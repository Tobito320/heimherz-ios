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
    /// Originale aus iCloud laden, wenn sie nicht auf dem Handy liegen. nil = Standard (ja).
    var iCloudLaden: Bool?
    /// Ahmed hat zuletzt "Anhalten" gedrückt (SPEC 31, W-003): dann startet der Abgleich nicht von selbst; "Abgleich starten" hebt es auf. nil = nein.
    var angehaltenVomNutzer: Bool?
    /// Ahmed hat die Foto-Erweiterung selbst ausgeschaltet: die App schaltet sie dann nicht wieder ein. nil = nein (Standard an).
    var erweiterungAus: Bool?

    var nutzerHatAngehalten: Bool { angehaltenVomNutzer ?? false }
    var nutzerHatErweiterungAusgeschaltet: Bool { erweiterungAus ?? false }
    var wlanNoetig: Bool { nurWLAN ?? true }
    var iCloudErlaubt: Bool { iCloudLaden ?? true }

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
        teil = teil.filter { !fertig.contains(FotoRegeln.kennung(vonSchluessel: $0)) }
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

/// Zahlen je Phase: erst alle Fotos (mit Live Photos), dann alle Videos.
struct FotoPhasen: Sendable, Equatable {
    var fotosGesamt = 0
    var fotosAmPC = 0
    var videosGesamt = 0
    var videosAmPC = 0
    var fotosOffen: Int { max(0, fotosGesamt - fotosAmPC) }
    var videosOffen: Int { max(0, videosGesamt - videosAmPC) }
}

/// Reine Planung: was ist noch offen? `ressourcen` holt die Dateien eines Assets (PhotoKit, teuer), wird für fertige Assets nie gerufen.
enum FotoPlan {
    struct Ergebnis: Sendable, Equatable {
        var zahlen: FotoZahlen
        var offen: [FotoRessource]
        /// Assets, die jetzt vollständig am PC liegen und zu `FotoStand.fertig` kommen.
        var neuFertig: Set<String>
        /// Je Kennung eines Assets in `offen`: wie viele Dateien ihm am PC noch fehlen. Sind alle gesendet, ist das Asset fertig.
        var fehlend: [String: Int] = [:]
        var phasen = FotoPhasen()
    }

    /// Geht die Köpfe (neueste zuerst) durch. `hoechstens` bricht die Suche ab, sobald so viele offene Dateien gefunden sind
    /// (Erweiterung: nur so viele, wie noch Platz für Jobs ist); die Zahlen sind dann unvollständig.
    /// `zaehleAlles`: nach dem Stück weiter zählen, aber nur Assets nachschlagen, von denen der PC schon Dateien kennt
    /// (alle anderen sind sicher offen). So bleiben die Zahlen vollständig, ohne bei 8000 Assets alle Dateilisten zu lesen.
    /// `uebersprungen`: Schlüssel, die schon als Job unterwegs sind oder in diesem Lauf nicht gingen.
    static func plane(koepfe alle: [FotoKopf], stand: FotoStand, uebersprungen: Set<String> = [], hoechstens: Int? = nil, zaehleAlles: Bool = false,
                      ressourcen: (FotoKopf) -> [FotoRessource]) -> Ergebnis {
        // Erst alle Fotos, dann alle Videos, in jeder Gruppe die Reihenfolge der Mediathek (neueste zuerst). Die kleinen Dateien gehen so zuerst durch.
        let koepfe = alle.filter { !$0.istVideo } + alle.filter(\.istVideo)
        var phasen = FotoPhasen(fotosGesamt: alle.count { !$0.istVideo }, videosGesamt: alle.count { $0.istVideo })
        var amPC = 0
        var offen: [FotoRessource] = []
        var neu: Set<String> = []
        var fehlend: [String: Int] = [:]
        let bekannt: Set<String> = zaehleAlles ? Set(stand.teil.map(FotoRegeln.kennung(vonSchluessel:))) : []
        var voll = zaehleAlles && hoechstens == 0
        for kopf in koepfe {
            func zaehleAmPC() {
                amPC += 1
                if kopf.istVideo { phasen.videosAmPC += 1 } else { phasen.fotosAmPC += 1 }
            }
            if stand.fertig.contains(kopf.kennung) { zaehleAmPC(); continue }
            if voll, !bekannt.contains(kopf.kennung) { continue }
            let alle = ressourcen(kopf)
            let fehlt = alle.filter { !stand.istErledigt($0) }
            if fehlt.isEmpty { zaehleAmPC(); neu.insert(kopf.kennung); continue }
            if voll { continue }
            offen.append(contentsOf: fehlt.filter { !uebersprungen.contains($0.schluessel) })
            fehlend[kopf.kennung] = fehlt.count
            if let hoechstens, offen.count >= hoechstens {
                offen = Array(offen.prefix(hoechstens))
                if zaehleAlles { voll = true } else { break }
            }
        }
        return Ergebnis(zahlen: FotoZahlen(gesamt: koepfe.count, amPC: amPC), offen: offen, neuFertig: neu, fehlend: fehlend, phasen: phasen)
    }
}
