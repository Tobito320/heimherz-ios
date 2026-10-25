import Foundation

/// ISO-Zeitstempel des Tresors (`geaendert`): `2026-10-25T01:40:00.000Z`, immer UTC mit Millisekunden.
/// Gerechnet wird in ganzen Millisekunden (Int), nie mit `Date`-Kommazahlen, damit Vergleiche auf beiden Seiten gleich ausgehen.
/// shortcut: nur die Form `JJJJ-MM-TTTHH:MM:SS[.f…]Z` wird gelesen (so schreiben TS und Swift); Offsets und Kalendertage wie 30. Februar prüft es nicht, bei fremden Schreibern erweitern.
enum Zeit {
    /// Millisekunden seit 1970 oder nil, wenn der Text nicht die erwartete Form hat.
    static func millis(iso text: String) -> Int64? {
        let b = Array(text.utf8)
        func zahl(_ von: Int, _ n: Int) -> Int? {
            guard von + n <= b.count else { return nil }
            var w = 0
            for i in von..<(von + n) {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                w = w * 10 + Int(b[i] - 48)
            }
            return w
        }
        guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58,
              let jahr = zahl(0, 4), let monat = zahl(5, 2), let tag = zahl(8, 2),
              let stunde = zahl(11, 2), let minute = zahl(14, 2), let sekunde = zahl(17, 2) else { return nil }
        var ms = 0
        var i = 19
        if b[i] == 46 {
            i += 1
            var stellen = 0
            while i < b.count, b[i] >= 48, b[i] <= 57 {
                if stellen < 3 { ms = ms * 10 + Int(b[i] - 48); stellen += 1 }
                i += 1
            }
            guard stellen > 0 else { return nil }
            while stellen < 3 { ms *= 10; stellen += 1 }
        }
        guard i == b.count - 1, b[i] == 90 else { return nil }
        guard (1...12).contains(monat), (1...31).contains(tag), stunde < 24, minute < 60, sekunde < 61 else { return nil }
        let tage = tageSeit1970(jahr: jahr, monat: monat, tag: tag)
        let sekunden = tage * 86_400 + stunde * 3_600 + minute * 60 + sekunde
        return Int64(sekunden) * 1000 + Int64(ms)
    }

    /// ISO-Text mit Millisekunden (abgerundet) in UTC.
    static func iso(_ datum: Date) -> String {
        iso(millis: Int64((datum.timeIntervalSince1970 * 1000).rounded(.down)))
    }

    static func iso(millis: Int64) -> String {
        let sekunden = Int((millis >= 0 ? millis : millis - 999) / 1000)
        let ms = Int(millis - Int64(sekunden) * 1000)
        var tage = sekunden / 86_400
        var rest = sekunden - tage * 86_400
        if rest < 0 { rest += 86_400; tage -= 1 }
        let (j, m, t) = datumAusTagen(tage)
        func z(_ n: Int, _ stellen: Int) -> String { String(repeating: "0", count: max(0, stellen - String(n).count)) + String(n) }
        return "\(z(j, 4))-\(z(m, 2))-\(z(t, 2))T\(z(rest / 3_600, 2)):\(z(rest % 3_600 / 60, 2)):\(z(rest % 60, 2)).\(z(ms, 3))Z"
    }

    // Tage seit 1970-01-01 (Howard Hinnant, days_from_civil)
    private static func tageSeit1970(jahr: Int, monat: Int, tag: Int) -> Int {
        let y = monat <= 2 ? jahr - 1 : jahr
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (monat + (monat > 2 ? -3 : 9)) + 2) / 5 + tag - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    // (civil_from_days)
    private static func datumAusTagen(_ tage: Int) -> (Int, Int, Int) {
        let z = tage + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let tag = doy - (153 * mp + 2) / 5 + 1
        let monat = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (monat <= 2 ? 1 : 0), monat, tag)
    }
}
