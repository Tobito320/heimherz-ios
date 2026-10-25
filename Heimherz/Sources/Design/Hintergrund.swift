import SwiftUI

/// Grundfläche der Bildschirme: flaches `grund`, darüber ein statisches, sehr kontrastarmes Mesh. Bei erhöhtem Kontrast bleibt es flach.
struct Hintergrund: View {
    @Environment(\.colorSchemeContrast) private var kontrast

    var body: some View {
        ZStack {
            Color.grund
            if kontrast != .increased {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.55, 0.45], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        .grund, .grundWarm.opacity(0.6), .grund,
                        .heroZwei.opacity(0.5), .grund, .grundWarm.opacity(0.6),
                        .grund, .heroDrei.opacity(0.5), .grund
                    ]
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Setzt den Heimherz-Hintergrund hinter die Ansicht.
    func heimherzHintergrund() -> some View {
        background { Hintergrund() }
    }
}
