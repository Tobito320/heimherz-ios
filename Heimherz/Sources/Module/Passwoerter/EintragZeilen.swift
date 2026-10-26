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
/// In den letzten Sekunden eines Codes steht der nächste klein darunter; Tippen kopiert dann gleich den nächsten (`PasswoerterLogik.codeZumKopieren`).
struct CodeZeile: View {
    let eintrag: Eintrag
    let freigegeben: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { zeit in
            let datum = Self.anzeigeZeit(zeit.date)
            let z = freigegeben ? TOTPAnzeige.zustand(eintrag.totp, datum: datum) : nil
            let naechster = z == nil ? nil : PasswoerterLogik.naechsterCode(eintrag.totp, datum: datum)
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
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(z.gruppiert)
                            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.tinte)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        // Die Zeile bleibt gleich hoch, auch wenn der nächste Code gerade nicht dasteht.
                        Text(naechster.map { "Danach " + TOTPZustand(code: $0, rest: 0, periode: z.periode).gruppiert } ?? " ")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.tinte2)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
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
            .accessibilityLabel(beschriftung(z, naechster))
            .accessibilityHint(z == nil ? "" : (naechster == nil ? "Tippen kopiert den Code" : "Tippen kopiert den nächsten Code"))
        }
    }

    /// Nur Debug (`-heimherzCodeVorschau YES`, Screenshot in CI): friert die Anzeige 3 Sekunden vor Ende der 30-Sekunden-Periode ein,
    /// damit der Screenshot den nächsten Code zeigt.
    private static func anzeigeZeit(_ datum: Date) -> Date {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "heimherzCodeVorschau") {
            let t = datum.timeIntervalSince1970
            return Date(timeIntervalSince1970: t - t.truncatingRemainder(dividingBy: 30) + 27)
        }
        #endif
        return datum
    }

    private func beschriftung(_ z: TOTPZustand?, _ naechster: String?) -> String {
        let kopf = [eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name, eintrag.benutzer].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let z else { return kopf + ", Code verdeckt" }
        var text = kopf + ", Code " + z.code.map { String($0) }.joined(separator: " ") + ", noch \(z.rest) Sekunden"
        if let naechster { text += ", danach " + naechster.map { String($0) }.joined(separator: " ") }
        return text
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
                    .foregroundStyle(Color.akzent)
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
