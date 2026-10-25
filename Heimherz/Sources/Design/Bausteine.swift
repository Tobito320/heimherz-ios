import SwiftUI

// Wiederverwendbare Bausteine. Module (Passwörter, Fotos, Dateien, AutoFill) benutzen sie, bauen sie nicht nach.

/// Die eine mutige Karte je Bildschirm: Grün-Verlauf, der einzige weiche Schatten. Bei erhöhtem Kontrast flach.
struct HeroKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    @Environment(\.colorSchemeContrast) private var kontrast
    @Environment(\.colorScheme) private var schema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.m) { inhalt() }
            .padding(Abstand.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hintergrund, in: .heimherzKarte)
            .shadow(color: schema == .dark ? Color.black.opacity(0.35) : Color.knopf.opacity(0.14), radius: 16, y: 8)
    }

    private var hintergrund: AnyShapeStyle {
        if kontrast == .increased { return AnyShapeStyle(Color.grundWarm) }
        return AnyShapeStyle(LinearGradient(colors: [.heroEins, .heroZwei, .heroDrei], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Flache Karte für Listen: massiv, ohne Schatten; Zeilen darin trennen Haarlinien.
struct ListenKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { inhalt() }
            .padding(Abstand.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.karte, in: .heimherzKarte)
    }
}

/// Zustand als Symbol plus Text auf getönter Fläche (Farbe trägt nie allein die Aussage).
struct StatusChip: View {
    enum Ton { case ok, warn, schlecht, neutral }

    let text: String
    let symbol: String
    var ton: Ton = .neutral

    private var farbe: Color {
        switch ton {
        case .ok: return .ok
        case .warn: return .warn
        case .schlecht: return .schlecht
        case .neutral: return .tinte2
        }
    }

    private var grund: Color {
        switch ton {
        case .ok: return .okGrund
        case .warn: return .warnGrund
        case .schlecht: return .schlechtGrund
        case .neutral: return .chip
        }
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(farbe)
            .padding(.horizontal, Abstand.s)
            .padding(.vertical, Abstand.xs)
            .background(grund, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// Leerer Zustand: Hausherz, ein Satz, optional eine Handlung. Lädt zur nächsten Handlung ein statt "Keine Daten".
struct LeerZustand: View {
    var stimmung: HausherzStimmung = .wach
    let titel: String
    let text: String
    var aktionTitel: String?
    var aktion: (() -> Void)?

    var body: some View {
        VStack(spacing: Abstand.m) {
            HausherzView(stimmung: stimmung, groesse: 112)
            Text(titel)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.tinte2)
                .multilineTextAlignment(.center)
            if let aktionTitel, let aktion {
                Button(aktionTitel, action: aktion)
                    .buttonStyle(.glassProminent)
                    .tint(Color.knopf)
                    .foregroundStyle(Color.aufKnopf)
                    .controlSize(.large)
                    .padding(.top, Abstand.xs)
            }
        }
        .padding(Abstand.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Fehlerkarte: trauriges Hausherz, ein verständlicher Satz, optional "Nochmal".
struct FehlerKarte: View {
    let text: String
    var wiederholen: (() -> Void)?

    var body: some View {
        ListenKarte {
            HStack(alignment: .top, spacing: Abstand.m) {
                HausherzView(stimmung: .sorry, groesse: 56)
                VStack(alignment: .leading, spacing: Abstand.s) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Color.tinte)
                        .fixedSize(horizontal: false, vertical: true)
                    if let wiederholen {
                        Button("Nochmal", action: wiederholen)
                            .buttonStyle(.glassProminent)
                            .tint(Color.knopf)
                            .foregroundStyle(Color.aufKnopf)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Zeile "Name ... Wert" in einer Karte.
struct WertZeile: View {
    let name: String
    let wert: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(Color.tinte2)
            Spacer(minLength: Abstand.m)
            Text(wert).foregroundStyle(Color.tinte).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Abstand.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Farbe einer Symbolkachel (wie in den iOS-Einstellungen). Feste, kräftige Töne mit weißem Symbol, in Hell und Dunkel gleich lesbar
/// (dieselben Werte wie die Kacheln der Passwörter-Startseite).
enum KachelTon {
    case gruen, tuerkis, gelb, rot, orange, rosa, grau

    var farbe: Color {
        switch self {
        case .gruen: return Color(red: 0.16, green: 0.55, blue: 0.27)
        case .tuerkis: return Color(red: 0.12, green: 0.62, blue: 0.68)
        case .gelb: return Color(red: 0.90, green: 0.68, blue: 0.10)
        case .rot: return Color(red: 0.88, green: 0.27, blue: 0.22)
        case .orange: return Color(red: 0.93, green: 0.55, blue: 0.14)
        case .rosa: return Color(red: 0.93, green: 0.36, blue: 0.45)
        case .grau: return Color(red: 0.45, green: 0.50, blue: 0.45)
        }
    }
}

/// Die kleine farbige Kachel vor einer Einstellungszeile.
struct EinstellungsKachel: View {
    let symbol: String
    var ton: KachelTon = .gruen

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 30, height: 30)
            .background(ton.farbe, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Titel mit Symbolkachel: der Inhalt jeder Einstellungszeile.
struct KachelTitel: View {
    let titel: String
    let symbol: String
    var ton: KachelTon = .gruen

    var body: some View {
        HStack(spacing: Abstand.m) {
            EinstellungsKachel(symbol: symbol, ton: ton)
            Text(titel).foregroundStyle(Color.tinte)
        }
    }
}

extension View {
    /// Gruppierte Liste im Stil der iOS-Einstellungen mit dem Heim-Hintergrund und weißen Karten (Hell) beziehungsweise dunkelgrünen (Dunkel).
    func heimherzEinstellungenListe() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .heimherzHintergrund()
            .tint(Color.knopf)
    }

    /// Zeile einer solchen Liste.
    func heimherzZeile() -> some View {
        self
            .listRowBackground(Color.karte)
            .listRowSeparatorTint(Color.haar)
    }
}

/// Kopf- und Fußzeile einer Einstellungsgruppe in den Heim-Farben.
struct GruppenText: View {
    let text: String
    var fuss = false

    var body: some View {
        Text(text)
            .font(fuss ? .footnote : .footnote.weight(.semibold))
            .foregroundStyle(Color.tinte2)
            .textCase(fuss ? nil : .uppercase)
            .fixedSize(horizontal: false, vertical: true)
    }
}
