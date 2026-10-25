import Foundation
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers

/// Kopieren in die Zwischenablage: nur auf diesem Gerät (kein Universal Clipboard zu Mac oder iPad) und nach 60 Sekunden wieder weg (SPEC 9).
@MainActor
enum Zwischenablage {
    static let ablaufSekunden: TimeInterval = 60

    static func optionen(jetzt: Date = Date()) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: jetzt.addingTimeInterval(ablaufSekunden)]
    }

    static func kopiere(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: optionen())
    }
}

/// Gerätecode oder Face ID vor dem Anzeigen eines Passworts.
enum GeraeteAbfrage {
    /// true bei Erfolg oder wenn das Gerät gar keinen Code hat (dann gibt es nichts zu prüfen, wie bei der App-Sperre).
    @concurrent
    static func pruefe(grund: String) async -> Bool {
        let kontext = LAContext()
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return true }
        return (try? await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: grund)) ?? false
    }
}
