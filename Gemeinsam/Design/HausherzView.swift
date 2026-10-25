import SwiftUI

enum HausherzStimmung: String, CaseIterable, Sendable {
    case wach, schlaeft, jubelt, sorry

    /// Für VoiceOver, wenn das Maskottchen eine Aussage trägt.
    var beschreibung: String {
        switch self {
        case .wach: return "Hausherz lächelt"
        case .schlaeft: return "Hausherz schläft"
        case .jubelt: return "Hausherz jubelt"
        case .sorry: return "Hausherz ist traurig"
        }
    }
}

/// Feste Farben des Maskottchens: Augen, Wangen und Herz schlagen im Dunkelmodus nicht um (wie Tschuli in Bahnherz).
private enum HausFarbe {
    static func hex(_ wert: UInt32) -> Color {
        Color(.sRGB, red: Double((wert >> 16) & 0xFF) / 255, green: Double((wert >> 8) & 0xFF) / 255, blue: Double(wert & 0xFF) / 255, opacity: 1)
    }
    static let koerper = hex(0xF8F3DC)
    static let dach = hex(0xB93A2B)
    static let schornstein = hex(0x8F2B1F)
    static let tinte = hex(0x15281A)
    static let wange = hex(0xF4B9AE)
}

/// Die Formen des Hauses als Pfade in einem Quadrat der Kantenlänge `s`.
private enum HausPfade {
    static func koerper(_ s: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: 0.16 * s, y: 0.46 * s, width: 0.68 * s, height: 0.46 * s), cornerRadius: 0.07 * s)
    }

    static func dach(_ s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.50 * s, y: 0.07 * s))
        p.addLine(to: CGPoint(x: 0.95 * s, y: 0.52 * s))
        p.addLine(to: CGPoint(x: 0.05 * s, y: 0.52 * s))
        p.closeSubpath()
        return p
    }

    static func schornstein(_ s: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: 0.68 * s, y: 0.12 * s, width: 0.10 * s, height: 0.20 * s), cornerRadius: 0.02 * s)
    }

    /// Das Herz im Dach.
    static func herz(_ s: CGFloat) -> Path {
        let x = 0.50 * s, y = 0.34 * s, w = 0.22 * s, h = 0.20 * s
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + 0.5 * h))
        p.addCurve(to: CGPoint(x: x - 0.5 * w, y: y - 0.15 * h), control1: CGPoint(x: x - 0.10 * w, y: y + 0.30 * h), control2: CGPoint(x: x - 0.5 * w, y: y + 0.20 * h))
        p.addCurve(to: CGPoint(x: x, y: y - 0.25 * h), control1: CGPoint(x: x - 0.5 * w, y: y - 0.55 * h), control2: CGPoint(x: x - 0.05 * w, y: y - 0.50 * h))
        p.addCurve(to: CGPoint(x: x + 0.5 * w, y: y - 0.15 * h), control1: CGPoint(x: x + 0.05 * w, y: y - 0.50 * h), control2: CGPoint(x: x + 0.5 * w, y: y - 0.55 * h))
        p.addCurve(to: CGPoint(x: x, y: y + 0.5 * h), control1: CGPoint(x: x + 0.5 * w, y: y + 0.20 * h), control2: CGPoint(x: x + 0.10 * w, y: y + 0.30 * h))
        p.closeSubpath()
        return p
    }

    static func augenOffen(_ s: CGFloat) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 0.35 * s, y: 0.60 * s, width: 0.06 * s, height: 0.07 * s))
        p.addEllipse(in: CGRect(x: 0.59 * s, y: 0.60 * s, width: 0.06 * s, height: 0.07 * s))
        return p
    }

    /// Geschlossene Augen als kleine Bögen (nach unten gewölbt = schläft, nach oben = jubelt).
    static func augenBogen(_ s: CGFloat, nachOben: Bool) -> Path {
        var p = Path()
        for mitteX in [0.38, 0.62] {
            let x = CGFloat(mitteX) * s
            let y = 0.64 * s
            p.move(to: CGPoint(x: x - 0.045 * s, y: y))
            p.addQuadCurve(to: CGPoint(x: x + 0.045 * s, y: y), control: CGPoint(x: x, y: y + (nachOben ? -0.07 : 0.07) * s))
        }
        return p
    }

    static func wangen(_ s: CGFloat) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 0.24 * s, y: 0.69 * s, width: 0.09 * s, height: 0.055 * s))
        p.addEllipse(in: CGRect(x: 0.67 * s, y: 0.69 * s, width: 0.09 * s, height: 0.055 * s))
        return p
    }

    static func muender(_ s: CGFloat, traurig: Bool) -> Path {
        var p = Path()
        let y = (traurig ? 0.76 : 0.71) * s
        p.move(to: CGPoint(x: 0.44 * s, y: y))
        p.addQuadCurve(to: CGPoint(x: 0.56 * s, y: y), control: CGPoint(x: 0.50 * s, y: y + (traurig ? -0.05 : 0.06) * s))
        return p
    }
}

private struct FormPfad: Shape {
    let pfad: @Sendable (CGFloat) -> Path
    func path(in rect: CGRect) -> Path { pfad(min(rect.width, rect.height)) }
}

/// Hausherz, das kleine Haus mit Herz im Dach: das Maskottchen von Heimherz. Reine Formen, keine Bild-Assets, skaliert als Vektor.
/// Größen: 40 (Liste), 96 (Leerzustand), 160 (Hero). Dekoration ist für VoiceOver versteckt, außer `beschriftet` ist wahr.
struct HausherzView: View {
    var stimmung: HausherzStimmung = .wach
    var groesse: CGFloat = 96
    var beschriftet = false

    var body: some View {
        let strich = StrokeStyle(lineWidth: max(1.5, groesse * 0.03), lineCap: .round)
        let traurig = stimmung == .sorry   // als Wert herausziehen: die Formen-Closures sind @Sendable und dürfen `self` nicht anfassen
        ZStack {
            FormPfad(pfad: HausPfade.schornstein).fill(HausFarbe.schornstein)
            FormPfad(pfad: HausPfade.koerper).fill(HausFarbe.koerper)
            FormPfad(pfad: HausPfade.dach).fill(HausFarbe.dach)
            FormPfad(pfad: HausPfade.herz).fill(HausFarbe.koerper)
            FormPfad(pfad: HausPfade.wangen).fill(HausFarbe.wange)
            augen(strich)
            FormPfad(pfad: { HausPfade.muender($0, traurig: traurig) }).stroke(HausFarbe.tinte, style: strich)
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(!beschriftet)
        .accessibilityLabel(beschriftet ? stimmung.beschreibung : "")
    }

    @ViewBuilder
    private func augen(_ strich: StrokeStyle) -> some View {
        switch stimmung {
        case .wach, .sorry:
            FormPfad(pfad: HausPfade.augenOffen).fill(HausFarbe.tinte)
        case .schlaeft:
            FormPfad(pfad: { HausPfade.augenBogen($0, nachOben: false) }).stroke(HausFarbe.tinte, style: strich)
        case .jubelt:
            FormPfad(pfad: { HausPfade.augenBogen($0, nachOben: true) }).stroke(HausFarbe.tinte, style: strich)
        }
    }
}
