import CryptoKit
import Foundation

/// Einstellungen eines Einmalcodes (RFC 6238): Geheimnis, Hash, Stellen, Periode.
struct TOTPEinstellung: Sendable, Equatable {
    enum Algorithmus: String, Sendable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }

    var geheim: Data
    var algorithmus: Algorithmus = .sha1
    var stellen = 6
    var periode = 30
}

/// TOTP nach RFC 6238 (SHA1, SHA256, SHA512; 6 bis 8 Stellen; Periode, Standard 30 s). Testvektoren: `fixtures/totp/rfc6238.json`.
enum TOTP {
    /// Liest eine `otpauth://totp/…`-URI oder ein rohes Base32-Geheimnis (Leerzeichen, Bindestriche, Kleinschreibung, Prozent-Kodierung erlaubt).
    /// nil bei `hotp`, unbekanntem Algorithmus, ungültigem Base32 oder Stellen außerhalb 6 bis 8.
    static func einstellung(aus text: String) -> TOTPEinstellung? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased().hasPrefix("otpauth://") else {
            return base32(t).map { TOTPEinstellung(geheim: $0) }
        }
        guard t.lowercased().hasPrefix("otpauth://totp"), let q = t.firstIndex(of: "?") else { return nil }
        var param: [String: String] = [:]
        for teil in t[t.index(after: q)...].split(separator: "&") {
            let kv = teil.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let schluessel = String(kv[0])
            let wert = kv.count > 1 ? String(kv[1]) : ""
            param[(schluessel.removingPercentEncoding ?? schluessel).lowercased()] = wert.removingPercentEncoding ?? wert
        }
        guard let geheimText = param["secret"], let geheim = base32(geheimText) else { return nil }
        guard let algorithmus = TOTPEinstellung.Algorithmus(rawValue: (param["algorithm"] ?? "SHA1").uppercased()),
              let stellen = Int(param["digits"] ?? "6"), (6...8).contains(stellen),
              let periode = Int(param["period"] ?? "30"), periode > 0 else { return nil }
        return TOTPEinstellung(geheim: geheim, algorithmus: algorithmus, stellen: stellen, periode: periode)
    }

    /// Base32 (RFC 4648), ohne Füllzeichen nötig. Leerzeichen, Bindestriche und `=` werden übersprungen. nil bei fremden Zeichen oder leerem Ergebnis.
    static func base32(_ text: String) -> Data? {
        var puffer = 0
        var bits = 0
        var aus = Data()
        for u in text.unicodeScalars {
            let wert: Int
            switch u.value {
            case 65...90: wert = Int(u.value) - 65
            case 97...122: wert = Int(u.value) - 97
            case 50...55: wert = Int(u.value) - 50 + 26
            case 9, 10, 13, 32, 45, 61: continue
            default: return nil
            }
            puffer = (puffer << 5) | wert
            bits += 5
            if bits >= 8 {
                bits -= 8
                aus.append(UInt8((puffer >> bits) & 0xFF))
                puffer &= (1 << bits) - 1
            }
        }
        return aus.isEmpty ? nil : aus
    }

    /// Der Code zur Unix-Zeit `zeit` (Sekunden), mit führenden Nullen.
    static func code(_ e: TOTPEinstellung, zeit: Int) -> String {
        let zaehler = UInt64(max(0, zeit) / max(1, e.periode))
        let nachricht = Data((0..<8).map { UInt8((zaehler >> UInt64(56 - 8 * $0)) & 0xFF) })
        let schluessel = SymmetricKey(data: e.geheim)
        let mac: [UInt8]
        switch e.algorithmus {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: nachricht, using: schluessel))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: nachricht, using: schluessel))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: nachricht, using: schluessel))
        }
        let o = Int(mac[mac.count - 1] & 0x0F)
        var bin = UInt32(mac[o] & 0x7F) << 24
        bin |= UInt32(mac[o + 1]) << 16
        bin |= UInt32(mac[o + 2]) << 8
        bin |= UInt32(mac[o + 3])
        var modul: UInt32 = 1
        for _ in 0..<e.stellen { modul *= 10 }
        let ziffern = String(bin % modul)
        return String(repeating: "0", count: max(0, e.stellen - ziffern.count)) + ziffern
    }

    static func code(_ e: TOTPEinstellung, datum: Date = Date()) -> String {
        code(e, zeit: Int(datum.timeIntervalSince1970))
    }

    /// Sekunden bis der Code wechselt (für den Ring in der Anzeige).
    static func restsekunden(_ e: TOTPEinstellung, zeit: Int) -> Int {
        let p = max(1, e.periode)
        return p - (max(0, zeit) % p)
    }
}
