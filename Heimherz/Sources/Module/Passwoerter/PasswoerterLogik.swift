import Foundation

/// Die Kacheln der Passwörter-Startseite (wie die Passwörter-App von Apple). Die Reihenfolge ist die der Kacheln.
enum PasswoerterKategorie: String, CaseIterable, Hashable, Sendable {
    case alle, favoriten, passkeys, codes, sicherheit, geloescht

    var titel: String {
        switch self {
        case .alle: return "Alle"
        case .favoriten: return "Favoriten"
        case .passkeys: return "Passkeys"
        case .codes: return "Codes"
        case .sicherheit: return "Sicherheit"
        case .geloescht: return "Gelöscht"
        }
    }

    var symbol: String {
        switch self {
        case .alle: return "key.fill"
        case .favoriten: return "star.fill"
        case .passkeys: return "person.badge.key.fill"
        case .codes: return "lock.badge.clock.fill"
        case .sicherheit: return "exclamationmark"
        case .geloescht: return "trash.fill"
        }
    }
}

enum Sortierung: String, CaseIterable, Hashable, Sendable {
    case name, geaendert, zuletztBenutzt

    var titel: String {
        switch self {
        case .name: return "Name"
        case .geaendert: return "Zuletzt geändert"
        case .zuletztBenutzt: return "Zuletzt benutzt"
        }
    }
}

/// Ein Abschnitt der Liste: ein Buchstabe (A bis Z oder `#`) oder bei "Zuletzt geändert" ein einziger ohne Titel.
struct Abschnitt: Identifiable, Equatable, Sendable {
    let kennung: String
    let eintraege: [Eintrag]
    var id: String { kennung }
}

/// Ein Passkey, der zu einem Eintrag gehört: Seite und Konto. Nur zum Anzeigen; benutzen kann Heimherz sie noch nicht.
struct PasskeyKonto: Equatable, Sendable {
    let seite: String
    let konto: String
}

enum PasswoerterLogik {
    /// So lange ist ein gelöschter Eintrag in "Gelöscht" wiederherstellbar; danach leert die Bereinigung seine Felder.
    static let geloeschtTage = 30

    // MARK: Kategorien

    /// Die Einträge einer Kategorie. `Gelöscht` zeigt nur Grabsteine mit Inhalt und höchstens `geloeschtTage` alt; alles andere nur lebendige.
    /// `lecks`: ids mit Treffer in einem Datenleck (`LeckPruefung.lecks`); sie gehören zu "Sicherheit".
    static func eintraege(_ kategorie: PasswoerterKategorie, in tresor: Tresor, jetzt: Date = Date(), lecks: Set<String> = []) -> [Eintrag] {
        switch kategorie {
        case .alle: return tresor.lebendige
        case .favoriten: return tresor.lebendige.filter(\.favorit)
        case .passkeys: return tresor.lebendige.filter { !passkeys(von: $0).isEmpty }
        case .codes: return tresor.lebendige.filter(hatCode)
        case .sicherheit:
            let ids = Set(PasswortSicherheit.pruefe(tresor.lebendige, lecks: lecks).map(\.eintragId))
            return tresor.lebendige.filter { ids.contains($0.id) }
        case .geloescht: return tresor.eintraege.filter { istWiederherstellbar($0, jetzt: jetzt) }
        }
    }

    /// Die Zahlen der Kacheln: genau so viele Zeilen hat die Liste dahinter.
    static func zaehler(in tresor: Tresor, jetzt: Date = Date(), lecks: Set<String> = []) -> [PasswoerterKategorie: Int] {
        Dictionary(uniqueKeysWithValues: PasswoerterKategorie.allCases.map { ($0, eintraege($0, in: tresor, jetzt: jetzt, lecks: lecks).count) })
    }

    static func hatCode(_ e: Eintrag) -> Bool {
        e.art == Eintrag.artLogin && !e.totp.isEmpty && TOTP.einstellung(aus: e.totp) != nil
    }

    // MARK: Gelöscht

    static func istWiederherstellbar(_ e: Eintrag, jetzt: Date) -> Bool {
        guard e.geloescht, e.hatInhalt, let ms = Zeit.millis(iso: e.geaendert) else { return false }
        return ms >= grenze(jetzt: jetzt)
    }

    private static func grenze(jetzt: Date) -> Int64 {
        Int64((jetzt.timeIntervalSince1970 * 1000).rounded(.down)) - Int64(geloeschtTage) * 86_400_000
    }

    /// Leert die Felder von Grabsteinen, die älter als `geloeschtTage` sind (sie wären sonst bis zum 90. Tag unsichtbar, aber noch lesbar im Tresor).
    /// nil, wenn nichts zu tun ist. Der neue Zeitstempel ist nötig, sonst gewinnt beim Zusammenführen der Stein mit Inhalt (gleiches `geaendert`).
    static func bereinige(_ tresor: Tresor, jetzt: Date) -> Tresor? {
        let g = grenze(jetzt: jetzt)
        let stempel = Zeit.iso(jetzt)
        var geaendert = false
        var t = tresor
        for i in t.eintraege.indices {
            let e = t.eintraege[i]
            guard e.geloescht, e.hatInhalt, let ms = Zeit.millis(iso: e.geaendert), ms < g else { continue }
            t.eintraege[i] = e.endgueltigGeloescht(geaendert: stempel)
            geaendert = true
        }
        return geaendert ? t : nil
    }

    // MARK: Passkeys

    /// Passkeys eines Eintrags: aus dem Bitwarden-Import (`bitwardenFido2`) und aus dem Import aus Apple Passwörter (`passkeys`).
    static func passkeys(von e: Eintrag) -> [PasskeyKonto] {
        ["bitwardenFido2", "passkeys"].flatMap { feld in
            (e.unbekannt[feld]?.alsListe ?? []).compactMap { wert -> PasskeyKonto? in
                guard case .objekt(let d) = wert else { return nil }
                let rp = d["rpId"]?.alsText ?? ""
                let seite = [d["rpName"]?.alsText, rp].compactMap { $0 }.first { !$0.isEmpty } ?? ""
                let konto = [d["userName"]?.alsText, d["userDisplayName"]?.alsText].compactMap { $0 }.first { !$0.isEmpty } ?? ""
                guard !seite.isEmpty || !konto.isEmpty else { return nil }
                return PasskeyKonto(seite: seite, konto: konto)
            }
        }
    }

    // MARK: Abschnitte

    /// Der Buchstabe für die A bis Z Leiste: erster Buchstabe des Namens ohne Akzente und Umlautpunkte, sonst `#`.
    static func buchstabe(_ name: String) -> String {
        guard let z = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let grund = String(z).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        guard let a = grund.unicodeScalars.first, a.value >= 65, a.value <= 90 else { return "#" }
        return String(a)
    }

    /// Nach Name: je Buchstabe ein Abschnitt, `#` zuletzt. Nach "Zuletzt geändert": ein einziger Abschnitt, neueste zuerst.
    /// Nach "Zuletzt benutzt": ein Abschnitt, zuletzt ausgefüllte oder kopierte zuerst (`benutzt`: id → Zeitpunkt), nie benutzte danach nach Name.
    static func abschnitte(_ eintraege: [Eintrag], sortierung: Sortierung, benutzt: [String: Date] = [:]) -> [Abschnitt] {
        switch sortierung {
        case .zuletztBenutzt:
            guard !eintraege.isEmpty else { return [] }
            let mit = eintraege.filter { benutzt[$0.id] != nil }.sorted { a, b in
                let ta = benutzt[a.id] ?? .distantPast, tb = benutzt[b.id] ?? .distantPast
                return ta == tb ? a.id < b.id : ta > tb
            }
            let ohne = EintragSuche.sortiert(eintraege.filter { benutzt[$0.id] == nil })
            return [Abschnitt(kennung: "", eintraege: mit + ohne)]
        case .geaendert:
            guard !eintraege.isEmpty else { return [] }
            let sortiert = eintraege.sorted { a, b in
                let ma = Zeit.millis(iso: a.geaendert) ?? 0, mb = Zeit.millis(iso: b.geaendert) ?? 0
                return ma == mb ? a.id < b.id : ma > mb
            }
            return [Abschnitt(kennung: "", eintraege: sortiert)]
        case .name:
            let gruppen = Dictionary(grouping: EintragSuche.sortiert(eintraege)) { buchstabe($0.name) }
            let schluessel = gruppen.keys.sorted { a, b in
                if a == "#" { return false }
                if b == "#" { return true }
                return a < b
            }
            return schluessel.map { Abschnitt(kennung: $0, eintraege: gruppen[$0] ?? []) }
        }
    }

    // MARK: Codes

    /// Die letzten Sekunden eines Codes, in denen schon der nächste klein daneben steht.
    static let vorschauSekunden = 5

    /// Der Code, der beim Antippen in die Zwischenablage geht: der laufende, in den letzten `vorschauSekunden` der nächste.
    /// nil ohne lesbares Geheimnis. Perioden bis `vorschauSekunden` zeigen nie einen nächsten (sonst wäre er immer dran).
    static func codeZumKopieren(_ totp: String, datum: Date) -> (code: String, istNaechster: Bool)? {
        guard let z = TOTPAnzeige.zustand(totp, datum: datum) else { return nil }
        guard let n = naechsterCode(totp, datum: datum) else { return (z.code, false) }
        return (n, true)
    }

    /// Der Code der nächsten Periode, aber nur in den letzten `vorschauSekunden` des laufenden. Sonst nil.
    static func naechsterCode(_ totp: String, datum: Date) -> String? {
        guard let e = TOTP.einstellung(aus: totp), e.periode > vorschauSekunden else { return nil }
        let zeit = Int(datum.timeIntervalSince1970)
        let rest = TOTP.restsekunden(e, zeit: zeit)
        guard rest <= vorschauSekunden else { return nil }
        return TOTP.code(e, zeit: zeit + rest)
    }

    // MARK: Passwort ändern

    /// `https://<host>/.well-known/change-password` (Apple/W3C: Seiten leiten dort auf ihre Seite zum Ändern). nil ohne Host oder bei Notizen und Gelöschtem.
    static func passwortAendernURL(von e: Eintrag) -> URL? {
        guard !e.geloescht, e.art == Eintrag.artLogin, let host = EintragSuche.hosts(von: e).first else { return nil }
        var teile = URLComponents()
        teile.scheme = "https"
        teile.host = host
        teile.path = "/.well-known/change-password"
        return teile.url
    }

    // MARK: Frühere Passwörter

    /// Ein früheres Passwort: der Text und (ISO) bis wann es galt, leer wenn unbekannt.
    struct FruehereZeile: Equatable, Sendable {
        let passwort: String
        let bis: String
    }

    /// Alle früheren Passwörter eines Eintrags: `passwortVerlauf` (Heim, `{passwort, bis}`) und `bitwardenVerlauf` (Bitwarden, `{password, lastUsedDate}`),
    /// ohne Doppelte (gleiches Passwort zur gleichen Zeit), das aktuelle Passwort nicht, neueste zuerst.
    static func fruehere(von e: Eintrag) -> [FruehereZeile] {
        var zeilen: [FruehereZeile] = []
        for w in e.unbekannt["passwortVerlauf"]?.alsListe ?? [] {
            guard case .objekt(let d) = w, let p = d["passwort"]?.alsText, !p.isEmpty else { continue }
            zeilen.append(FruehereZeile(passwort: p, bis: d["bis"]?.alsText ?? ""))
        }
        for w in e.unbekannt["bitwardenVerlauf"]?.alsListe ?? [] {
            guard case .objekt(let d) = w, let p = d["password"]?.alsText, !p.isEmpty else { continue }
            zeilen.append(FruehereZeile(passwort: p, bis: d["lastUsedDate"]?.alsText ?? ""))
        }
        var gesehen = Set<String>()
        let ohneDoppelte = zeilen.filter { $0.passwort != e.passwort }.filter { gesehen.insert($0.passwort + "\u{0}" + $0.bis).inserted }
        // sortiert ist stabil genug: gleiche Zeit bleibt in der Reihenfolge der Quelle (Heim vor Bitwarden)
        return ohneDoppelte.enumerated().sorted { a, b in
            let ma = Zeit.millis(iso: a.element.bis) ?? Int64.min, mb = Zeit.millis(iso: b.element.bis) ?? Int64.min
            return ma == mb ? a.offset < b.offset : ma > mb
        }.map(\.element)
    }
}
