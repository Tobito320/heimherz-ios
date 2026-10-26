// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI
import UIKit

/// Ein Satz Federn für alle Lumen-Apps. Unter Reduce Motion überblenden Aufrufer stattdessen. Stromsparmodus: ohne Überschwinger.
enum Feder {
    static let schnell: Animation = .snappy(duration: 0.28)
    static let weich: Animation = .smooth(duration: 0.38)
    /// Tab-Wechsel und Umschalter.
    static let tab: Animation = .snappy(duration: 0.32, extraBounce: 0.08)
    /// Sheets, Karten, die aufgehen: etwas Schwung, kaum Überschwinger.
    static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.82)
    /// Zahlen-Ticker (ZaehltHoch) und Zeichen-Animationen.
    static let ticker: Animation = .easeOut(duration: 0.9)
    /// Abstand zwischen zwei Elementen beim gestaffelten Aufbau (s) und höchste Stufe.
    static let staffel: Double = 0.05
    static let staffelMax = 8
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
    @LumenStill private var reduceMotion

    var body: some View {
        konfiguration.label
            .scaleEffect(konfiguration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(konfiguration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion || konfiguration.isPressed ? Feder.schnell : Feder.jelly, value: konfiguration.isPressed)
    }
}

/// Zahl, die beim Erscheinen von 0 hochzählt (und bei neuem Wert weiterzählt, ausgebremst am Ende). Reduce Motion: sofort der Endwert.
/// Der Text kommt fertig formatiert aus `format`, damit Aufrufer Tausenderpunkte, Einheiten oder Cent selbst bestimmen.
/// Zählt per Aufgabe in 30 Schritten statt per `Animatable`: Swift 6 lässt `Animatable` auf einer View nicht zu (Hauptakteur).
struct ZaehltHoch: View {
    let wert: Int
    var groesse: CGFloat = 52
    var format: (Int) -> String = { $0.formatted(.number.locale(Locale(identifier: "de_DE"))) }

    @State private var angezeigt = 0
    @LumenStill private var reduceMotion

    var body: some View {
        BetragGross(text: format(angezeigt), groesse: groesse)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(format(wert))
            .task(id: wert) { await zaehle(auf: wert) }
    }

    private func zaehle(auf ziel: Int) async {
        let start = angezeigt
        guard !reduceMotion, start != ziel else { angezeigt = ziel; return }
        let schritte = 30
        for i in 1...schritte {
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return }
            let t = Double(i) / Double(schritte)
            angezeigt = start + Int((Double(ziel - start) * (1 - pow(1 - t, 3))).rounded())
        }
        angezeigt = ziel
    }
}

/// Baut ein Element beim ersten Erscheinen auf: von unten, leicht kleiner, versetzt nach `index` (höchstens 8 Stufen). Reduce Motion: sofort da.
struct Aufbau: ViewModifier {
    let index: Int
    @State private var da = false
    @LumenStill private var reduceMotion

    func body(content: Content) -> some View {
        let sichtbar = da || reduceMotion
        content
            .opacity(sichtbar ? 1 : 0)
            .offset(y: sichtbar ? 0 : 18)
            .scaleEffect(sichtbar ? 1 : 0.96)
            .onAppear {
                guard !da else { return }
                withAnimation(Feder.weich.delay(Double(min(index, Feder.staffelMax)) * Feder.staffel)) { da = true }
            }
    }
}

extension View {
    /// `.aufbau(3)`: erscheint als vierter in der Reihe.
    func aufbau(_ index: Int = 0) -> some View { modifier(Aufbau(index: index)) }
}

// Bewegungs-Katalog der Lumen-Familie (neben `Feder.swift`): Skelett mit Shimmer, Erfolgs-Haken, zeichnende Striche, Scroll-Versatz,
// geteilte Übergänge. Alles beachtet Reduce Motion. Braucht nur SwiftUI und die Farb-Tokens (`chip`, `ok`, `tinte`).

/// Ein heller Streifen läuft über die Fläche (Platzhalter beim Laden). Reduce Motion: stehende Fläche.
struct Shimmer: ViewModifier {
    let aktiv: Bool
    @State private var lauf: CGFloat = -1
    @LumenStill private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if aktiv && !reduceMotion {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Color.tinte.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.6)
                            .offset(x: lauf * g.size.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard aktiv, !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { lauf = 1.4 }
            }
    }
}

extension View {
    func shimmer(_ aktiv: Bool = true) -> some View { modifier(Shimmer(aktiv: aktiv)) }
}

/// Grauer Platzhalter-Balken mit Shimmer.
struct Skelett: View {
    var hoehe: CGFloat = 16
    var breite: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: hoehe / 2, style: .continuous)
            .fill(Color.chip)
            .frame(width: breite, height: hoehe)
            .shimmer()
            .accessibilityHidden(true)
    }
}

/// Platzhalter einer Listenkarte: `zeilen` Zeilen aus rundem Symbol und zwei Balken.
struct SkelettKarte: View {
    var zeilen = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.l) {
            ForEach(0..<zeilen, id: \.self) { i in
                HStack(spacing: Abstand.m) {
                    Circle().fill(Color.chip).frame(width: 36, height: 36).shimmer()
                    VStack(alignment: .leading, spacing: Abstand.xs) {
                        Skelett(hoehe: 14, breite: 140 + CGFloat(i % 3) * 30)
                        Skelett(hoehe: 10, breite: 90)
                    }
                }
            }
        }
        .padding(Abstand.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.karte, in: .lumenKarte)
        .accessibilityLabel("Lädt")
    }
}

/// Eine Form, die sich beim Erscheinen von vorn nach hinten zeichnet (Diagramm-Linien, Ringe). Reduce Motion: sofort ganz.
struct ZeichnenderStrich<Form: Shape>: View {
    let form: Form
    var farbe: Color = .knopf
    var breite: CGFloat = 3
    var dauer: Double = 1.0
    @State private var bis: CGFloat = 0
    @LumenStill private var reduceMotion

    var body: some View {
        form.trim(from: 0, to: bis)
            .stroke(farbe, style: StrokeStyle(lineWidth: breite, lineCap: .round, lineJoin: .round))
            .onAppear {
                if reduceMotion { bis = 1 } else { withAnimation(.easeOut(duration: dauer)) { bis = 1 } }
            }
    }
}

extension View {
    /// Schreibt den senkrechten Scroll-Versatz (pt, 0 oben) in `versatz`: für schrumpfende Köpfe und den fließenden Hintergrund.
    func scrollVersatz(_ versatz: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self, of: { max(0, $0.contentOffset.y + $0.contentInsets.top) }) { _, neu in versatz.wrappedValue = neu }
    }

    /// Kopf, der beim Scrollen kleiner wird und verblasst (Hero-Zahl). `versatz` kommt aus `scrollVersatz`. Reduce Motion: bleibt stehen.
    func schrumpftBeimScrollen(_ versatz: CGFloat, reduceMotion: Bool = false) -> some View {
        scaleEffect(reduceMotion ? 1 : max(0.72, 1 - versatz / 420), anchor: .top)
            .opacity(reduceMotion ? 1 : max(0, 1 - versatz / 240))
    }

    /// Geteilter Übergang: Quelle (Kachel) und Ziel (Seite) zoomen ineinander.
    func zoomQuelle<ID: Hashable>(_ id: ID, in raum: Namespace.ID) -> some View { matchedTransitionSource(id: id, in: raum) }
    func zoomZiel<ID: Hashable>(_ id: ID, in raum: Namespace.ID) -> some View { navigationTransition(.zoom(sourceID: id, in: raum)) }
}
