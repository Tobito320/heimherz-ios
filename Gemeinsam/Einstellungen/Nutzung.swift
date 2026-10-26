import Foundation

/// Wann ein Konto zuletzt ausgefüllt oder kopiert wurde (für "Zuletzt benutzt"). Nur Eintrags-ids und Zeiten in der App Group, nie Inhalte.
/// Lokal je Handy, geht nicht an den PC.
struct Nutzung {
    let speicher: UserDefaults
    static let hoechstens = 200
    private static let schluessel = "nutzung.zuletzt"
    private static let zaehlerSchluessel = "nutzung.anzahl"

    init(speicher: UserDefaults? = UserDefaults(suiteName: Kennungen.appGruppe)) {
        self.speicher = speicher ?? .standard
    }

    /// id → Zeitpunkt der letzten Nutzung.
    var zuletzt: [String: Date] {
        let roh = speicher.dictionary(forKey: Self.schluessel) as? [String: Double] ?? [:]
        return roh.mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// id → wie oft benutzt (für die Reihenfolge der Vorschläge, W-030). Nur Zahlen je Konto-id, klein genug für die App Group.
    var anzahl: [String: Int] { speicher.dictionary(forKey: Self.zaehlerSchluessel) as? [String: Int] ?? [:] }

    func merke(id: String, jetzt: Date = Date()) {
        var zaehler = anzahl
        zaehler[id, default: 0] += 1
        speicher.set(zaehler, forKey: Self.zaehlerSchluessel)
        var roh = speicher.dictionary(forKey: Self.schluessel) as? [String: Double] ?? [:]
        roh[id] = jetzt.timeIntervalSince1970
        if roh.count > Self.hoechstens {
            for (alt, _) in roh.sorted(by: { $0.value < $1.value }).prefix(roh.count - Self.hoechstens) { roh[alt] = nil }
        }
        speicher.set(roh, forKey: Self.schluessel)
    }

    func vergiss() {
        speicher.removeObject(forKey: Self.schluessel)
        speicher.removeObject(forKey: Self.zaehlerSchluessel)
    }
}
