import Foundation

/// Was beim Speichern aus der Erweiterung (iOS 26.2, "In Heimherz sichern?") mit dem Tresor passiert.
enum SpeicherAktion: Equatable, Sendable {
    /// Es gibt noch kein Konto mit diesem Benutzer auf dieser Webseite.
    case neu(Eintrag)
    /// Konto da, aber mit anderem Passwort: der Eintrag mit dem neuen Passwort.
    case aktualisieren(Eintrag)
    /// Konto mit genau diesem Passwort ist schon da.
    case vorhanden
}

enum PasswortSpeichern {
    /// So viele alte Passwörter bleiben am Eintrag (`passwortVerlauf`, ein Feld, das der Tresor nicht kennt und das darum erhalten bleibt).
    static let verlaufMax = 5

    /// Sucht ein lebendiges Login mit gleichem Benutzer (ohne Groß/Klein) und passendem Host; ein Eintrag mit genau diesem Host geht vor einem über eine Unterdomain.
    /// Ohne Host (App statt Webseite) zählt der Name.
    static func plane(in tresor: Tresor, host: String?, name: String, benutzer: String, passwort: String, jetzt: Date) -> SpeicherAktion {
        let kandidaten = tresor.lebendige.filter { e in
            guard e.art == Eintrag.artLogin, e.benutzer.caseInsensitiveCompare(benutzer) == .orderedSame else { return false }
            guard let host else { return e.urls.isEmpty && e.name == name }
            return EintragSuche.hosts(von: e).contains { EintragSuche.passt(eintragHost: $0, anfrageHost: host) }
        }
        let treffer = kandidaten.first { e in host.map { EintragSuche.hosts(von: e).contains($0) } ?? false } ?? kandidaten.first
        let stempel = Zeit.iso(jetzt)
        if var e = treffer {
            if e.passwort == passwort { return .vorhanden }
            e.unbekannt["passwortVerlauf"] = verlauf(von: e, bis: stempel)
            e.passwort = passwort
            e.geaendert = stempel
            return .aktualisieren(e)
        }
        let urls = host.map { ["https://" + $0] } ?? []
        return .neu(Eintrag(name: name.isEmpty ? (host ?? "Konto") : name, benutzer: benutzer, passwort: passwort, urls: urls, geaendert: stempel))
    }

    /// Der Verlauf mit dem jetzigen Passwort vorn: Liste von `{passwort, bis}`, neueste zuerst, höchstens `verlaufMax`.
    private static func verlauf(von e: Eintrag, bis: String) -> JSONWert {
        var liste = e.unbekannt["passwortVerlauf"]?.alsListe ?? []
        if !e.passwort.isEmpty { liste.insert(.objekt(["passwort": .text(e.passwort), "bis": .text(bis)]), at: 0) }
        return .liste(Array(liste.prefix(verlaufMax)))
    }

    /// Hinweis für den Dialog "Passwort aktualisieren?", wenn der Eintrag nur über eine Unterdomain gepasst hat (Seite `login.example.org`, Eintrag `example.org`).
    static func hostHinweis(fuer e: Eintrag, anfrageHost: String?) -> String? {
        guard let anfrageHost else { return nil }
        let hosts = EintragSuche.hosts(von: e)
        guard !hosts.isEmpty, !hosts.contains(anfrageHost) else { return nil }
        return "Das Konto gehört zu \(hosts.joined(separator: ", ")), du bist auf \(anfrageHost)."
    }

    /// Legt den Eintrag an oder ersetzt den mit gleicher id (zweimaliges Anwenden ergibt keinen Doppelten).
    static func anwenden(_ aktion: SpeicherAktion, auf tresor: Tresor) -> Tresor {
        var t = tresor
        switch aktion {
        case .vorhanden:
            break
        case .neu(let e), .aktualisieren(let e):
            if let i = t.eintraege.firstIndex(where: { $0.id == e.id }) { t.eintraege[i] = e } else { t.eintraege.append(e) }
        }
        return t
    }
}

/// Ein Vorschlag für die Passwort-Erzeugung ("Starkes Passwort" und so weiter im System-Dialog ab iOS 26.2).
struct PasswortVorschlag: Equatable, Sendable {
    enum Art: Sendable { case stark, alphanumerisch, wortgruppe }
    let art: Art
    let wert: String
}

enum PasswortVorschlaege {
    /// Liest `minlength` und `maxlength` aus Apples Passwort-Regeln (`required: lower; minlength: 8; maxlength: 20`).
    /// shortcut: `required`/`allowed`/`max-consecutive` werden nicht ausgewertet; die drei Vorschläge sind unterschiedlich genug, dass meist einer passt. Bei Bedarf Regeln voll lesen.
    static func laengenGrenzen(aus regeln: String?) -> (min: Int?, max: Int?) {
        var min: Int?, max: Int?
        for teil in (regeln ?? "").split(separator: ";") {
            let kv = teil.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard kv.count == 2, let n = Int(kv[1]) else { continue }
            if kv[0] == "minlength" { min = n } else if kv[0] == "maxlength" { max = n }
        }
        return (min, max)
    }

    /// Drei Vorschläge; Länge innerhalb der Grenzen der Seite, soweit sie mit dem Generator (8 bis 64) vereinbar sind.
    static func erzeuge<G: RandomNumberGenerator>(regeln: [String?], mit zufall: inout G) -> [PasswortVorschlag] {
        let grenzen = regeln.compactMap { $0 }.map { laengenGrenzen(aus: $0) }
        let kleinste = grenzen.compactMap { $0.min }.max()
        let groesste = grenzen.compactMap { $0.max }.min()
        var laenge = 20
        if let kleinste { laenge = Swift.max(laenge, kleinste) }
        if let groesste { laenge = Swift.min(laenge, groesste) }
        laenge = Swift.min(Swift.max(laenge, PasswortGenerator.laengen.lowerBound), PasswortGenerator.laengen.upperBound)

        var stark = PasswortRegeln()
        stark.laenge = laenge
        var alnum = stark
        alnum.sonderzeichen = false
        var wort = PasswortRegeln()
        wort.modus = .wortgruppe

        let alle = [
            PasswortVorschlag(art: .stark, wert: PasswortGenerator.erzeuge(stark, mit: &zufall)),
            PasswortVorschlag(art: .alphanumerisch, wert: PasswortGenerator.erzeuge(alnum, mit: &zufall)),
            PasswortVorschlag(art: .wortgruppe, wert: PasswortGenerator.erzeuge(wort, mit: &zufall))
        ]
        // Was länger als die Obergrenze der Seite ist (z. B. maxlength unter 8, dem Minimum des Generators), wird nicht angeboten.
        return alle.filter { v in groesste.map { v.wert.count <= $0 } ?? true }
    }
}
