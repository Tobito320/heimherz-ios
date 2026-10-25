import Foundation

/// Der Einmalcode zu einem Eintrag für die Anzeige: Code, Restsekunden, Länge der Periode.
struct TOTPZustand: Equatable {
    let code: String
    let rest: Int
    let periode: Int

    var anteil: Double { Double(rest) / Double(max(1, periode)) }

    /// Zur Lesbarkeit in der Mitte getrennt: `123 456`, `1234 5678`.
    var gruppiert: String {
        guard code.count >= 6, code.count % 2 == 0 else { return code }
        let mitte = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<mitte]) + " " + String(code[mitte...])
    }
}

enum TOTPAnzeige {
    /// nil ohne lesbares TOTP-Geheimnis.
    static func zustand(_ totp: String, datum: Date) -> TOTPZustand? {
        guard let e = TOTP.einstellung(aus: totp) else { return nil }
        let zeit = Int(datum.timeIntervalSince1970)
        return TOTPZustand(code: TOTP.code(e, zeit: zeit), rest: TOTP.restsekunden(e, zeit: zeit), periode: e.periode)
    }
}
