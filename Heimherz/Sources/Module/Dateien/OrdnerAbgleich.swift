import Foundation
import Observation

/// Größe und Änderungszeit (ganze Sekunden) einer Datei auf dem Handy; ändert sich eins davon, gilt die Datei als neu.
struct OrdnerDateiStand: Codable, Equatable, Sendable {
    var groesse: Int64
    var geaendert: Int64
}

/// Ein Ordner aus der Dateien-App, den der Nutzer verbunden hat (W-045, SPEC 12). `gesendet` = was schon am PC liegt, nach relativem Pfad.
struct VerbundenerOrdner: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var lesezeichen: Data
    var gesendet: [String: OrdnerDateiStand] = [:]
    /// Dateien, die beim letzten Abgleich nicht hochgeladen werden konnten.
    var offen: Int?
}

struct GefundeneDatei: Sendable {
    let url: URL
    let stand: OrdnerDateiStand
}

enum OrdnerRegeln {
    /// Relative Pfade, die neu oder geändert sind (Größe oder Zeit weicht vom Gemerkten ab), sortiert.
    /// shortcut: eine geänderte Datei kommt als Kopie "name (2).ext" an, der Dienst überschreibt nie; bei Bedarf später ersetzen.
    static func zuSenden(gefunden: [String: OrdnerDateiStand], gemerkt: [String: OrdnerDateiStand]) -> [String] {
        gefunden.filter { gemerkt[$0.key] != $0.value }.keys.sorted()
    }

    /// Zielpfad am PC (relativ zu `~/Heimherz/Dateien`); der Dienst legt `Eingang/…` bei Bedarf an.
    static func zielPfad(ordnerName: String, relativ: String) -> String { "Eingang/\(ordnerName)/\(relativ)" }

    /// Alle regulären Dateien unterhalb von `wurzel`, rekursiv, ohne versteckte Dateien und ohne Symlinks.
    static func lies(_ wurzel: URL) -> [String: GefundeneDatei] {
        var aus: [String: GefundeneDatei] = [:]
        sammle(wurzel, vorsatz: "", &aus)
        return aus
    }

    private static func sammle(_ ordner: URL, vorsatz: String, _ aus: inout [String: GefundeneDatei]) {
        let schluessel: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let inhalt = try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: schluessel, options: [.skipsHiddenFiles]) else { return }
        for u in inhalt {
            guard let w = try? u.resourceValues(forKeys: Set(schluessel)), w.isSymbolicLink != true else { continue }
            let name = vorsatz + u.lastPathComponent
            if w.isDirectory == true {
                sammle(u, vorsatz: name + "/", &aus)
            } else if let groesse = w.fileSize, let datum = w.contentModificationDate {
                aus[name] = GefundeneDatei(url: u, stand: OrdnerDateiStand(groesse: Int64(groesse), geaendert: Int64(datum.timeIntervalSince1970)))
            }
        }
    }
}

/// Verbundene Handy-Ordner: Liste (JSON im App-Support-Ordner) und Abgleich zum PC. Löscht oder ändert am Handy nie etwas.
@MainActor @Observable
final class OrdnerAbgleich {
    static let geteilt = OrdnerAbgleich()

    private(set) var ordner: [VerbundenerOrdner]
    private(set) var laeuft = false
    private let datei: URL
    private var seitSpeichern = 0

    init(datei: URL = URL.applicationSupportDirectory.appending(path: "Heimherz/ordner-abgleich.json")) {
        self.datei = datei
        ordner = (try? JSONDecoder().decode([VerbundenerOrdner].self, from: Data(contentsOf: datei))) ?? []
    }

    /// Merkt einen Ordner aus dem Auswahldialog. false, wenn der Zugriff oder das Lesezeichen scheitert.
    @discardableResult
    func verbinde(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let daten = try? url.bookmarkData() else { return false }   // iOS: ohne .withSecurityScope (nur macOS)
        ordner.append(VerbundenerOrdner(name: url.lastPathComponent, lesezeichen: daten))
        speichere()
        return true
    }

    func trenne(_ id: UUID) {
        ordner.removeAll { $0.id == id }
        speichere()
    }

    /// Lädt neue und geänderte Dateien aller Ordner zum PC. Ein Lauf zur Zeit; Fehler einzelner Dateien bleiben still (nächstes Mal wieder).
    func abgleichen(client: HeimClient) async {
        guard !laeuft, !ordner.isEmpty else { return }
        laeuft = true
        defer { laeuft = false }
        for id in ordner.map(\.id) {
            guard let e = ordner.first(where: { $0.id == id }) else { continue }
            // Jede bestätigte Datei sofort merken (gespeichert alle 10): wird die App mitten im Lauf beendet, kommt nichts doppelt als "(2)" an den PC.
            seitSpeichern = 0
            let r = await Self.gleiche(e, client: client) { [weak self] rel, stand in
                guard let self, let i = self.ordner.firstIndex(where: { $0.id == id }) else { return }
                self.ordner[i].gesendet[rel] = stand
                self.seitSpeichern += 1
                if self.seitSpeichern % 10 == 0 { self.speichere() }
            }
            guard let i = ordner.firstIndex(where: { $0.id == id }) else { continue }
            ordner[i].gesendet = r.gesendet
            ordner[i].offen = r.offen
            if let neu = r.lesezeichen { ordner[i].lesezeichen = neu }
            speichere()
        }
    }

    private func speichere() {
        try? FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let daten = try? JSONEncoder().encode(ordner) { try? daten.write(to: datei, options: .atomic) }
    }

    struct Ergebnis: Sendable {
        var gesendet: [String: OrdnerDateiStand]
        var offen: Int
        var lesezeichen: Data?
    }

    @concurrent
    private static func gleiche(_ e: VerbundenerOrdner, client: HeimClient, merke: @MainActor @Sendable (String, OrdnerDateiStand) -> Void) async -> Ergebnis {
        var veraltet = false
        guard let wurzel = try? URL(resolvingBookmarkData: e.lesezeichen, options: [], relativeTo: nil, bookmarkDataIsStale: &veraltet) else {
            return Ergebnis(gesendet: e.gesendet, offen: e.offen ?? 0)   // Ordner nicht mehr auflösbar: Eintrag bleibt, Nutzer trennt ihn
        }
        let zugriff = wurzel.startAccessingSecurityScopedResource()
        defer { if zugriff { wurzel.stopAccessingSecurityScopedResource() } }
        var r = Ergebnis(gesendet: e.gesendet, offen: 0, lesezeichen: veraltet ? (try? wurzel.bookmarkData()) : nil)
        let gefunden = OrdnerRegeln.lies(wurzel)
        let neu = OrdnerRegeln.zuSenden(gefunden: gefunden.mapValues(\.stand), gemerkt: e.gesendet)
        for (n, rel) in neu.enumerated() {
            guard let g = gefunden[rel], let kopie = await kopiere(g.url) else { r.offen += 1; continue }
            defer { try? FileManager.default.removeItem(at: kopie) }
            do {
                try await client.dateiHochladen(pfad: OrdnerRegeln.zielPfad(ordnerName: e.name, relativ: rel), von: kopie)
                r.gesendet[rel] = g.stand
                await merke(rel, g.stand)
            } catch let f as HeimFehler where f.istNetzproblem || f == .nichtBerechtigt || f == .speicherVoll {
                r.offen += neu.count - n   // PC nicht erreichbar oder voll: der Rest wartet auf das nächste Mal
                break
            } catch {
                r.offen += 1
            }
            if Task.isCancelled { r.offen += neu.count - n - 1; break }
        }
        return r
    }

    /// Kopie in den Temp-Ordner. Der Zugriff über `NSFileCoordinator` lädt Dateien, die ein Datei-Anbieter (Adobe Scan, iCloud) nur in seiner Lumen Cloud hält, erst herunter.
    nonisolated private static func kopiere(_ quelle: URL) async -> URL? {
        await withCheckedContinuation { weiter in
            DispatchQueue.global().async {
                var fehler: NSError?
                var ziel: URL?
                NSFileCoordinator().coordinate(readingItemAt: quelle, options: [], error: &fehler) { gelesen in
                    let kopie = FileManager.default.temporaryDirectory.appending(path: "ordner-\(UUID().uuidString)")
                    if (try? FileManager.default.copyItem(at: gelesen, to: kopie)) != nil { ziel = kopie }
                }
                weiter.resume(returning: ziel)
            }
        }
    }
}
