import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Teilen-Erweiterung "Heimcloud" (W-045, SPEC 12): Dateien aus Adobe Scan und anderen Apps gehen nacheinander nach `Eingang/` am PC.
/// Zugang wie die anderen Erweiterungen: Schlüsselbund und Adresse der App (`Schluesselbund.live`). Reine Regeln: `TeilenRegeln`.
@MainActor @Observable
final class TeilenModell {
    enum Stand: Equatable {
        case laeuft
        case fertig
        case fehler(String)
    }

    private(set) var stand = Stand.laeuft
    private(set) var anzahl = 0
    private(set) var gesendet = 0
    /// `true`: fertig, `false`: abgebrochen oder Fehler gelesen.
    var schliessen: (@MainActor (Bool) -> Void)?
    private var anbieter: [NSItemProvider] = []
    private var lauf: Task<Void, Never>?

    func starte(_ anbieter: [NSItemProvider]) {
        guard lauf == nil else { return }
        self.anbieter = anbieter
        anzahl = anbieter.count
        lauf = Task { await self.sende() }
    }

    func beende() {
        lauf?.cancel()
        schliessen?(false)
    }

    private func sende() async {
        guard anzahl > 0 else { return stand = .fehler("Es wurde keine Datei übergeben") }
        let client: HeimClient
        do { client = try HeimClient.aus(Schluesselbund.live) } catch { return stand = .fehler(TeilenRegeln.fehlerText(error)) }
        var letzterFehler: Error?
        for p in anbieter {
            do {
                let kopie = try await Self.kopiere(p)
                defer { try? FileManager.default.removeItem(at: kopie.deletingLastPathComponent()) }
                try await client.dateiHochladen(pfad: TeilenRegeln.zielPfad(name: kopie.lastPathComponent), von: kopie)
                gesendet += 1
            } catch {
                if Task.isCancelled { return }
                letzterFehler = error
                if TeilenRegeln.haeltAn(error) { break }
            }
        }
        if let letzterFehler { return stand = .fehler(TeilenRegeln.fehlerZeile(letzterFehler, gesendet: gesendet, von: anzahl)) }
        stand = .fertig
        try? await Task.sleep(for: .seconds(1))
        schliessen?(true)
    }

    /// Temp-Kopie unter ihrem Namen in einem eigenen Ordner. Die URL des Systems gilt nur im Handler, darum wird dort kopiert.
    /// Der Handler ist ausdrücklich `@Sendable` (nicht an den Hauptakteur gebunden): iOS ruft ihn auf einer eigenen Warteschlange.
    private static func kopiere(_ p: NSItemProvider) async throws -> URL {
        let typ = p.registeredContentTypes.first { $0.conforms(to: .data) } ?? .data
        return try await withCheckedThrowingContinuation { weiter in
            _ = p.loadFileRepresentation(forTypeIdentifier: typ.identifier) { @Sendable url, _ in
                guard let url else { return weiter.resume(throwing: TeilenFehler.nichtLesbar) }
                do {
                    let ordner = FileManager.default.temporaryDirectory.appending(path: "teilen-\(UUID().uuidString)", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
                    let ziel = ordner.appending(path: url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: ziel)
                    weiter.resume(returning: ziel)
                } catch {
                    weiter.resume(throwing: TeilenFehler.nichtLesbar)
                }
            }
        }
    }
}

struct TeilenAnsicht: View {
    let modell: TeilenModell

    var body: some View {
        VStack(spacing: Abstand.l) {
            switch modell.stand {
            case .laeuft:
                ProgressView(value: Double(modell.gesendet), total: Double(max(modell.anzahl, 1)))
                Text(TeilenRegeln.kopfzeile(anzahl: modell.anzahl)).font(.headline)
                Text(TeilenRegeln.fortschritt(gesendet: modell.gesendet, von: modell.anzahl)).font(.subheadline).foregroundStyle(.secondary)
                Button("Abbrechen") { modell.beende() }
            case .fertig:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green).accessibilityHidden(true)
                Text("Am PC").font(.headline)
            case .fehler(let text):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange).accessibilityHidden(true)
                Text(text).font(.body).multilineTextAlignment(.center)
                Button("Schließen") { modell.beende() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(Abstand.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// Der Einstieg der Erweiterung (`NSExtensionPrincipalClass`): nimmt die geteilten Anhänge und startet das Hochladen, sobald das Blatt sichtbar ist.
final class TeilenController: UIViewController {
    private let modell = TeilenModell()

    override func viewDidLoad() {
        super.viewDidLoad()
        modell.schliessen = { [weak self] fertig in
            if fertig { self?.extensionContext?.completeRequest(returningItems: nil) } else { self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
        }
        let host = UIHostingController(rootView: TeilenAnsicht(modell: modell))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let objekte = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        modell.starte(objekte.flatMap { $0.attachments ?? [] })
    }
}
