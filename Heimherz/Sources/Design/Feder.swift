import SwiftUI
import UIKit

/// Ein Satz Federn für die ganze App. Unter Reduce Motion überblenden Aufrufer stattdessen. Stromsparmodus: ohne Überschwinger.
enum Feder {
    static let schnell: Animation = .snappy(duration: 0.28)
    static let weich: Animation = .smooth(duration: 0.38)
    static var jelly: Animation {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? schnell : .spring(response: 0.32, dampingFraction: 0.55)
    }
}

/// Knöpfe weichen beim Drücken aus (0,94) und federn zurück. Reduce Motion: keine Bewegung, nur gedimmt.
struct FederKnopfStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FederKnopfInhalt(konfiguration: configuration)
    }
}

extension ButtonStyle where Self == FederKnopfStil {
    static var federnd: FederKnopfStil { FederKnopfStil() }
}

private struct FederKnopfInhalt: View {
    let konfiguration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        konfiguration.label
            .scaleEffect(konfiguration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(konfiguration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion || konfiguration.isPressed ? Feder.schnell : Feder.jelly, value: konfiguration.isPressed)
    }
}

/// Haptik mit fester Bedeutung, nur bei klarer Ursache.
@MainActor
enum Haptik {
    static func erfolg() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func fehler() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func auswahl() { UISelectionFeedbackGenerator().selectionChanged() }
}
