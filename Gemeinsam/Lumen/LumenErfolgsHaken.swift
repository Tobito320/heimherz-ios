// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI

/// Der Haken im Kreis, der sich beim Erscheinen zeichnet (Kreis, dann Haken), mit Erfolgs-Haptik. Reduce Motion: sofort fertig.
struct ErfolgsHaken: View {
    var groesse: CGFloat = 56
    var haptik = true
    @State private var fertig = false
    @LumenStill private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Color.okGrund)
            Circle()
                .trim(from: 0, to: fertig ? 1 : 0)
                .stroke(Color.ok, style: StrokeStyle(lineWidth: max(2, groesse * 0.06), lineCap: .round))
                .rotationEffect(.degrees(-90))
            HakenForm()
                .trim(from: 0, to: fertig ? 1 : 0)
                .stroke(Color.ok, style: StrokeStyle(lineWidth: max(2.5, groesse * 0.08), lineCap: .round, lineJoin: .round))
                .padding(groesse * 0.26)
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(true)
        .onAppear {
            guard !fertig else { return }
            if reduceMotion { fertig = true } else { withAnimation(.easeOut(duration: 0.7)) { fertig = true } }
            if haptik { Haptik.erfolg() }
        }
    }
}

private struct HakenForm: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 0.04 * rect.width, y: rect.minY + 0.54 * rect.height))
        p.addLine(to: CGPoint(x: rect.minX + 0.38 * rect.width, y: rect.minY + 0.86 * rect.height))
        p.addLine(to: CGPoint(x: rect.minX + 0.96 * rect.width, y: rect.minY + 0.18 * rect.height))
        return p
    }
}
