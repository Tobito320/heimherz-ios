import SwiftUI

enum HausherzStimmung: String, CaseIterable, Sendable {
    case wach, schlaeft, jubelt, sorry

    /// Das Symbol im Kreis (Revolut-Stil: grauer Kreis, ein klares Zeichen).
    var symbol: String {
        switch self {
        case .wach: return "house.fill"
        case .schlaeft: return "lock.fill"
        case .jubelt: return "checkmark"
        case .sorry: return "exclamationmark"
        }
    }

    /// Für VoiceOver, wenn das Maskottchen eine Aussage trägt.
    var beschreibung: String {
        switch self {
        case .wach: return "Cloud ist bereit"
        case .schlaeft: return "Cloud ist gesperrt"
        case .jubelt: return "Cloud meldet Erfolg"
        case .sorry: return "Cloud meldet ein Problem"
        }
    }
}

/// Das Cloud-Zeichen für leere Zustände, Sperre und Fehler: grauer Kreis mit einem Symbol (ersetzt das frühere Maskottchen).
/// Größen: 40 (Liste), 96 (Leerzustand), 160 (Hero). Dekoration ist für VoiceOver versteckt, außer `beschriftet` ist wahr.
struct HausherzView: View {
    var stimmung: HausherzStimmung = .wach
    var groesse: CGFloat = 96
    var beschriftet = false

    var body: some View {
        Image(systemName: stimmung.symbol)
            .font(.system(size: groesse * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(stimmung == .sorry ? Color.schlecht : Color.tinte)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: groesse, height: groesse)
            .background(Color.chip, in: Circle())
            .accessibilityHidden(!beschriftet)
            .accessibilityLabel(beschriftet ? stimmung.beschreibung : "")
    }
}
