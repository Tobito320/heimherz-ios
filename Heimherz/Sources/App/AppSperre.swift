import LocalAuthentication
import Observation
import SwiftUI

/// Wann die App sperrt: nach 5 Minuten im Hintergrund (SPEC 8, 9).
enum SperrLogik {
    static let sekunden: TimeInterval = 300

    static func sollSperren(hintergrundSeit: Date?, jetzt: Date) -> Bool {
        guard let seit = hintergrundSeit else { return false }
        return jetzt.timeIntervalSince(seit) >= sekunden
    }
}

/// Die App-Sperre mit Face ID (oder Gerätecode). `aktiv` ist aus im Test-Host und im Demo-Modus, sonst würde dort Face ID gefragt.
/// Gesperrt wird beim Kaltstart (wenn gekoppelt) und nach 5 Minuten im Hintergrund.
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

    init(gesperrt: Bool, aktiv: Bool) {
        self.aktiv = aktiv
        self.gesperrt = aktiv && gesperrt
    }

    func szene(_ phase: ScenePhase, jetzt: Date = Date()) {
        guard aktiv else { return }
        switch phase {
        case .inactive:
            verdeckt = true
        case .background:
            verdeckt = true
            if hintergrundSeit == nil { hintergrundSeit = jetzt }
        case .active:
            verdeckt = false
            if SperrLogik.sollSperren(hintergrundSeit: hintergrundSeit, jetzt: jetzt) {
                gesperrt = true
                neuerKontext()
            }
            hintergrundSeit = nil
        default:
            break
        }
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
        case .ok, .nichtMoeglich: gesperrt = false       // ohne Gerätecode gibt es nichts zu prüfen
        case .abgelehnt:
            meldung = "Entsperren hat nicht geklappt. Bitte noch einmal versuchen."
            neuerKontext()
        }
        pruefungLaeuft = false
    }

    enum Pruefung: Sendable { case ok, abgelehnt, nichtMoeglich }

    /// Face ID, sonst Gerätecode, im Kontext der Sperre (`EntsperrKontext` ist als Sendable markiert, siehe dort).
    @concurrent
    private static func pruefeGeraet(_ ek: EntsperrKontext) async -> Pruefung {
        let kontext = ek.kontext
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return .nichtMoeglich }
        do {
            let ok = try await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Heim entsperren")
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
            Text("Heim ist gesperrt")
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
