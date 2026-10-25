import Foundation
import Observation
import Synchronization

/// Schlüsselbund im Speicher für Demo (Screenshots), Vorschau und Test-Host; es gibt dort keinen echten Schlüsselbund.
final class SpeicherImRAM: KeychainSpeicher {
    private let werte = Mutex<[String: Data]>([:])
    private let abfragen = Mutex<[String: Bool]>([:])

    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? { werte.withLock { $0[konto] } }

    func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws {
        werte.withLock { $0[konto] = daten }
        abfragen.withLock { $0[konto] = mitAbfrage }
    }

    func loeschen(_ konto: String) throws {
        werte.withLock { $0[konto] = nil }
        abfragen.withLock { $0[konto] = nil }
    }

    /// Ob der Eintrag mit Face-ID-Abfrage gespeichert wurde (für Tests).
    func mitAbfrage(_ konto: String) -> Bool? { abfragen.withLock { $0[konto] } }
}

/// Alles, was die Module gemeinsam brauchen: Schlüsselbund, Ablage, Verbindung zum PC, App-Sperre.
/// Andockpunkte für die späteren Module: `client()` (Passwörter, Fotos, Dateien), `tresorDienst()` (Passwörter), `bund` (Schlüssel K).
@MainActor @Observable
final class AppUmgebung {
    let bund: Schluesselbund
    let ablage: TresorAblage
    let sitzung: URLSession
    let sperre: AppSperre
    let istDemo: Bool

    private(set) var geraet: Geraet?
    private(set) var status: ServerStatus?
    private(set) var statusFehler: String?
    private(set) var statusLaedt = false

    var istGekoppelt: Bool { geraet != nil }

    init(bund: Schluesselbund, ablage: TresorAblage, sitzung: URLSession = .shared, sperreAktiv: Bool, istDemo: Bool = false) {
        self.bund = bund
        self.ablage = ablage
        self.sitzung = sitzung
        self.istDemo = istDemo
        let geraet = try? bund.ladeGeraet()
        self.geraet = geraet
        self.sperre = AppSperre(gesperrt: geraet != nil, aktiv: sperreAktiv)
    }

    // MARK: Andockpunkte

    /// Der Client zum PC; wirft `nichtGekoppelt`.
    func client() throws -> HeimClient {
        guard let g = geraet else { throw HeimFehler.nichtGekoppelt }
        return HeimClient(basis: g.url, token: g.token, sitzung: sitzung)
    }

    /// Der Abgleich-Dienst (SPEC 9); ohne Kopplung arbeitet er nur lokal.
    func tresorDienst() -> TresorDienst {
        TresorDienst(ablage: ablage, client: try? client())
    }

    // MARK: Zustand

    func ladeStatus() async {
        guard !istDemo, let c = try? client() else { return }
        statusLaedt = true
        defer { statusLaedt = false }
        do {
            status = try await c.status()
            statusFehler = nil
        } catch let fehler as HeimFehler {
            statusFehler = fehler.nutzerText
        } catch {
            statusFehler = HeimFehler.nichtErreichbar.nutzerText
        }
    }

    /// Koppeln mit dem Text aus QR oder Zwischenablage. Wirft verständliche Fehler (`KoppelFehler`, `HeimFehler`).
    func koppeln(link: String) async throws {
        status = try await Koppeln.koppeln(link: link, bund: bund, sitzung: sitzung)
        statusFehler = nil
        geraet = try bund.ladeGeraet()
    }

    /// Entkoppeln: Schlüssel, Token und URL aus dem Schlüsselbund, lokaler Tresor-Cache weg. Am PC bleibt alles; das Token dort widerruft `heimherz geraet weg`.
    func entkoppeln() {
        try? bund.vergiss()
        try? ablage.loesche()
        geraet = nil
        status = nil
        statusFehler = nil
    }

    // MARK: Aufbau

    nonisolated static var istTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Die eine Instanz der laufenden App. Im Test-Host (gehostete Unit-Tests starten die App) eine Vorschau ohne Sperre und ohne Netz.
    static let geteilt: AppUmgebung = istTestHost ? vorschau() : live()

    static func live() -> AppUmgebung {
        let ordner = URL.applicationSupportDirectory.appending(path: "Heimherz", directoryHint: .isDirectory)
        return AppUmgebung(bund: .live, ablage: TresorAblage.appGruppe() ?? TresorAblage(ordner: ordner), sperreAktiv: true)
    }

    static func vorschau() -> AppUmgebung {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "heimherz-vorschau-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppUmgebung(bund: Schluesselbund(speicher: SpeicherImRAM()), ablage: TresorAblage(ordner: ordner), sperreAktiv: false, istDemo: true)
    }

    #if DEBUG
    /// Nur Debug (`-heimherzDemo YES`, Screenshots in CI): gekoppelt mit erfundenen Zahlen, oder mit `ohnePC` ungekoppelt. Nie Netz, nie Face ID.
    static func demo(ohnePC: Bool) -> AppUmgebung {
        let u = vorschau()
        if !ohnePC {
            try? u.bund.speichereGeraet(Geraet(url: URL(string: "https://pc.example.ts.net") ?? URL(fileURLWithPath: "/"), token: "demo"))
            u.geraet = try? u.bund.ladeGeraet()
            u.status = ServerStatus(version: "0.1.0", rev: 12, fotos: 1342, belegt: 48_000_000_000, frei: 412_000_000_000)
        }
        return u
    }
    #endif
}
