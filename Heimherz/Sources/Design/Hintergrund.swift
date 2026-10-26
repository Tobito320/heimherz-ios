import SwiftUI

/// Fließende Höhenlinien wie bei Revolut: langsam bewegt, reagieren leicht auf den Scroll-Versatz. Pausiert bei Reduce Motion, Stromsparmodus
/// und wenn die App nicht aktiv ist (kein Akku-Verbrauch); dann steht die zuletzt gezeichnete Form. Höchstens 24 Bilder je Sekunde.
struct FliessTopo: View {
    var linie: Color = .tinte
    var staerke: Double = 0.09
    var versatz: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    func heimherzHintergrund(versatz: CGFloat = 0) -> some View {
        background { Hintergrund(versatz: versatz) }
    }

    /// Titel einer Tab-Wurzel: der System-Großtitel ist weder gerundet noch getönt, hier steht er in Rounded, kräftig und in Tinte
    /// (iOS 26: `.largeTitle` ersetzt nur die große Darstellung, der kleine Titel beim Scrollen bleibt der Systemtitel).
    func heimherzGrossTitel(_ titel: String) -> some View {
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
