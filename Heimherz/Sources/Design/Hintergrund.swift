import SwiftUI

/// Grundfläche der Bildschirme (Revolut-Stil): flaches `grund` (Schwarz im Dunkeln), oben ein feines Topo-Linienmuster, das nach unten ausläuft.
/// Bei erhöhtem Kontrast bleibt die Fläche glatt. Reicht unter Tab- und Navigationsleiste (keine Farbfläche unter Steuerung).
struct Hintergrund: View {
    @Environment(\.colorSchemeContrast) private var kontrast
    @Environment(\.colorScheme) private var schema

    var body: some View {
        ZStack(alignment: .top) {
            Color.grund
            if kontrast != .increased {
                TopoHintergrund(linie: .tinte, staerke: schema == .dark ? 0.16 : 0.09)
                    .frame(height: 560)
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Setzt den Cloud-Hintergrund hinter die Ansicht.
    func heimherzHintergrund() -> some View {
        background { Hintergrund() }
    }

    /// Titel einer Tab-Wurzel: der System-Großtitel ist weder gerundet noch getönt, hier steht er in Rounded, kräftig und in
    /// Tinte (iOS 26: `.largeTitle` ersetzt nur die große Darstellung, der kleine Titel beim Scrollen bleibt der Systemtitel).
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
