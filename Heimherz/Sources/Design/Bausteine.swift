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
