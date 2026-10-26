import SwiftUI

// Bewegungs-Katalog der Lumen-Familie (neben `Feder.swift`): Skelett mit Shimmer, Erfolgs-Haken, zeichnende Striche, Scroll-Versatz,
// geteilte Übergänge. Alles beachtet Reduce Motion. Braucht nur SwiftUI und die Farb-Tokens (`chip`, `ok`, `tinte`).

/// Ein heller Streifen läuft über die Fläche (Platzhalter beim Laden). Reduce Motion: stehende Fläche.
struct Shimmer: ViewModifier {
    let aktiv: Bool
    @State private var lauf: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .background(Color.karte, in: .heimherzKarte)
        .accessibilityLabel("Lädt")
    }
}

/// Der Haken im Kreis, der sich beim Erscheinen zeichnet (Kreis, dann Haken), mit Erfolgs-Haptik. Reduce Motion: sofort fertig.
struct ErfolgsHaken: View {
    var groesse: CGFloat = 56
    var haptik = true
    @State private var fertig = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

/// Eine Form, die sich beim Erscheinen von vorn nach hinten zeichnet (Diagramm-Linien, Ringe). Reduce Motion: sofort ganz.
struct ZeichnenderStrich<Form: Shape>: View {
    let form: Form
    var farbe: Color = .knopf
    var breite: CGFloat = 3
    var dauer: Double = 1.0
    @State private var bis: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
