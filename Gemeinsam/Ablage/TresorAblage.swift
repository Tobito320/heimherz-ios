import Foundation

/// Der lokale Tresor-Cache: nur der verschlüsselte `Umschlag` als eine Datei im App-Group-Ordner (atomar geschrieben), nie Klartext auf Platte.
/// Die AutoFill-Erweiterung liest dieselbe Datei und kann so auch ohne PC und ohne Netz füllen.
struct TresorAblage: Sendable {
    let datei: URL

    init(ordner: URL) {
        datei = ordner.appendingPathComponent("tresor.umschlag.json")
    }

    /// Die Ablage im App-Group-Ordner; nil, wenn es ihn nicht gibt (Tests ohne Signierung: dort `init(ordner:)` mit Temp-Ordner nehmen).
    static func appGruppe() -> TresorAblage? {
        Kennungen.gruppenOrdner().map { TresorAblage(ordner: $0) }
    }

    /// nil, wenn noch nichts liegt.
    func lade() throws -> Umschlag? {
        guard FileManager.default.fileExists(atPath: datei.path) else { return nil }
        return try JSONDecoder().decode(Umschlag.self, from: Data(contentsOf: datei))
    }

    func speichere(_ umschlag: Umschlag) throws {
        try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Lesbar nach dem ersten Entsperren: die Erweiterung läuft auch bei gesperrtem Bildschirm im Hintergrund an.
        try encoder.encode(umschlag).write(to: datei, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func loesche() throws {
        if FileManager.default.fileExists(atPath: datei.path) { try FileManager.default.removeItem(at: datei) }
    }
}
