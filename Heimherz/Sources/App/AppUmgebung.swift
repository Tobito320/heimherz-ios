import CryptoKit
import Foundation
import Observation
import Photos
import Synchronization

/// Schlüsselbund im Speicher für Demo (Screenshots), Vorschau und Test-Host; es gibt dort keinen echten Schlüsselbund.
final class SpeicherImRAM: KeychainSpeicher {
    private let werte = Mutex<[String: Data]>([:])
    private let schuetze = Mutex<[String: KeychainSchutz]>([:])

    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? { werte.withLock { $0[konto] } }

    func schreiben(_ konto: String, daten: Data, schutz: KeychainSchutz) throws {
        werte.withLock { $0[konto] = daten }
        schuetze.withLock { $0[konto] = schutz }
    }

    func loeschen(_ konto: String) throws {
        werte.withLock { $0[konto] = nil }
        schuetze.withLock { $0[konto] = nil }
    }

    /// Ob der Eintrag mit Face-ID-Abfrage gespeichert wurde (für Tests).
    func mitAbfrage(_ konto: String) -> Bool? { schuetze.withLock { $0[konto] }.map { $0 == .abfrage } }

    /// Wie der Eintrag geschützt gespeichert wurde (für Tests).
    func schutz(_ konto: String) -> KeychainSchutz? { schuetze.withLock { $0[konto] } }
}

/// Was vor dem Entkoppeln über den Stand dieses Handys bekannt ist (nach einem letzten Abgleichversuch).
enum EntkoppelPruefung: Equatable, Sendable {
    /// Alles liegt am PC.
    case alleAmPC
    /// So viele Einträge (auch gelöschte) sind vielleicht noch nicht am PC.
    case offen(Int)
    /// Der Stand ließ sich nicht prüfen (Schlüssel nicht lesbar, Zeit um).
    case unbekannt

    /// Der Text im Dialog; "Am PC bleibt alles" steht nur da, wenn es stimmt.
    var nachricht: String {
        let weg = "Schlüssel, Zugang und der Tresor auf diesem Handy werden gelöscht."
        let token = "Das Token am PC widerrufst du mit `heimherz geraet weg`."
        switch self {
        case .alleAmPC: return "\(weg) Am PC bleibt alles; \(token)"
        case .offen(let n): return "\(n == 1 ? "1 Änderung noch nicht am PC" : "\(n) Änderungen noch nicht am PC"). Sie gehen verloren. \(weg) \(token)"
        case .unbekannt: return "Ob alle Änderungen am PC sind, ließ sich nicht prüfen. Was dort fehlt, geht verloren. \(weg) \(token)"
        }
    }
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
    /// Zählt Koppeln und Entkoppeln hoch; Ansichten mit Klartext (Passwörter) lassen sich dadurch auch bei einem Wechsel des Zugangs zurücksetzen.
    private(set) var kopplung = 0

    var istGekoppelt: Bool { geraet != nil }

    init(bund: Schluesselbund, ablage: TresorAblage, sitzung: URLSession = .shared, sperreAktiv: Bool, istDemo: Bool = false) {
        self.bund = bund
        self.ablage = ablage
        self.sitzung = sitzung
        self.istDemo = istDemo
        let geraet = try? bund.ladeGeraet()
        self.geraet = geraet
        self.sperre = AppSperre(gesperrt: geraet != nil, aktiv: sperreAktiv, bund: bund)
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
    /// Ist das Handy schon gekoppelt, ersetzt der neue Zugang den alten samt lokalem Tresor: davor ein letzter Abgleich mit dem alten PC (der Dialog hat gewarnt).
    func koppeln(link: String) async throws {
        _ = try KoppelLink.lese(link)
        let warGekoppelt = geraet != nil
        if warGekoppelt { _ = await pruefeVorEntkoppeln() }
        status = try await Koppeln.koppeln(link: link, bund: bund, sitzung: sitzung)
        if warGekoppelt { try? ablage.loesche() }   // gehört zum alten Schlüssel
        statusFehler = nil
        geraet = try bund.ladeGeraet()
        kopplung += 1
    }

    /// Letzter Abgleichversuch mit dem PC und danach die Zahl der Einträge, die dort noch fehlen. Höchstens `sekunden` lang.
    /// Fragt kein zweites Mal nach Face ID: K wird mit dem Kontext der Sperre geladen.
    func pruefeVorEntkoppeln(sekunden: Double = 10) async -> EntkoppelPruefung {
        guard geraet != nil, !istDemo else { return .alleAmPC }
        let bund = bund, kontext = sperre.kontext, dienst = tresorDienst(), ablage = ablage
        return await withTaskGroup(of: EntkoppelPruefung?.self) { gruppe in
            gruppe.addTask { await Self.pruefe(bund: bund, kontext: kontext, dienst: dienst, ablage: ablage) }
            gruppe.addTask {
                try? await Task.sleep(for: .seconds(sekunden))
                return nil
            }
            let erstes = await gruppe.next()
            gruppe.cancelAll()
            return (erstes ?? nil) ?? .unbekannt
        }
    }

    @concurrent
    private static func pruefe(bund: Schluesselbund, kontext: EntsperrKontext, dienst: TresorDienst, ablage: TresorAblage) async -> EntkoppelPruefung {
        let lokal: Tresor
        let k: SymmetricKey
        do {
            guard let schluessel = try await bund.ladeSchluessel(kontext: kontext), let t = try await dienst.lokal(schluessel: schluessel) else { return .alleAmPC }
            k = schluessel
            lokal = t
        } catch {
            return .unbekannt
        }
        let ergebnis = try? await dienst.abgleichen(lokal: lokal, schluessel: k)
        if case .abgeglichen? = ergebnis { return .alleAmPC }
        let n = ablage.ungesendet(in: lokal)
        return n == 0 ? .alleAmPC : .offen(n)
    }

    /// Entkoppeln: Schlüssel, Token und URL aus dem Schlüsselbund, lokaler Tresor-Cache weg, Foto-Erweiterung aus (angelegte Upload-Jobs tragen das alte Token).
    /// Wirft, wenn etwas klemmt (der Aufrufer zeigt es); der Zustand folgt dann dem, was der Schlüsselbund noch hält.
    func entkoppeln() throws {
        defer {
            geraet = try? bund.ladeGeraet()
            if geraet == nil {
                status = nil
                statusFehler = nil
            }
            kopplung += 1
        }
        try bund.vergiss()
        if !istDemo, !Self.istTestHost { try? PHPhotoLibrary.shared().setUploadJobExtensionEnabled(false) }
        try ablage.loesche()
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
