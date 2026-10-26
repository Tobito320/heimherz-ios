import LocalAuthentication
import Observation
import SwiftUI

/// Wann die App sperrt: nach `entsperrDauer` im Hintergrund (Standard 5 Minuten; "Jedes Mal" = sofort), außer das Entsperr-Fenster ist offen,
/// weil Ahmed gerade in der AutoFill-Erweiterung entsperrt hat (SPEC 2, 8, 10).
enum SperrLogik {
    static func sollSperren(hintergrundSeit: Date?, jetzt: Date, dauer: EntsperrDauer = .fuenfMinuten, fensterOffen: Bool = false) -> Bool {
        guard let seit = hintergrundSeit, !fensterOffen else { return false }
        return jetzt.timeIntervalSince(seit) >= dauer.sekunden
    }
}

/// Die App-Sperre mit Face ID (oder Gerätecode). `aktiv` ist aus im Test-Host und im Demo-Modus, sonst würde dort Face ID gefragt.
/// Gesperrt wird beim Kaltstart (wenn gekoppelt), nach `entsperrDauer` im Hintergrund und bei "Jedes Mal" sofort beim Wechsel in den Hintergrund.
/// Dasselbe Entsperr-Fenster wie AutoFill (`Schluesselbund.fensterOffen`): wer dort entsperrt hat, muss die App nicht noch einmal entsperren, und umgekehrt.
/// Unabhängig davon deckt `verdeckt` den Inhalt sofort ab, sobald die App nicht aktiv ist (App-Umschalter, Kontrollzentrum).
@MainActor @Observable
final class AppSperre {
    private(set) var gesperrt: Bool
    private(set) var verdeckt = false
    private(set) var meldung: String?
    private(set) var pruefungLaeuft = false
    /// Der Kontext der Face-ID-Abfrage dieser Entsperrung. Der Tresor lädt K mit demselben Kontext, so fragt der Start nur einmal.
    /// Bei jedem Sperren (und nach einer Ablehnung) kommt ein neuer, der alte wird ungültig.
    private(set) var kontext = EntsperrKontext()
    private var hintergrundSeit: Date?
    let aktiv: Bool
    /// Für das Entsperr-Fenster; nil in Tests ohne Schlüsselbund (dann gilt die Standarddauer, kein Fenster).
    private let bund: Schluesselbund?

    init(gesperrt: Bool, aktiv: Bool, bund: Schluesselbund? = nil) {
        self.aktiv = aktiv
        self.bund = bund
        self.gesperrt = aktiv && gesperrt && !(bund?.fensterOffen ?? false)
    }

    private var dauer: EntsperrDauer { bund?.dauer() ?? .fuenfMinuten }

    func szene(_ phase: ScenePhase, jetzt: Date = Date()) {
        guard aktiv else { return }
        switch phase {
        case .inactive:
            verdeckt = true
        case .background:
            verdeckt = true
            if hintergrundSeit == nil { hintergrundSeit = jetzt }
            if dauer == .aus { sperren() }   // "Jedes Mal": sofort, nicht erst beim Zurückkommen
        case .active:
            verdeckt = false
            if SperrLogik.sollSperren(hintergrundSeit: hintergrundSeit, jetzt: jetzt, dauer: dauer, fensterOffen: bund?.fensterOffen ?? false) { sperren() }
            hintergrundSeit = nil
        default:
            break
        }
    }

    /// Sperren (auch von Hand): neuer Kontext, und die Kopie von K im Entsperr-Fenster wird gelöscht, damit AutoFill ebenfalls wieder fragt.
    func sperren() {
        guard aktiv else { return }
        gesperrt = true
        neuerKontext()
        bund?.schliesseFenster()
    }

    private func neuerKontext() {
        kontext.kontext.invalidate()
        kontext = EntsperrKontext()
    }

    func entsperren() async {
        guard gesperrt, !pruefungLaeuft else { return }
        pruefungLaeuft = true
        meldung = nil
        switch await Self.pruefeGeraet(kontext) {
        case .ok:
            gesperrt = false
            if let bund { await Self.oeffneFenster(bund, kontext) }
        case .nichtMoeglich: gesperrt = false           // ohne Gerätecode gibt es nichts zu prüfen
        case .abgelehnt:
            meldung = "Entsperren hat nicht geklappt. Bitte noch einmal versuchen."
            neuerKontext()
        }
        pruefungLaeuft = false
    }

    /// Liest K mit dem gerade entsperrten Kontext (keine zweite Abfrage): `ladeSchluessel` öffnet dabei das Fenster für die Erweiterung.
    @concurrent
    private static func oeffneFenster(_ bund: Schluesselbund, _ kontext: EntsperrKontext) async {
        _ = try? await bund.ladeSchluessel(kontext: kontext)
    }

    enum Pruefung: Sendable { case ok, abgelehnt, nichtMoeglich }

    /// Face ID, sonst Gerätecode, im Kontext der Sperre (`EntsperrKontext` ist als Sendable markiert, siehe dort).
    @concurrent
    private static func pruefeGeraet(_ ek: EntsperrKontext) async -> Pruefung {
        let kontext = ek.kontext
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return .nichtMoeglich }
        do {
            let ok = try await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Lumen Cloud entsperren")
            return ok ? .ok : .abgelehnt
        } catch {
            return .abgelehnt
        }
    }
}

/// Die Sperrfläche über der ganzen App.
struct SperrAnsicht: View {
    let sperre: AppSperre

    var body: some View {
        VStack(spacing: Abstand.l) {
            Spacer()
            HausherzView(stimmung: .schlaeft, groesse: 140)
            Text("Lumen Cloud ist gesperrt")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
            if let meldung = sperre.meldung {
                Text(meldung)
                    .font(.subheadline)
                    .foregroundStyle(Color.schlecht)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await sperre.entsperren() }
            } label: {
                Label("Entsperren", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.knopf)
            .foregroundStyle(Color.aufKnopf)
            .controlSize(.large)
            .disabled(sperre.pruefungLaeuft)
        }
        .padding(Abstand.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Hintergrund() }
        .task { await sperre.entsperren() }
    }
}

/// Deckt den Inhalt ab, sobald die App nicht aktiv ist: im App-Umschalter steht dann nur das Haus, nie ein Passwort.
struct DeckFlaeche: View {
    var body: some View {
        HausherzView(stimmung: .schlaeft, groesse: 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Hintergrund() }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
