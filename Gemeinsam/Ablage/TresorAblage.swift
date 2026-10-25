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
        if FileManager.default.fileExists(atPath: abgeglichenDatei.path) { try FileManager.default.removeItem(at: abgeglichenDatei) }
    }

    // MARK: Was ist schon am PC?

    private var abgeglichenDatei: URL { datei.deletingLastPathComponent().appendingPathComponent("tresor.abgeglichen") }

    /// Merkt, wann ein Abgleich den Stand am PC bestätigt hat (App und Erweiterung teilen den Ordner). Ein Fehler hier heißt nur: später mehr Warnungen, nie weniger.
    func markiereAbgeglichen(_ zeit: Date) {
        try? Data(Zeit.iso(zeit).utf8).write(to: abgeglichenDatei, options: [.atomic])
    }

    /// Einträge (auch Grabsteine), die nach dem letzten bestätigten Abgleich geändert wurden und darum vielleicht noch nicht am PC liegen.
    /// Ohne Merker gelten alle als ungesendet. Zählt eher zu viel als zu wenig (Uhr des Handys gegen Uhr des Handys).
    func ungesendet(in tresor: Tresor) -> Int {
        let grenze = (try? Data(contentsOf: abgeglichenDatei)).flatMap { Zeit.millis(iso: String(decoding: $0, as: UTF8.self)) }
        guard let grenze else { return tresor.eintraege.count }
        return tresor.eintraege.filter { e in (Zeit.millis(iso: e.geaendert) ?? Int64.max) >= grenze }.count
    }
}
