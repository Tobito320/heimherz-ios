import UIKit

/// Hängt Dinge ein, die SwiftUI nicht kennt: die Systemaufgaben des Foto-Abgleichs (müssen vor dem Ende des App-Starts registriert sein),
/// die Zustellung von Hintergrund-Uploads, die fertig wurden, während die App beendet war, und die Schnellaktionen am App-Symbol.
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

    /// Kaltstart per Schnellaktion: das Element steckt in den Verbindungsoptionen (`windowScene(_:performActionFor:)` kommt dann nicht).
    /// Genau hier wird es abgelegt, nirgends sonst, damit es nicht doppelt läuft.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let element = options.shortcutItem, let aktion = Schnellaktion(typ: element.type) { SchnellaktionPostfach.geteilt.lege(aktion) }
        let konfiguration = UISceneConfiguration(name: connectingSceneSession.configuration.name, sessionRole: connectingSceneSession.role)
        konfiguration.delegateClass = HeimherzSzenenDelegate.self
        return konfiguration
    }
}

/// Nimmt die Schnellaktion bei laufender App an (Warmstart). SwiftUI baut Fenster und Inhalt weiter selbst.
@MainActor
final class HeimherzSzenenDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let aktion = Schnellaktion(typ: shortcutItem.type) else { return false }
        SchnellaktionPostfach.geteilt.lege(aktion)
        return true
    }
}
