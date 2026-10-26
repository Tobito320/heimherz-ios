import SwiftUI

// Wiederverwendbare Bausteine. Module (Passwörter, Fotos, Dateien, AutoFill) benutzen sie, bauen sie nicht nach.

/// Die eine große Karte je Bildschirm (Revolut-Stil): massiv, flach, ohne Schatten und ohne Verlauf.
struct HeroKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.m) { inhalt() }
            .padding(Abstand.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.karte, in: .heimherzKarte)
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

/// Leerer Zustand: Cloud-Zeichen, ein Satz, optional eine Handlung. Lädt zur nächsten Handlung ein statt "Keine Daten".
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

/// Fehlerkarte: Fehlerzeichen, ein verständlicher Satz, optional "Nochmal".
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

/// Ton einer Symbolkachel. Im Revolut-Stil sind alle Kacheln grau; der Ton bleibt nur, damit Aufrufer nicht ändern müssen.
enum KachelTon {
    case gruen, tuerkis, gelb, rot, orange, rosa, grau
}

/// Der kleine graue Kreis vor einer Einstellungszeile.
struct EinstellungsKachel: View {
    let symbol: String
    var ton: KachelTon = .gruen

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.tinte)
            .frame(width: 32, height: 32)
            .background(Color.chip, in: Circle())
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
    /// Gruppierte Liste im Stil der iOS-Einstellungen mit dem Heim-Hintergrund und flachen Karten.
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
