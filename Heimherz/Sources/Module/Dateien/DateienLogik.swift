import CryptoKit
import Foundation

/// Pfade am PC, relativ zu `~/Heimherz/Dateien` (SPEC 6), mit `/` getrennt.
enum DateiPfad {
    static func zusammen(_ ordner: [String], _ name: String) -> String {
        (ordner + [name]).joined(separator: "/")
    }

    /// Brotkrumen: "Dateien" (Tiefe 0) und je Ordner eine Stufe. `tiefe` ist die Zahl der Ordner, die geöffnet bleiben.
    static func krumen(ordner: [String]) -> [(titel: String, tiefe: Int)] {
        [("Dateien", 0)] + ordner.enumerated().map { ($0.element, $0.offset + 1) }
    }
}

/// Anzeige-Regeln für Zeilen.
enum DateiAnzeige {
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

    static func groesse(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// "12 KB, 25. Okt. 2026" bzw. "Ordner, ..." für die zweite Zeile.
    static func untertitel(_ e: DateiInfo) -> String {
        let datum = e.datum?.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE")))
        return [e.ordner ? "Ordner" : groesse(e.groesse), datum].compactMap { $0 }.joined(separator: ", ")
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
