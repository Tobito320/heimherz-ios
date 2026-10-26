import UIKit

/// Haptik mit fester Bedeutung, nur bei klarer Ursache.
@MainActor
enum Haptik {
    static func erfolg() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func fehler() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func auswahl() { UISelectionFeedbackGenerator().selectionChanged() }
}
