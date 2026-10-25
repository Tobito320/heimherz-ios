import Foundation

/// Messung eines Laufs: Dateien und Bytes seit dem Start ergeben Geschwindigkeit und Restzeit. Die Uhr kommt von außen (Test).
struct FotoTempo: Sendable, Equatable {
    let start: Date
    private(set) var dateien = 0
    private(set) var bytes: Int64 = 0

    init(start: Date) { self.start = start }

    mutating func buche(bytes neu: Int64) {
        dateien += 1
        bytes += neu
    }

    /// Erst nach zwei Sekunden und mit mindestens einem übertragenen Byte, vorher wäre die Zahl Zufall.
    func bytesProSekunde(jetzt: Date) -> Double? {
        let t = jetzt.timeIntervalSince(start)
        guard t >= 2, bytes > 0 else { return nil }
        return Double(bytes) / t
    }

    /// Restzeit aus dem bisherigen Schnitt je Datei. `offen` sind Assets, Live Photos haben zwei Dateien, die Schätzung fällt dann etwas zu kurz aus.
    /// shortcut: Dateien und Assets gleich gezählt; genauer wäre die Dateizahl je Asset, sobald die Schätzung stört.
    func restSekunden(offen: Int, jetzt: Date) -> Double? {
        let t = jetzt.timeIntervalSince(start)
        guard dateien >= 3, t >= 5, offen > 0 else { return nil }
        return Double(offen) * t / Double(dateien)
    }

    /// "ca. 12 Min.", "ca. 2 Std. 5 Min.", "mehr als 1 Tag".
    static func restText(_ sekunden: Double) -> String {
        let minuten = Int((sekunden / 60).rounded(.up))
        if minuten <= 1 { return "weniger als 1 Min." }
        if minuten < 60 { return "ca. \(minuten) Min." }
        if minuten >= 24 * 60 { return "mehr als 1 Tag" }
        let rest = minuten % 60
        return rest == 0 ? "ca. \(minuten / 60) Std." : "ca. \(minuten / 60) Std. \(rest) Min."
    }
}
