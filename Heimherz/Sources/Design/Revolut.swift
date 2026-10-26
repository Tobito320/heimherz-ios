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
