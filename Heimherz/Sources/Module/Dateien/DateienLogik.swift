import CryptoKit
import Foundation

/// Pfade am PC, relativ zu `~/Heimherz/Dateien` (SPEC 6), mit `/` getrennt.
enum DateiPfad {
    static func zusammen(_ ordner: [String], _ name: String) -> String {
        (ordner + [name]).joined(separator: "/")
    }

    static func teile(_ pfad: String) -> [String] {
        pfad.split(separator: "/").map(String.init)
    }

    /// Alle Stufen bis zum Ordner, damit "Zurück" nach einem Sprung aus der Suche Schritt für Schritt hinausführt: ["A", "B"] gibt [["A"], ["A", "B"]].
    static func stufen(_ ordner: [String]) -> [[String]] {
        ordner.indices.map { Array(ordner[...$0]) }
    }
}

/// Womit die Dateien sortiert werden (Menü "Sortieren nach", wie in Apples Dateien).
enum SortierKriterium: String, CaseIterable, Sendable {
    case name, datum, groesse, art

    var titel: String {
        switch self {
        case .name: return "Name"
        case .datum: return "Datum"
        case .groesse: return "Größe"
        case .art: return "Art"
        }
    }

    /// Richtung beim ersten Antippen: Namen und Arten A bis Z, Datum und Größe das Größte oder Neueste zuerst.
    var startAufsteigend: Bool { self == .name || self == .art }
}

struct DateiSortierung: Equatable, Sendable {
    var kriterium: SortierKriterium
    var aufsteigend: Bool

    static let standard = DateiSortierung(kriterium: .name, aufsteigend: true)

    init(kriterium: SortierKriterium, aufsteigend: Bool) {
        self.kriterium = kriterium
        self.aufsteigend = aufsteigend
    }

    /// Aus dem gemerkten Text ("name-auf"); Unbekanntes gibt nil.
    init?(rohwert: String) {
        let teile = rohwert.split(separator: "-").map(String.init)
        guard teile.count == 2, let k = SortierKriterium(rawValue: teile[0]), teile[1] == "auf" || teile[1] == "ab" else { return nil }
        self.init(kriterium: k, aufsteigend: teile[1] == "auf")
    }

    var rohwert: String { "\(kriterium.rawValue)-\(aufsteigend ? "auf" : "ab")" }

    /// Menü: ein neues Kriterium startet in seiner üblichen Richtung, dasselbe noch einmal dreht um.
    func nachTippen(auf k: SortierKriterium) -> DateiSortierung {
        k == kriterium ? DateiSortierung(kriterium: k, aufsteigend: !aufsteigend) : DateiSortierung(kriterium: k, aufsteigend: k.startAufsteigend)
    }

    /// Ordner stehen immer oben (wie der Dienst sie liefert); bei Gleichstand entscheidet der Name von A bis Z.
    func sortiere(_ liste: [DateiInfo]) -> [DateiInfo] {
        liste.sorted { a, b in
            if a.ordner != b.ordner { return a.ordner }
            let c = vergleiche(a, b)
            if c != 0 { return aufsteigend ? c < 0 : c > 0 }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func vergleiche(_ a: DateiInfo, _ b: DateiInfo) -> Int {
        switch kriterium {
        case .name: return a.name.localizedStandardCompare(b.name).rawValue
        case .datum: return Self.zahl(a.datum ?? .distantPast, b.datum ?? .distantPast)
        case .groesse: return Self.zahl(a.groesse, b.groesse)
        case .art:
            return (a.name as NSString).pathExtension.lowercased().localizedStandardCompare((b.name as NSString).pathExtension.lowercased()).rawValue
        }
    }

    private static func zahl<T: Comparable>(_ a: T, _ b: T) -> Int { a < b ? -1 : (a > b ? 1 : 0) }
}

/// Suche im Namen, wie sie der Dienst macht: Groß und klein sowie Umlaute egal (ä = ae, ö = oe, ü = ue, ß = ss), alle Wörter müssen vorkommen.
enum DateiSuche {
    static func normalisiere(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
    }

    static func woerter(_ text: String) -> [String] {
        normalisiere(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func passt(name: String, woerter: [String]) -> Bool {
        let n = normalisiere(name)
        return !woerter.isEmpty && woerter.allSatisfy { n.contains($0) }
    }
}

/// Anzeige-Regeln für Zeilen.
enum DateiAnzeige {
    private static let de = Locale(identifier: "de_DE")

    static func symbol(name: String, ordner: Bool) -> String {
        if ordner { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "bmp": return "photo.fill"
        case "mov", "mp4", "m4v", "mkv", "avi", "webm": return "film.fill"
        case "mp3", "m4a", "wav", "flac", "ogg", "aac": return "waveform"
        case "zip", "7z", "rar", "tar", "gz", "xz": return "doc.zipper"
        case "txt", "md", "rtf", "log": return "doc.text.fill"
        case "xls", "xlsx", "csv", "numbers", "ods": return "tablecells.fill"
        case "doc", "docx", "odt", "pages": return "doc.fill"
        default: return "doc.fill"
        }
    }

    /// Dieselben Endungen wie der Dienst (`server/vorschau.ts`): nur dafür fragt die App ein Vorschaubild an.
    static func hatVorschau(name: String) -> Bool {
        ["pdf", "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "mp4", "mov", "m4v", "mkv", "avi", "webm"]
            .contains((name as NSString).pathExtension.lowercased())
    }

    static func groesse(_ bytes: Int64) -> String {
        bytes.formatted(ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: de))
    }

    static func datum(_ e: DateiInfo) -> String? {
        datum(e.datum)
    }

    static func datum(_ d: Date?) -> String? {
        d?.formatted(.dateTime.day().month(.abbreviated).year().locale(de))
    }

    /// "1 Objekt", "12 Objekte".
    static func objekte(_ n: Int) -> String { n == 1 ? "1 Objekt" : "\(n) Objekte" }

    /// Unter dem Inhalt, fett: "9 Objekte"; darunter steht `synchron` bzw. `getrennt`.
    static let synchron = "Mit PC synchronisiert"
    static let getrennt = "PC nicht erreichbar"

    /// Listenansicht, zweite Zeile: "25. Okt. 2026 – 482 KB"; Ordner: "25. Okt. 2026 – 12 Objekte".
    static func listenUntertitel(_ e: DateiInfo) -> String {
        let rest = e.ordner ? e.anzahl.map(objekte) : groesse(e.groesse)
        return [datum(e), rest].compactMap { $0 }.joined(separator: " – ")
    }

    /// Symbolansicht unter dem Namen: Ordner "12 Objekte" (sonst nichts), Dateien Datum und Größe in zwei Zeilen.
    static func rasterZeilen(_ e: DateiInfo) -> [String] {
        if e.ordner { return [e.anzahl.map(objekte)].compactMap { $0 } }
        return [datum(e), groesse(e.groesse)].compactMap { $0 }
    }

    /// Treffer in der Suche, zweite Zeile: der Ordner, in dem er liegt.
    static func ort(_ ordner: [String]) -> String {
        ordner.isEmpty ? "Dateien" : ordner.joined(separator: " › ")
    }

    /// "12 KB, 25. Okt. 2026" bzw. "Ordner, ..." (Informationen, VoiceOver).
    static func untertitel(_ e: DateiInfo) -> String {
        [e.ordner ? "Ordner" : groesse(e.groesse), datum(e)].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Wo eine geladene Datei zur Vorschau oder zum Teilen liegt: `<wurzel>/<Kurzhash des Pfads>/<Name>`. Der Name bleibt, weil QuickLook und
/// das Teilen-Blatt an der Endung erkennen, was es ist; der Hash trennt gleiche Namen aus verschiedenen Ordnern.
enum VorschauCache {
    static var wurzel: URL {
        URL.cachesDirectory.appending(path: "Heimherz/Dateien", directoryHint: .isDirectory)
    }

    static func ziel(wurzel: URL, pfad: String, name: String) -> URL {
        let hash = SHA256.hash(data: Data(pfad.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return wurzel.appending(path: hash, directoryHint: .isDirectory).appending(path: name)
    }

    static func leere(wurzel: URL = wurzel) {
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Wie viel der Zwischenspeicher am Handy belegt (Summe aller Dateien darunter), für die Einstellungen.
    static func groesse(wurzel: URL = wurzel) -> Int64 {
        guard let liste = FileManager.default.enumerator(at: wurzel, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var summe: Int64 = 0
        for case let url as URL in liste {
            guard let werte = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), werte.isRegularFile == true else { continue }
            summe += Int64(werte.fileSize ?? 0)
        }
        return summe
    }
}

/// Namen für Dateien, die aus Fotos kommen (der Fotoauswahl-Dialog nennt keinen Namen).
enum DateiNamen {
    static func fotoName(datum: Date, endung: String, nummer: Int, zeitzone: TimeZone = .current) -> String {
        var kal = Calendar(identifier: .gregorian)
        kal.timeZone = zeitzone
        let c = kal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: datum)
        let zeit = String(format: "%04d-%02d-%02d %02d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let ext = endung.isEmpty ? "" : ".\(endung.lowercased())"
        return nummer > 1 ? "Foto \(zeit) \(nummer)\(ext)" : "Foto \(zeit)\(ext)"
    }
}
