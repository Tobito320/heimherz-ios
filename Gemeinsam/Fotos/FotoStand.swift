import Foundation

/// Was Handy und Erweiterung über den Foto-Abgleich wissen; eine Datei in der App Group (`fotos-stand.json`).
/// Neue Felder immer optional. App und Erweiterung schreiben beide; verloren gehen kann höchstens ein Eintrag, der Server nimmt Doppeltes ohnehin nur einmal an.
struct FotoStand: Codable, Sendable, Equatable {
    /// Kennungen der Assets, deren Dateien alle am PC liegen.
    var fertig: Set<String> = []
    /// Schlüssel (`kennung/name`) einzelner Dateien am PC, solange ihr Asset noch nicht in `fertig` steht.
    var teil: Set<String> = []
    var letzteUebertragung: Date?
    /// Letzter Fehler in Klartext; nil, wenn der letzte Lauf sauber war.
    var fehler: String?
    /// nil = Standard (an).
    var nurWLAN: Bool?
    /// Schlüssel der Dateien, für die die Erweiterung einen Upload-Job angelegt hat, mit Zeit (iOS zeigt laufende Jobs erst ab 26.5).
    var eingereicht: [String: Date]?
    /// Anzahl Assets bei der letzten Zählung (für die Anzeige, wenn der PC gerade aus ist).
    var gesamt: Int?

    var wlanNoetig: Bool { nurWLAN ?? true }

    /// Schlüssel mit einem Job, der jünger als drei Tage ist; ältere gelten als verschwunden und werden neu versucht.
    func unterwegs(jetzt: Date) -> Set<String> {
        Set((eingereicht ?? [:]).filter { jetzt.timeIntervalSince($0.value) < 3 * 86_400 }.keys)
    }

    func istErledigt(_ r: FotoRessource) -> Bool { teil.contains(r.schluessel) }

    /// Übernimmt die Liste des Servers und räumt `teil` um Assets auf, die schon in `fertig` stehen.
    mutating func uebernimm(bekannt: [BekanntesFoto]) {
        teil.formUnion(bekannt.map { FotoRegeln.schluessel(kennung: $0.kennung, name: $0.ressource) })
    }

    mutating func raeumeAuf() {
        teil = teil.filter { !fertig.contains(String($0.prefix { $0 != "/" })) }
    }
}

/// Liest und schreibt `FotoStand` atomar. Ohne App Group (Tests, Simulator ohne Entitlement) in einem frei wählbaren Ordner.
struct FotoStandAblage: Sendable {
    let datei: URL

    init(ordner: URL) { datei = ordner.appending(path: "fotos-stand.json") }

    static func appGruppe() -> FotoStandAblage? { Kennungen.gruppenOrdner().map { FotoStandAblage(ordner: $0) } }

    func lade() -> FotoStand {
        guard let daten = try? Data(contentsOf: datei) else { return FotoStand() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode(FotoStand.self, from: daten)) ?? FotoStand()
    }

    func speichere(_ stand: FotoStand) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        guard let daten = try? e.encode(stand) else { return }
        try? FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? daten.write(to: datei, options: [.atomic])
    }

    /// Liest, ändert, schreibt.
    func aendere(_ f: (inout FotoStand) -> Void) {
        var s = lade()
        f(&s)
        speichere(s)
    }
}

/// Ergebnis der Zählung (SPEC 11: gesamt, am PC, offen).
struct FotoZahlen: Sendable, Equatable {
    var gesamt: Int
    var amPC: Int
    var offen: Int { max(0, gesamt - amPC) }
}

/// Reine Planung: was ist noch offen? `ressourcen` holt die Dateien eines Assets (PhotoKit, teuer), wird für fertige Assets nie gerufen.
enum FotoPlan {
    struct Ergebnis: Sendable, Equatable {
        var zahlen: FotoZahlen
        var offen: [FotoRessource]
        /// Assets, die jetzt vollständig am PC liegen und zu `FotoStand.fertig` kommen.
        var neuFertig: Set<String>
    }

    /// Geht die Köpfe (neueste zuerst) durch. `hoechstens` bricht die Suche ab, sobald so viele offene Dateien gefunden sind
    /// (Erweiterung: nur so viele, wie noch Platz für Jobs ist); die Zahlen sind dann unvollständig.
    /// `uebersprungen`: Schlüssel, die schon als Job unterwegs sind.
    static func plane(koepfe: [FotoKopf], stand: FotoStand, uebersprungen: Set<String> = [], hoechstens: Int? = nil, ressourcen: (FotoKopf) -> [FotoRessource]) -> Ergebnis {
        var amPC = 0
        var offen: [FotoRessource] = []
        var neu: Set<String> = []
        for kopf in koepfe {
            if stand.fertig.contains(kopf.kennung) { amPC += 1; continue }
            let alle = ressourcen(kopf)
            let fehlt = alle.filter { !stand.istErledigt($0) }
            if fehlt.isEmpty { amPC += 1; neu.insert(kopf.kennung); continue }
            offen.append(contentsOf: fehlt.filter { !uebersprungen.contains($0.schluessel) })
            if let hoechstens, offen.count >= hoechstens { offen = Array(offen.prefix(hoechstens)); break }
        }
        return Ergebnis(zahlen: FotoZahlen(gesamt: koepfe.count, amPC: amPC), offen: offen, neuFertig: neu)
    }
}
