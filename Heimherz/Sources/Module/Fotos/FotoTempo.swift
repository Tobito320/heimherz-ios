import Foundation

/// Messung eines Laufs. Zählt nur Dateien, die der PC mit 2xx bestätigt hat (`FotoAbgleich.verbuche`). Die Geschwindigkeit ist gleitend über die
/// letzten `fenster` Sekunden, nicht der Schnitt seit dem Start: sie zeigt, was jetzt ankommt. Die Uhr kommt von außen (Test).
struct FotoTempo: Sendable, Equatable {
    /// Gleitendes Fenster; kurz genug für "jetzt", lang genug, damit einzelne große Dateien die Zahl nicht springen lassen.
    static let fenster: TimeInterval = 15

    struct Probe: Sendable, Equatable {
        let zeit: Date
        let bytes: Int64
    }

    let start: Date
    private(set) var dateien = 0
    private(set) var bytes: Int64 = 0
    private var proben: [Probe] = []

    init(start: Date) { self.start = start }

    mutating func buche(bytes neu: Int64, jetzt: Date) {
        dateien += 1
        bytes += neu
        proben.append(Probe(zeit: jetzt, bytes: neu))
        proben.removeAll { jetzt.timeIntervalSince($0.zeit) > Self.fenster }
    }

    /// Bytes der letzten `fenster` Sekunden geteilt durch die Fensterbreite (in den ersten Sekunden durch die bisherige Laufzeit).
    /// Erst nach zwei Sekunden; nil, solange noch nichts bestätigt wurde oder im Fenster nichts ankam (dann zeigt die Oberfläche keine Zahl statt "0").
    /// shortcut: Dateien zählen erst beim Abschluss, bei einer sehr großen Datei springt die Zahl; genauer wäre der Fortschritt von `URLSession`, wenn das stört.
    func bytesProSekunde(jetzt: Date) -> Double? {
        let t = jetzt.timeIntervalSince(start)
        guard t >= 2, dateien > 0 else { return nil }
        let summe = proben.filter { jetzt.timeIntervalSince($0.zeit) <= Self.fenster }.reduce(Int64(0)) { $0 + $1.bytes }
        guard summe > 0 else { return nil }
        return Double(summe) / min(Self.fenster, t)
    }

    /// Restzeit aus der gleitenden Geschwindigkeit und der mittleren Größe je bestätigter Datei. `offen` sind Assets, Live Photos haben zwei Dateien,
    /// die Schätzung fällt dann etwas zu kurz aus.
    /// shortcut: Dateien und Assets gleich gezählt; genauer wäre die Dateizahl je Asset, sobald die Schätzung stört.
    func restSekunden(offen: Int, jetzt: Date) -> Double? {
        guard dateien >= 3, jetzt.timeIntervalSince(start) >= 5, offen > 0, let rate = bytesProSekunde(jetzt: jetzt), bytes > 0 else { return nil }
        return Double(offen) * (Double(bytes) / Double(dateien)) / rate
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

/// Die Zahlen, die jeder Foto-Upload dem PC als Kopfzeilen `X-Heim-*` mitgibt (`heimherz tempo` fasst sie zusammen, SPEC 6/7).
/// Nur Zeiten, Zähler und feste Stichwörter, nie Inhalte, Namen oder Kennungen.
struct FotoMessung: Sendable, Equatable {
    /// Dauer des PhotoKit-Exports dieser Datei.
    var exportMs: Int
    /// Vom fertigen Export bis zum Start des Uploads (Platz-Warten und Sprung auf den Hauptthread eingerechnet).
    var warteMs: Int
    /// Laufende Uploads (diesen mitgezählt) und laufende Exporte in diesem Moment.
    var aktiv: Int
    var exporte: Int
    var iCloud: Bool
    /// Bis hierher in diesem Lauf: nach iCloud zurückgestellt, wegen Stillstand abgebrochen.
    var aufgeschoben = 0
    var haenger = 0

    func setze(in anfrage: inout URLRequest) {
        anfrage.setValue(String(max(0, exportMs)), forHTTPHeaderField: "X-Heim-Export-Ms")
        anfrage.setValue(String(max(0, warteMs)), forHTTPHeaderField: "X-Heim-Warte-Ms")
        anfrage.setValue(String(max(0, aktiv)), forHTTPHeaderField: "X-Heim-Aktiv")
        anfrage.setValue(String(max(0, exporte)), forHTTPHeaderField: "X-Heim-Exporte")
        anfrage.setValue(iCloud ? "icloud" : "lokal", forHTTPHeaderField: "X-Heim-Durchgang")
        anfrage.setValue(String(max(0, aufgeschoben)), forHTTPHeaderField: "X-Heim-Aufgeschoben")
        anfrage.setValue(String(max(0, haenger)), forHTTPHeaderField: "X-Heim-Haenger")
    }

    /// Was erst der Sender weiß: ob die App vorn war und über welche Sitzung es ging. `zusatzWarteMs`: Zeit, die der Sender selbst noch verbraucht hat.
    static func markiere(_ anfrage: URLRequest, vordergrund: Bool, zusatzWarteMs: Int = 0) -> URLRequest {
        var r = anfrage
        r.setValue(vordergrund ? "1" : "0", forHTTPHeaderField: "X-Heim-Vordergrund")
        r.setValue(vordergrund ? "vorder" : "hinter", forHTTPHeaderField: "X-Heim-Session")
        if zusatzWarteMs > 0, let alt = r.value(forHTTPHeaderField: "X-Heim-Warte-Ms").flatMap({ Int($0) }) {
            r.setValue(String(alt + zusatzWarteMs), forHTTPHeaderField: "X-Heim-Warte-Ms")
        }
        return r
    }

    static func ms(seit start: ContinuousClock.Instant) -> Int {
        let d = start.duration(to: .now).components
        return Int(d.seconds * 1_000 + d.attoseconds / 1_000_000_000_000_000)
    }
}
