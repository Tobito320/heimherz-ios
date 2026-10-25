import UIKit

/// Hängt zwei Dinge ein, die SwiftUI nicht kennt: die Systemaufgaben des Foto-Abgleichs (müssen vor dem Ende des App-Starts registriert sein)
/// und die Zustellung von Hintergrund-Uploads, die fertig wurden, während die App beendet war.
@MainActor
final class HeimherzAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Im Test-Host startet nichts (kein Info.plist-Eintrag nötig, kein doppeltes Registrieren).
        if !AppUmgebung.istTestHost { FotoHintergrund.registriere() }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String) async {
        guard identifier == HintergrundUpload.sitzungsKennung else { return }
        await HintergrundUpload.geteilt.warteAufEreignisse()
    }
}
