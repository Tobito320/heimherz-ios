import UIKit
import UniformTypeIdentifiers

/// Der Einmalcode in der Zwischenablage nach dem Ausfüllen des Passworts (Einstellung `codeKopieren`): nur auf diesem Gerät
/// (`localOnly`, kein Universal Clipboard) und nach 60 Sekunden wieder weg, wie beim Kopieren in der App.
@MainActor
enum CodeAblage {
    static let ablaufSekunden: TimeInterval = 60

    static func optionen(jetzt: Date = Date()) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: jetzt.addingTimeInterval(ablaufSekunden)]
    }

    static func kopiere(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: optionen())
    }
}
