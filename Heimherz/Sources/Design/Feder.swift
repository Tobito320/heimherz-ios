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

/// Zahl, die beim Erscheinen von 0 hochzählt (und bei neuem Wert weiterzählt). Reduce Motion: sofort der Endwert.
/// Der Text kommt fertig formatiert aus `format`, damit Aufrufer Tausenderpunkte, Einheiten oder Cent selbst bestimmen.
struct ZaehltHoch: View {
    let wert: Int
    var groesse: CGFloat = 52
    var format: (Int) -> String = { $0.formatted(.number.locale(Locale(identifier: "de_DE"))) }

    @State private var angezeigt: Double = 0
    @State private var gestartet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZaehlerText(wert: angezeigt, groesse: groesse, format: format)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(format(wert))
            .onAppear {
                guard !gestartet else { return }
                gestartet = true
                if reduceMotion { angezeigt = Double(wert) } else { withAnimation(.easeOut(duration: 0.9)) { angezeigt = Double(wert) } }
            }
            .onChange(of: wert) { _, neu in
                if reduceMotion { angezeigt = Double(neu) } else { withAnimation(.easeOut(duration: 0.6)) { angezeigt = Double(neu) } }
            }
    }
}

/// Zeichnet die gerade animierte Zahl; SwiftUI ruft `body` je Bild mit dem Zwischenwert.
private struct ZaehlerText: View, Animatable {
    var wert: Double
    let groesse: CGFloat
    let format: (Int) -> String

    var animatableData: Double {
        get { wert }
        set { wert = newValue }
    }

    var body: some View { BetragGross(text: format(Int(wert.rounded())), groesse: groesse) }
}

/// Baut ein Element beim ersten Erscheinen auf: von unten, leicht kleiner, versetzt nach `index` (höchstens 8 Stufen). Reduce Motion: sofort da.
struct Aufbau: ViewModifier {
    let index: Int
    @State private var da = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let sichtbar = da || reduceMotion
        content
            .opacity(sichtbar ? 1 : 0)
            .offset(y: sichtbar ? 0 : 18)
            .scaleEffect(sichtbar ? 1 : 0.96)
            .onAppear {
                guard !da else { return }
                withAnimation(Feder.weich.delay(Double(min(index, 8)) * 0.05)) { da = true }
            }
    }
}

extension View {
    /// `.aufbau(3)`: erscheint als vierter in der Reihe.
    func aufbau(_ index: Int = 0) -> some View { modifier(Aufbau(index: index)) }
}
