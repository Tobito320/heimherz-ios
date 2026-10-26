// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import UIKit

/// Haptik mit fester Bedeutung, nur bei klarer Ursache. Der Schalter "Haptik" der Standard-Einstellungen (`LumenEinstellung.haptikSchluessel`) schaltet alles aus.
@MainActor
enum Haptik {
    static var an: Bool { UserDefaults.standard.object(forKey: LumenEinstellung.haptikSchluessel) as? Bool ?? true }
    static func erfolg() { if an { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func fehler() { if an { UINotificationFeedbackGenerator().notificationOccurred(.error) } }
    static func auswahl() { if an { UISelectionFeedbackGenerator().selectionChanged() } }
}
