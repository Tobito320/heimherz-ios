import SwiftUI

/// Eine Zeile der Listen wie in der Passwörter-App von Apple: Symbol, Name fett, Benutzer grau. Rechts ein rotes Ausrufezeichen bei einem Sicherheitshinweis.
struct EintragZeile: View {
    let eintrag: Eintrag
    /// Ersetzt den Benutzer als zweite Zeile (Sicherheit: der Grund, Passkeys: das Konto).
    var untertitel: String?
    var hinweis = false

    private var zweite: String {
        if let untertitel { return untertitel }
        if eintrag.art == Eintrag.artNotiz { return "Notiz" }
        if !eintrag.benutzer.isEmpty { return eintrag.benutzer }
        return EintragSuche.hosts(von: eintrag).first ?? ""
    }

    var body: some View {
        HStack(spacing: Abstand.m) {
            SymbolKachel(eintrag: eintrag)
            VStack(alignment: .leading, spacing: 2) {
                Text(eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name)
                    .font(.headline)
                    .foregroundStyle(Color.tinte)
                    .lineLimit(1)
                if !zweite.isEmpty {
                    Text(zweite)
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Abstand.s)
            if hinweis {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.schlecht)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Abstand.xs)
        .frame(minHeight: Abstand.tippflaeche)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beschriftung)
    }

    private var beschriftung: String {
        var teile = [eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name, zweite]
        if eintrag.favorit { teile.append("Favorit") }
        if hinweis { teile.append("Sicherheitshinweis") }
        return teile.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Eine Zeile der Liste "Codes": Symbol, Name, Benutzer und der laufende Code groß mit Ring und Restzeit. Der Code ist bis zur Face ID verdeckt.
struct CodeZeile: View {
    let eintrag: Eintrag
    let freigegeben: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { zeit in
            let z = freigegeben ? TOTPAnzeige.zustand(eintrag.totp, datum: zeit.date) : nil
            HStack(spacing: Abstand.m) {
                SymbolKachel(eintrag: eintrag)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name)
                        .font(.headline)
                        .foregroundStyle(Color.tinte)
                        .lineLimit(1)
                    if !eintrag.benutzer.isEmpty {
                        Text(eintrag.benutzer)
                            .font(.subheadline)
                            .foregroundStyle(Color.tinte2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Abstand.s)
                if let z {
                    Text(z.gruppiert)
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.tinte)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    TOTPRing(anteil: z.anteil, rest: z.rest, groesse: 32)
                } else {
                    Text("••• •••")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.tinte3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Abstand.xs)
            .frame(minHeight: Abstand.tippflaeche)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(beschriftung(z))
            .accessibilityHint(z == nil ? "" : "Tippen kopiert den Code")
        }
    }

    private func beschriftung(_ z: TOTPZustand?) -> String {
        let kopf = [eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name, eintrag.benutzer].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let z else { return kopf + ", Code verdeckt" }
        return kopf + ", Code " + z.code.map { String($0) }.joined(separator: " ") + ", noch \(z.rest) Sekunden"
    }
}

/// Hinweiskarte oben in einer Liste (Sicherheit, Passkeys, Gelöscht): grauer Text auf der Kartenfläche.
struct HinweisKarte: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.gruen)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.tinte2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Abstand.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.karte, in: .heimherzKarte)
        .accessibilityElement(children: .combine)
    }
}

/// Die Farben der Kacheln der Startseite. Nur Schmuck (Titel und Zahl tragen die Aussage); weißes Symbol darauf wie bei Apple.
enum KachelFarbe {
    static func farbe(_ k: PasswoerterKategorie) -> Color {
        switch k {
        case .alle: return Color(red: 0.16, green: 0.55, blue: 0.27)
        case .favoriten: return Color(red: 0.93, green: 0.36, blue: 0.45)
        case .passkeys: return Color(red: 0.12, green: 0.62, blue: 0.68)
        case .codes: return Color(red: 0.90, green: 0.68, blue: 0.10)
        case .sicherheit: return Color(red: 0.88, green: 0.27, blue: 0.22)
        case .geloescht: return Color(red: 0.93, green: 0.55, blue: 0.14)
        }
    }
}
