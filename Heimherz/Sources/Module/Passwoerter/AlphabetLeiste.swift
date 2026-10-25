import SwiftUI

/// Die A bis Z Leiste am rechten Rand wie in der Passwörter-App: über die Buchstaben ziehen springt zum Abschnitt, jeder Wechsel tickt leise.
/// Für VoiceOver verborgen (dort geht man durch die Liste). Es erscheinen nur Buchstaben, zu denen es einen Abschnitt gibt.
struct AlphabetLeiste: View {
    let buchstaben: [String]
    var waehle: (String) -> Void

    @State private var aktiv: String?

    var body: some View {
        GeometryReader { geo in
            let hoehe = geo.size.height / CGFloat(max(1, buchstaben.count))
            VStack(spacing: 0) {
                ForEach(buchstaben, id: \.self) { b in
                    Text(b)
                        .font(.system(size: min(12, max(7, hoehe * 0.7)), weight: .semibold))
                        .foregroundStyle(Color.gruen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { wert in
                        let i = min(max(Int(wert.location.y / max(1, hoehe)), 0), buchstaben.count - 1)
                        guard buchstaben.indices.contains(i), buchstaben[i] != aktiv else { return }
                        aktiv = buchstaben[i]
                        Haptik.auswahl()
                        waehle(buchstaben[i])
                    }
                    .onEnded { _ in aktiv = nil }
            )
        }
        .frame(width: 24)
        .accessibilityHidden(true)
    }
}
