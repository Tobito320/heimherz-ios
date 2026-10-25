import Foundation

/// TestFlight-Builds laufen nach 90 Tagen ab. Das Build-Datum (`HeimherzBuildDatum` im Info.plist, `JJJJ-MM-TT`, UTC) setzt `testflight.yml`.
/// Die App warnt ab Tag 75 ("Build läuft in N Tagen ab"), damit rechtzeitig ein neuer Build nötig wird (SPEC 2).
enum BuildAblauf {
    static let gueltigeTage = 90
    static let warnungAbTag = 75

    struct Hinweis: Equatable {
        let text: String
        let abgelaufen: Bool
    }

    static func buildDatum(_ text: String?) -> Date? {
        guard let text, let ms = Zeit.millis(iso: text + "T00:00:00.000Z") else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    /// Verbleibende ganze Tage (0 = läuft heute ab, negativ = abgelaufen). nil ohne gültiges Datum (Debug-Builds, Simulator).
    static func verbleibendeTage(buildDatum text: String?, jetzt: Date) -> Int? {
        guard let start = buildDatum(text) else { return nil }
        let alter = Int((jetzt.timeIntervalSince(start) / 86_400).rounded(.down))
        return gueltigeTage - alter
    }

    /// Der Hinweis, erst ab Tag 75 nach dem Build; vorher nil.
    static func hinweis(buildDatum text: String?, jetzt: Date) -> Hinweis? {
        guard let rest = verbleibendeTage(buildDatum: text, jetzt: jetzt), rest <= gueltigeTage - warnungAbTag else { return nil }
        switch rest {
        case ..<0: return Hinweis(text: "Dieser Build ist abgelaufen. Bitte den neuen Build aus TestFlight laden.", abgelaufen: true)
        case 0: return Hinweis(text: "Build läuft heute ab", abgelaufen: false)
        case 1: return Hinweis(text: "Build läuft in 1 Tag ab", abgelaufen: false)
        default: return Hinweis(text: "Build läuft in \(rest) Tagen ab", abgelaufen: false)
        }
    }
}
