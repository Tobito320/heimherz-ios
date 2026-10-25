import Foundation

/// Die vier Gruppen der Passwort-Gesundheit (W-037). Getrennt von `PasswortSicherheit`: dessen Zahl steht auf der Kachel "Sicherheit" und
/// bestimmt die Zeilen der Liste; "ohne 2FA" würde fast jeden Eintrag dort markieren.
enum GesundheitGruppe: Int, CaseIterable, Sendable {
    case schwach, gleich, alt, ohne2FA

    var titel: String {
        switch self {
        case .schwach: return "Schwach"
        case .gleich: return "Gleiches Passwort"
        case .alt: return "Alt"
        case .ohne2FA: return "Ohne 2FA"
        }
    }

    var erklaerung: String {
        switch self {
        case .schwach: return "Kurz, einfach zu erraten oder ein bekanntes Muster."
        case .gleich: return "Dasselbe Passwort steckt in mehreren Einträgen."
        case .alt: return "Seit über einem Jahr nicht geändert."
        case .ohne2FA: return "Kein Code (2FA) und kein Passkey hinterlegt."
        }
    }

    var symbol: String {
        switch self {
        case .schwach: return "exclamationmark.shield"
        case .gleich: return "doc.on.doc"
        case .alt: return "clock.arrow.circlepath"
        case .ohne2FA: return "lock.open"
        }
    }
}

/// Wird nur im Speicher berechnet: enthält ids, nie ein Passwort. Zählt lebendige Logins mit Passwort.
struct PasswortGesundheit: Equatable, Sendable {
    /// Älter als so viele Tage gilt als "alt". `geaendert` ändert sich bei jeder Änderung (auch Favorit): eine Näherung an "Passwort zuletzt geändert".
    static let altTage = 365

    let gruppen: [GesundheitGruppe: [String]]

    func ids(_ g: GesundheitGruppe) -> [String] { gruppen[g] ?? [] }
    func anzahl(_ g: GesundheitGruppe) -> Int { ids(g).count }
    var istLeer: Bool { GesundheitGruppe.allCases.allSatisfy { ids($0).isEmpty } }

    static func pruefe(_ eintraege: [Eintrag], jetzt: Date = Date()) -> PasswortGesundheit {
        let logins = eintraege.filter { !$0.geloescht && $0.art == Eintrag.artLogin && !$0.passwort.isEmpty }
        var haeufigkeit: [String: Int] = [:]
        for e in logins { haeufigkeit[e.passwort, default: 0] += 1 }
        let grenze = Int64((jetzt.timeIntervalSince1970 * 1000).rounded(.down)) - Int64(altTage) * 86_400_000
        var g: [GesundheitGruppe: [String]] = [:]
        for e in logins {
            if PasswortSicherheit.istSchwach(e.passwort, benutzer: e.benutzer, name: e.name) { g[.schwach, default: []].append(e.id) }
            if (haeufigkeit[e.passwort] ?? 0) > 1 { g[.gleich, default: []].append(e.id) }
            if let ms = Zeit.millis(iso: e.geaendert), ms < grenze { g[.alt, default: []].append(e.id) }
            if !PasswoerterLogik.hatCode(e), PasswoerterLogik.passkeys(von: e).isEmpty { g[.ohne2FA, default: []].append(e.id) }
        }
        return PasswortGesundheit(gruppen: g)
    }
}
