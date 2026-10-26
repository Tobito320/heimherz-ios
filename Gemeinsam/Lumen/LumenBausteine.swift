// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI

/// Großer Betrag mit kleinen Cent: "18" groß, ",63 €" kleiner und auf derselben Grundlinie.
/// `text` ist der fertig formatierte Betrag ("18,63 €", Komma als Dezimaltrenner). Ohne Komma (zum Beispiel "•••") erscheint er einfach groß.
struct BetragGross: View {
    let text: String
    var groesse: CGFloat = 52
    var gewicht: Font.Weight = .heavy

    /// Zerlegt "1.234,56 €" in ("1.234", ",56 €"); ohne Komma ist der Rest leer. Rein, damit Tests ohne Oberfläche prüfen.
    nonisolated static func teile(_ text: String) -> (gross: String, klein: String) {
        guard let komma = text.lastIndex(of: ",") else { return (text, "") }
        return (String(text[..<komma]), String(text[komma...]))
    }

    var body: some View {
        let teile = Self.teile(text)
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(teile.gross).font(.system(size: groesse, weight: gewicht, design: .rounded))
            Text(teile.klein).font(.system(size: groesse * 0.5, weight: gewicht, design: .rounded))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}


/// Die graue Pille ("Konten", "Alle anzeigen"): Text auf `chip`, volle Rundung, mindestens 44 pt hoch.
struct PillenKnopf: View {
    let titel: String
    var symbol: String?
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: Abstand.xs) {
                if let symbol { Image(systemName: symbol) }
                Text(titel)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.tinte)
            .padding(.horizontal, Abstand.l)
            .frame(minHeight: Abstand.tippflaeche)
            .background(Color.chip, in: Capsule())
        }
        .buttonStyle(.federnd)
    }
}


/// Runder Schnellknopf mit Beschriftung darunter (wie "Einzahlen", "Details", "Mehr"): 56-pt-Kreis auf `chip`, Symbol in `tinte`.
struct RundeAktion: View {
    let titel: String
    let symbol: String
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            VStack(spacing: Abstand.s) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.tinte)
                    .frame(width: 56, height: 56)
                    .background(Color.chip, in: Circle())
                Text(titel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.tinte)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.federnd)
        .accessibilityElement(children: .combine)
    }
}


/// Kopfzeile einer Tagesgruppe: Datum links ("23. Oktober"), Tagessumme rechts in Grau. Darunter folgt eine Karte mit den Zeilen.
struct TagesKopf: View {
    let titel: String
    let summe: String

    var body: some View {
        HStack {
            Text(titel).font(.headline).foregroundStyle(Color.tinte)
            Spacer()
            Text(summe).font(.subheadline).foregroundStyle(Color.tinte2)
        }
        .padding(.horizontal, Abstand.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Graue Pille nur zum Anzeigen (kein Knopf): Text auf `chip`, volle Rundung.
struct InfoPille: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Abstand.xs) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.tinte)
        .padding(.horizontal, Abstand.l)
        .frame(minHeight: 36)
        .background(Color.chip, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Die eine große Karte je Bildschirm (Revolut-Stil): massiv, flach, ohne Schatten und ohne Verlauf.
struct HeroKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.m) { inhalt() }
            .padding(Abstand.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.karte, in: .lumenKarte)
    }
}

/// Flache Karte für Listen: massiv, ohne Schatten; Zeilen darin trennen Haarlinien.
struct ListenKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { inhalt() }
            .padding(Abstand.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.karte, in: .lumenKarte)
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
    func lumenEinstellungenListe() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .lumenHintergrund()
            .tint(Color.knopf)
    }

    /// Zeile einer solchen Liste.
    func lumenZeile() -> some View {
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
