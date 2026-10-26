// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI

/// Fließende Höhenlinien wie auf einer Karte, selbst gezeichnet (kein Bild, keine fremde Grafik). Statisch, billig, deterministisch.
/// Kopierbar: braucht nur SwiftUI. Linienfarbe über `linie`, Deckkraft über `staerke`.
struct TopoHintergrund: View {
    var linie: Color = .white
    var staerke: Double = 0.16
    var anzahl = 34
    /// Zeit in Sekunden (fließend) plus Scroll-Versatz in pt; 0 = die ruhige Ausgangsform.
    var zeit: Double = 0
    var versatz: Double = 0

    var body: some View {
        Canvas { kontext, groesse in
            let breite = groesse.width, hoehe = groesse.height
            for i in 0..<anzahl {
                let t = Double(i) / Double(anzahl)
                var pfad = Path()
                var x = -8.0
                while x <= breite + 8 {
                    let u = x / breite
                    // Zwei Wellen plus eine Beule: benachbarte Linien verschieben sich nur leicht, so entstehen Höhenlinien.
                    let phase = zeit * 0.18 + versatz * 0.004
                    let welle = sin(u * 5.2 + t * 6.0 + phase) * 0.045 + sin(u * 11.0 - t * 9.0 + 1.3 - phase * 1.7) * 0.016
                    let beule = exp(-pow((u - 0.35 - 0.10 * sin(phase * 0.7)) * 3.2, 2)) * 0.16 * sin(t * 3.1 + 0.6 + phase * 0.5)
                    let y = (t * 1.25 - 0.1 + welle + beule) * hoehe
                    if x < 0 { pfad.move(to: CGPoint(x: x, y: y)) } else { pfad.addLine(to: CGPoint(x: x, y: y)) }
                    x += 6
                }
                kontext.stroke(pfad, with: .color(linie.opacity(staerke)), lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}


/// Fließende Höhenlinien wie bei Revolut: langsam bewegt, reagieren leicht auf den Scroll-Versatz. Pausiert bei Reduce Motion, Stromsparmodus
/// und wenn die App nicht aktiv ist (kein Akku-Verbrauch); dann steht die zuletzt gezeichnete Form. Höchstens 24 Bilder je Sekunde.
struct FliessTopo: View {
    var linie: Color = .tinte
    var staerke: Double = 0.09
    var versatz: CGFloat = 0

    @LumenStill private var reduceMotion
    @Environment(\.scenePhase) private var szene
    @State private var sparmodus = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let ruhig = reduceMotion || sparmodus || szene != .active
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: ruhig)) { zeit in
            TopoHintergrund(linie: linie, staerke: staerke, zeit: zeit.date.timeIntervalSinceReferenceDate, versatz: Double(versatz))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            sparmodus = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// Grundfläche der Bildschirme (Revolut-Stil): flaches `grund` (Schwarz im Dunkeln), oben fließende Topo-Linien, die nach unten auslaufen.
/// Bei erhöhtem Kontrast bleibt die Fläche glatt. Reicht unter Tab- und Navigationsleiste (keine Farbfläche unter Steuerung).
struct Hintergrund: View {
    var versatz: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var kontrast
    @Environment(\.colorScheme) private var schema

    var body: some View {
        ZStack(alignment: .top) {
            Color.grund
            if kontrast != .increased {
                FliessTopo(linie: .tinte, staerke: schema == .dark ? 0.16 : 0.09, versatz: versatz)
                    .frame(height: 560)
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Setzt den Lumen-Hintergrund hinter die Ansicht. `versatz` = Scroll-Versatz (`.scrollVersatz`), die Linien schieben sich leicht mit.
    func lumenHintergrund(versatz: CGFloat = 0) -> some View {
        background { Hintergrund(versatz: versatz) }
    }

    /// Titel einer Tab-Wurzel: der System-Großtitel ist weder gerundet noch getönt, hier steht er in Rounded, kräftig und in Tinte
    /// (iOS 26: `.largeTitle` ersetzt nur die große Darstellung, der kleine Titel beim Scrollen bleibt der Systemtitel).
    func lumenGrossTitel(_ titel: String) -> some View {
        navigationTitle(titel)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Text(titel)
                        .font(.largeTitle.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.tinte)
                }
                .sharedBackgroundVisibility(.hidden)   // sonst legt iOS 26 eine Glaskapsel um den Titel
            }
    }
}
