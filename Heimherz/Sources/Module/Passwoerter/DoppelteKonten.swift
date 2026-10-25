import Foundation

/// Einträge, die dasselbe Konto sein dürften: gleicher Host und gleicher Benutzer.
struct DoppelteGruppe: Equatable, Identifiable, Sendable {
    /// Die ids, nach Name sortiert (stabil, auch wenn ein Eintrag mehrere Hosts hat).
    let ids: [String]
    var id: String { ids.joined(separator: "|") }
}

/// Findet doppelte Konten. Es wird nie etwas zusammengeführt oder gelöscht: das entscheidet Ahmed einzeln im Vergleich.
enum DoppelteKonten {
    /// Host ohne führendes `www.`, kleingeschrieben (`EintragSuche.host` macht schon klein).
    static func host(_ roh: String) -> String {
        roh.hasPrefix("www.") ? String(roh.dropFirst(4)) : roh
    }

    /// Gruppen mit mindestens zwei lebendigen Logins, die einen Host (ohne `www.`) und denselben Benutzer (ohne Groß- und Kleinschreibung) teilen.
    /// Einträge ohne Benutzer zählen nie (ohne Benutzer ist nicht klar, dass es dasselbe Konto ist). Hat ein Eintrag mehrere Hosts, wachsen die Gruppen zusammen.
    static func finde(_ eintraege: [Eintrag]) -> [DoppelteGruppe] {
        let logins = eintraege.filter { !$0.geloescht && $0.art == Eintrag.artLogin }
        var nachSchluessel: [String: [String]] = [:]
        for e in logins {
            let benutzer = e.benutzer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !benutzer.isEmpty else { continue }
            for h in Set(EintragSuche.hosts(von: e).map(host)) { nachSchluessel[h + "\u{0}" + benutzer, default: []].append(e.id) }
        }
        // Union-Find über die ids: wer in einer Gruppe zusammen steht, gehört zusammen.
        var eltern: [String: String] = [:]
        func wurzel(_ id: String) -> String {
            var w = id
            while let p = eltern[w], p != w { w = p }
            return w
        }
        for ids in nachSchluessel.values where ids.count > 1 {
            for id in ids where eltern[id] == nil { eltern[id] = id }
            let erste = wurzel(ids[0])
            for id in ids.dropFirst() {
                let w = wurzel(id)
                eltern[w] = erste
            }
        }
        let namen = Dictionary(logins.map { ($0.id, $0.name.lowercased()) }, uniquingKeysWith: { a, _ in a })
        func name(_ id: String) -> String { namen[id] ?? "" }
        let gruppen: [DoppelteGruppe] = Dictionary(grouping: eltern.keys) { wurzel($0) }.values.map { ids in
            DoppelteGruppe(ids: ids.sorted { (name($0), $0) < (name($1), $1) })
        }
        return gruppen.sorted { a, b in
            let ka = name(a.ids.first ?? ""), kb = name(b.ids.first ?? "")
            return ka == kb ? a.id < b.id : ka < kb
        }
    }
}
