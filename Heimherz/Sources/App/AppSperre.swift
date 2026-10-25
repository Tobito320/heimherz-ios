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
@MainActor @Observable
final class AppSperre {
    private(set) var gesperrt: Bool
    private(set) var meldung: String?
    private(set) var pruefungLaeuft = false
    private var hintergrundSeit: Date?
    let aktiv: Bool

    init(gesperrt: Bool, aktiv: Bool) {
        self.aktiv = aktiv
        self.gesperrt = aktiv && gesperrt
    }

    func szene(_ phase: ScenePhase, jetzt: Date = Date()) {
        guard aktiv else { return }
        switch phase {
        case .background:
            if hintergrundSeit == nil { hintergrundSeit = jetzt }
        case .active:
            if SperrLogik.sollSperren(hintergrundSeit: hintergrundSeit, jetzt: jetzt) { gesperrt = true }
            hintergrundSeit = nil
        default:
            break
        }
    }

    func entsperren() async {
        guard gesperrt, !pruefungLaeuft else { return }
        pruefungLaeuft = true
        meldung = nil
        switch await Self.pruefeGeraet() {
        case .ok, .nichtMoeglich: gesperrt = false       // ohne Gerätecode gibt es nichts zu prüfen
        case .abgelehnt: meldung = "Entsperren hat nicht geklappt. Bitte noch einmal versuchen."
        }
        pruefungLaeuft = false
    }

    enum Pruefung: Sendable { case ok, abgelehnt, nichtMoeglich }

    /// Face ID, sonst Gerätecode. Eigener Kontext in der Funktion, damit nichts Nicht-Sendbares die Isolation wechselt.
    @concurrent
    private static func pruefeGeraet() async -> Pruefung {
        let kontext = LAContext()
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return .nichtMoeglich }
        do {
            let ok = try await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Heimherz entsperren")
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
            Text("Heimherz ist gesperrt")
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
