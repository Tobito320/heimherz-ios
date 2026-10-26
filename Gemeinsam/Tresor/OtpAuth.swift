import Foundation

/// Ein Code zum Einrichten, gelesen aus einem `otpauth://totp/…`-Link (Key URI Format): Anbieter, Konto und die TOTP-Einstellung.
struct OtpKonto: Equatable, Sendable {
    var issuer: String
    var konto: String
    var einstellung: TOTPEinstellung

    /// Was im Tresor im Feld `totp` steht: der Link in fester Form, mit Hash, Stellen und Periode (ein rohes Geheimnis verlöre sie).
    var uri: String { OtpAuth.uri(self) }
    /// Der Name für die Anzeige und für einen neuen Eintrag.
    var anzeigeName: String { issuer.isEmpty ? konto : issuer }
}

enum OtpFehler: Error, Equatable, LocalizedError {
    case keinLink, zuLang, hotp, migration, unbekannterTyp
    case geheimnisFehlt, geheimnisUngueltig, algorithmus, stellen, periode

    /// Nie mit dem Geheimnis im Text: die Meldung landet in Warnfenstern und Logs.
    var nutzerText: String {
        switch self {
        case .keinLink: return "Das ist kein Link zum Einrichten eines Codes (otpauth://)."
        case .zuLang: return "Der Link ist zu lang für einen Code."
        case .hotp: return "Dieser Code zählt hoch (HOTP). Lumen kann nur Codes, die sich nach der Zeit ändern (TOTP)."
        case .migration: return "Das ist ein Export aus Google Authenticator. Den kann Lumen noch nicht lesen. Richte den Code bei der Seite noch einmal ein."
        case .unbekannterTyp: return "Die Art des Codes im Link ist unbekannt."
        case .geheimnisFehlt: return "Im Link fehlt das Geheimnis (secret)."
        case .geheimnisUngueltig: return "Das Geheimnis im Link ist ungültig. Erlaubt sind die Buchstaben A bis Z und die Ziffern 2 bis 7."
        case .algorithmus: return "Das Verfahren im Link wird nicht unterstützt. Erlaubt sind SHA1, SHA256 und SHA512."
        case .stellen: return "Die Stellenzahl im Link wird nicht unterstützt. Erlaubt sind 6 oder 8."
        case .periode: return "Die Gültigkeitsdauer im Link ist ungültig."
        }
    }

    var errorDescription: String? { nutzerText }
}

/// Liest und schreibt `otpauth://totp/Anbieter:Konto?secret=…&issuer=…&algorithm=…&digits=…&period=…` streng.
/// `TOTP.einstellung(aus:)` bleibt die nachsichtige Fassung für gespeicherte Werte und AutoFill; hier wird geprüft, was neu hereinkommt.
enum OtpAuth {
    /// Ein echter Link ist kurz; alles darüber ist kein Code (und kein Grund, einen langen Text zu zerlegen).
    static let maxLaenge = 2048

    /// Liest genau einen Code. Wirft einen `OtpFehler` mit lesbarem Text, nie einen mit dem Geheimnis darin.
    static func lese(_ text: String) throws -> OtpKonto {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= maxLaenge else { throw OtpFehler.zuLang }
        let lower = t.lowercased()
        if lower.hasPrefix("otpauth-migration:") { throw OtpFehler.migration }
        guard lower.hasPrefix("otpauth:") else { throw OtpFehler.keinLink }
        // Manche Seiten lassen Leerzeichen im Namen ungekodiert; URLComponents lehnt sie ab.
        guard let teile = URLComponents(string: t.replacingOccurrences(of: " ", with: "%20")), teile.scheme?.lowercased() == "otpauth" else {
            throw OtpFehler.keinLink
        }
        switch teile.host?.lowercased() ?? "" {
        case "totp": break
        case "hotp": throw OtpFehler.hotp
        default: throw OtpFehler.unbekannterTyp
        }
        var param: [String: String] = [:]
        for e in teile.queryItems ?? [] where param[e.name.lowercased()] == nil { param[e.name.lowercased()] = e.value ?? "" }

        guard let geheimText = param["secret"], !geheimText.isEmpty else { throw OtpFehler.geheimnisFehlt }
        guard let geheim = TOTP.base32(geheimText) else { throw OtpFehler.geheimnisUngueltig }
        guard let algorithmus = TOTPEinstellung.Algorithmus(rawValue: (param["algorithm"] ?? "SHA1").uppercased()) else { throw OtpFehler.algorithmus }
        guard let stellen = Int(param["digits"] ?? "6"), stellen == 6 || stellen == 8 else { throw OtpFehler.stellen }
        guard let periode = Int(param["period"] ?? "30"), (1...3600).contains(periode) else { throw OtpFehler.periode }

        // Label: "Anbieter:Konto" oder nur "Konto". Der Parameter `issuer` gewinnt, wenn beide da sind.
        let label = String(teile.path.drop(while: { $0 == "/" })).trimmingCharacters(in: .whitespaces)
        var labelIssuer = ""
        var konto = label
        if let doppel = label.firstIndex(of: ":") {
            labelIssuer = String(label[..<doppel]).trimmingCharacters(in: .whitespaces)
            konto = String(label[label.index(after: doppel)...]).trimmingCharacters(in: .whitespaces)
        }
        let issuer = (param["issuer"] ?? "").trimmingCharacters(in: .whitespaces)
        return OtpKonto(issuer: issuer.isEmpty ? labelIssuer : issuer, konto: konto,
                        einstellung: TOTPEinstellung(geheim: geheim, algorithmus: algorithmus, stellen: stellen, periode: periode))
    }

    /// Der Link in fester Form (Base32 ohne Füllzeichen, Namen prozentkodiert); `lese` gibt daraus wieder denselben Code.
    static func uri(_ k: OtpKonto) -> String {
        let e = k.einstellung
        let name = k.issuer.isEmpty ? kodiere(k.konto) : "\(kodiere(k.issuer)):\(kodiere(k.konto))"
        var s = "otpauth://totp/\(name)?secret=\(base32(e.geheim))"
        if !k.issuer.isEmpty { s += "&issuer=\(kodiere(k.issuer))" }
        return s + "&algorithm=\(e.algorithmus.rawValue)&digits=\(e.stellen)&period=\(e.periode)"
    }

    private static let unreserviert = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func kodiere(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserviert) ?? ""
    }

    /// Base32 nach RFC 4648, ohne Füllzeichen (Gegenstück zu `TOTP.base32`).
    static func base32(_ daten: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var aus = ""
        var puffer = 0
        var bits = 0
        for byte in daten {
            puffer = (puffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                aus.append(alphabet[(puffer >> bits) & 31])
            }
            puffer &= (1 << bits) - 1
        }
        if bits > 0 { aus.append(alphabet[(puffer << (5 - bits)) & 31]) }
        return aus
    }
}
