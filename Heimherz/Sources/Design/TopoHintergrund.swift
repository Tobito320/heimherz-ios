import SwiftUI

/// Fließende Höhenlinien wie auf einer Karte, selbst gezeichnet (kein Bild, keine fremde Grafik). Statisch, billig, deterministisch.
/// Kopierbar: braucht nur SwiftUI. Linienfarbe über `linie`, Deckkraft über `staerke`.
struct TopoHintergrund: View {
    var linie: Color = .white
    var staerke: Double = 0.16
    var anzahl = 34

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
                    let welle = sin(u * 5.2 + t * 6.0) * 0.045 + sin(u * 11.0 - t * 9.0 + 1.3) * 0.016
                    let beule = exp(-pow((u - 0.35) * 3.2, 2)) * 0.16 * sin(t * 3.1 + 0.6)
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
