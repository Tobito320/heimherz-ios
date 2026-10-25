import AuthenticationServices
import Foundation

/// Hosts, Zuordnung zu Anfragen und Suche über Einträge. Rein und ohne Oberfläche: Passwörter-Liste und AutoFill-Erweiterung nutzen dieselbe Zuordnung.
enum EintragSuche {
    /// Der Host einer gespeicherten URL oder eines Service-Bezeichners, kleingeschrieben. Auch ohne Schema (`github.com/login`). nil ohne Host.
    static func host(von text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let mitSchema = t.contains("://") ? t : "https://" + t
        guard var host = URLComponents(string: mitSchema)?.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Alle Hosts der URLs eines Eintrags, ohne Doppelte, in Reihenfolge.
    static func hosts(von eintrag: Eintrag) -> [String] {
        var gesehen = Set<String>()
        return eintrag.urls.compactMap(host(von:)).filter { gesehen.insert($0).inserted }
    }

    /// Host eines Service-Bezeichners; nur `.domain` und `.URL` haben einen (`.app` gibt es erst ab iOS 26.2 und meint eine Bundle-ID).
    static func host(von bezeichner: ASCredentialServiceIdentifier) -> String? {
        bezeichner.type == .domain || bezeichner.type == .URL ? host(von: bezeichner.identifier) : nil
    }

    /// Hosts der Anfrage der App oder Webseite.
    static func hosts(von bezeichner: [ASCredentialServiceIdentifier]) -> [String] {
        bezeichner.compactMap { host(von: $0) }
    }

    /// Gleicher Host, oder einer ist Unterdomain des anderen an der Punktgrenze (`m.example.com` passt zu `example.com`,
    /// `evilexample.com` nicht; ein Rest ohne Punkt wie `com` passt nie).
    /// shortcut: keine Public-Suffix-Liste, `a.co.uk` passt zu einem Eintrag `co.uk`; Einträge heißen in der Praxis nie so, bei Bedarf Liste ergänzen.
    static func passt(eintragHost: String, anfrageHost: String) -> Bool {
        if eintragHost == anfrageHost { return true }
        return istUnterdomain(eintragHost, von: anfrageHost) || istUnterdomain(anfrageHost, von: eintragHost)
    }

    private static func istUnterdomain(_ lang: String, von kurz: String) -> Bool {
        kurz.contains(".") && lang.hasSuffix("." + kurz)
    }

    /// Lebendige Logins (AutoFill kennt keine Notizen), nach Name sortiert.
    static func logins(in eintraege: [Eintrag]) -> [Eintrag] {
        sortiert(eintraege.filter { !$0.geloescht && $0.art == Eintrag.artLogin })
    }

    /// Logins, deren URL zu einem der Hosts passt, und die übrigen. Beide nach Name.
    static func aufteilen(_ eintraege: [Eintrag], anfrageHosts: [String]) -> (passend: [Eintrag], uebrige: [Eintrag]) {
        let alle = logins(in: eintraege)
        guard !anfrageHosts.isEmpty else { return ([], alle) }
        let passend = alle.filter { e in
            hosts(von: e).contains { eh in anfrageHosts.contains { passt(eintragHost: eh, anfrageHost: $0) } }
        }
        // Genau der Host der Anfrage vor Treffern über eine Unterdomain; innerhalb jeder Gruppe bleibt die Namensreihenfolge.
        let exakt = passend.filter { e in hosts(von: e).contains { anfrageHosts.contains($0) } }
        let exaktIds = Set(exakt.map(\.id))
        let geordnet = exakt + passend.filter { !exaktIds.contains($0.id) }
        let ids = Set(passend.map(\.id))
        return (geordnet, alle.filter { !ids.contains($0.id) })
    }

    static func sortiert(_ eintraege: [Eintrag]) -> [Eintrag] {
        eintraege.sorted { a, b in
            let r = a.name.localizedStandardCompare(b.name)
            return r == .orderedSame ? a.id < b.id : r == .orderedAscending
        }
    }

    /// Jedes Wort des Suchbegriffs muss in Name, Benutzer oder einem Host vorkommen (ohne Groß/Klein und Akzente). Leer = alle.
    static func filtern(_ eintraege: [Eintrag], begriff: String) -> [Eintrag] {
        let woerter = begriff.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !woerter.isEmpty else { return eintraege }
        return eintraege.filter { e in
            let heu = ([e.name, e.benutzer] + hosts(von: e)).joined(separator: "\n")
            return woerter.allSatisfy { heu.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
