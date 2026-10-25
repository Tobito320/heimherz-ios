import Foundation
import Observation

/// Zustand des Dateien-Tabs: Ordnerliste mit Navigation, Laden, Hochladen, Papierkorb. Alles geht über `HeimClient`; in Demo und Test-Host nie ins Netz.
@MainActor @Observable
final class DateienModell {
    enum Zustand: Equatable {
        case laedt, bereit
        /// `offline`: der PC antwortet nicht (aus, kein Tailscale); die letzte Liste bleibt sichtbar.
        case fehler(String, offline: Bool)
    }

    private(set) var ordner: [String] = []
    private(set) var eintraege: [DateiInfo] = []
    private(set) var zustand = Zustand.laedt
    /// Ergebnis des letzten Hochladens oder Papierkorbs, einmal anzeigen.
    private(set) var meldung: String?
    private(set) var meldungIstFehler = false
    private(set) var uebertragungen = 0

    let istDemo: Bool
    private let holeClient: @MainActor () throws -> HeimClient
    private var ladeNummer = 0

    init(istDemo: Bool, holeClient: @escaping @MainActor () throws -> HeimClient) {
        self.istDemo = istDemo
        self.holeClient = holeClient
        if istDemo {
            eintraege = Self.demoEintraege
            zustand = .bereit
        }
    }

    var pfad: String { ordner.joined(separator: "/") }

    // MARK: Liste

    func lade() async {
        guard !istDemo else { return }
        ladeNummer += 1
        let nr = ladeNummer
        if eintraege.isEmpty { zustand = .laedt }
        do {
            let liste = try await holeClient().dateienListe(pfad: pfad)
            guard nr == ladeNummer else { return }
            eintraege = liste
            zustand = .bereit
        } catch {
            guard nr == ladeNummer else { return }
            zustand = Self.fehlerZustand(error)
        }
    }

    func oeffne(_ ordnerName: String) async {
        guard !istDemo else { return }
        ordner.append(ordnerName)
        eintraege = []
        await lade()
    }

    /// Zurück auf eine Stufe der Brotkrumen (0 = Wurzel).
    func geheZu(tiefe: Int) async {
        guard !istDemo, tiefe >= 0, tiefe < ordner.count else { return }
        ordner = Array(ordner.prefix(tiefe))
        eintraege = []
        await lade()
    }

    func quittiereMeldung() { meldung = nil }

    // MARK: Laden zur Vorschau

    /// Lädt die Datei in den Cache und gibt ihre Adresse zurück (Vorschau, Teilen). Wirft `HeimFehler`.
    func laden(_ e: DateiInfo) async throws -> URL {
        let client = try holeClient()
        let pfad = DateiPfad.zusammen(ordner, e.name)
        let ziel = VorschauCache.ziel(wurzel: VorschauCache.wurzel, pfad: pfad, name: e.name)
        try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await client.dateiLaden(pfad: pfad, nach: ziel)
        return ziel
    }

    // MARK: Hochladen

    /// Lädt lokale Dateien in den aktuellen Ordner. Die Dateien werden danach nicht angefasst (Aufrufer räumt Temp-Dateien auf).
    func hochladen(_ dateien: [(url: URL, name: String)]) async {
        guard !istDemo, !dateien.isEmpty else { return }
        uebertragungen += dateien.count
        defer { uebertragungen -= dateien.count }
        var ok = 0
        var letzterFehler: String?
        do {
            let client = try holeClient()
            for d in dateien {
                do {
                    try await client.dateiHochladen(pfad: DateiPfad.zusammen(ordner, d.name), von: d.url)
                    ok += 1
                } catch let f as HeimFehler where f.istNetzproblem || f == .nichtBerechtigt {
                    letzterFehler = f.nutzerText
                    break
                } catch {
                    letzterFehler = (error as? HeimFehler)?.nutzerText ?? "„\(d.name)“ konnte nicht hochgeladen werden."
                }
            }
        } catch {
            letzterFehler = (error as? HeimFehler)?.nutzerText ?? HeimFehler.nichtErreichbar.nutzerText
        }
        melde(ok: ok, von: dateien.count, fehler: letzterFehler)
        if ok > 0 { await lade() }
    }

    static func ergebnisText(ok: Int, von: Int, fehler: String?) -> (text: String, istFehler: Bool) {
        if let fehler { return (ok > 0 ? "\(ok) von \(von) hochgeladen. \(fehler)" : fehler, true) }
        return (ok == 1 ? "1 Datei hochgeladen." : "\(ok) Dateien hochgeladen.", false)
    }

    private func melde(ok: Int, von: Int, fehler: String?) {
        let e = Self.ergebnisText(ok: ok, von: von, fehler: fehler)
        meldung = e.text
        meldungIstFehler = e.istFehler
    }

    // MARK: Papierkorb

    /// Legt am PC eine Datei oder einen Ordner in den Papierkorb (nie endgültig löschen). true bei Erfolg.
    @discardableResult
    func inPapierkorb(_ e: DateiInfo) async -> Bool {
        guard !istDemo else { return false }
        do {
            try await holeClient().inPapierkorb(pfad: DateiPfad.zusammen(ordner, e.name))
            meldung = "„\(e.name)“ liegt jetzt im Papierkorb am PC."
            meldungIstFehler = false
            await lade()
            return true
        } catch {
            meldung = (error as? HeimFehler)?.nutzerText ?? "Das hat nicht geklappt."
            meldungIstFehler = true
            return false
        }
    }

    // MARK: Hilfen

    static func fehlerZustand(_ error: Error) -> Zustand {
        guard let f = error as? HeimFehler else { return .fehler(HeimFehler.nichtErreichbar.nutzerText, offline: true) }
        return .fehler(f.nutzerText, offline: f.istNetzproblem)
    }

    private static var demoEintraege: [DateiInfo] {
        let jetzt = Zeit.iso(Date())
        return [
            DateiInfo(name: "Dokumente", ordner: true, groesse: 0, geaendert: jetzt),
            DateiInfo(name: "Scans", ordner: true, groesse: 0, geaendert: jetzt),
            DateiInfo(name: "Mietvertrag.pdf", ordner: false, groesse: 482_000, geaendert: jetzt),
            DateiInfo(name: "Urlaub Foto.jpg", ordner: false, groesse: 3_400_000, geaendert: jetzt),
        ]
    }
}
