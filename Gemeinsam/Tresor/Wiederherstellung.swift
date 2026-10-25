import CryptoKit
import Foundation

/// Der mit dem Wiederherstellungscode umwickelte Tresorschlüssel (W-036, SPEC 25): `{"v":1,"salt":b64(16),"nonce":b64(12),"daten":b64(32+16)}`.
/// Der Code (20 Zufallsbytes, Base32 in Vierergruppen) wird nur am Handy erzeugt und einmal gezeigt; der PC sieht nur dieses Blatt.
/// Schlüssel: HKDF-SHA256(Code, salt, "heimherz-wiederherstellung-v1") -> 32 Byte, AES-256-GCM, AAD "heimherz-schluessel-v1". Gleiches Format wie `lib/sicherung.ts`.
struct WiederherstellungsBlatt: Codable, Sendable, Equatable {
    var v: Int
    var salt: String
    var nonce: String
    var daten: String
}

enum WiederherstellungFehler: Error, Equatable {
    case blattUngueltig
    case codeUngueltig
    case codePasstNicht
}

enum Wiederherstellung {
    static let aad = Data("heimherz-schluessel-v1".utf8)
    static let info = Data("heimherz-wiederherstellung-v1".utf8)
    static let codeBytes = 20
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// 20 Zufallsbytes aus dem Zufallsgenerator des Systems (kryptografisch sicher).
    static func neuerCode() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<codeBytes).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    /// `ABCD-EFGH-...` (32 Zeichen in 8 Gruppen).
    static func codeText(_ code: Data) -> String {
        var bits = 0, wert = 0
        var zeichen: [Character] = []
        for b in code {
            wert = (wert << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                zeichen.append(alphabet[(wert >> (bits - 5)) & 31])
                bits -= 5
            }
            wert &= (1 << bits) - 1
        }
        return stride(from: 0, to: zeichen.count, by: 4).map { String(zeichen[$0..<min($0 + 4, zeichen.count)]) }.joined(separator: "-")
    }

    /// Groß- oder Kleinschreibung, Leerzeichen und Bindestriche egal; sonst genau 32 Zeichen A bis Z und 2 bis 7. nil bei allem anderen.
    static func codeDaten(_ text: String) -> Data? {
        let roh = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard roh.count == 32 else { return nil }
        var bits = 0, wert = 0
        var aus: [UInt8] = []
        for c in roh {
            guard let i = alphabet.firstIndex(of: c) else { return nil }
            wert = (wert << 5) | i
            bits += 5
            if bits >= 8 {
                aus.append(UInt8((wert >> (bits - 8)) & 255))
                bits -= 8
                wert &= (1 << bits) - 1
            }
        }
        return Data(aus)
    }

    private static func umwickelSchluessel(code: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: code), salt: salt, info: info, outputByteCount: 32)
    }

    /// Umwickelt K. Ohne Angabe nimmt es frisches Salt und frische Nonce; feste Werte nur für den Testvektor.
    static func umwickle(schluessel k: SymmetricKey, code: Data, salt: Data? = nil, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> WiederherstellungsBlatt {
        guard code.count == codeBytes else { throw WiederherstellungFehler.codeUngueltig }
        var generator = SystemRandomNumberGenerator()
        let s = salt ?? Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let klar = k.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(klar, using: umwickelSchluessel(code: code, salt: s), nonce: nonce, authenticating: aad)
        return WiederherstellungsBlatt(v: 1, salt: s.base64EncodedString(), nonce: Data(nonce).base64EncodedString(), daten: (box.ciphertext + box.tag).base64EncodedString())
    }

    /// Holt K aus dem Blatt. Falscher Code oder verändertes Blatt ergibt `codePasstNicht`.
    static func entwickle(_ blatt: WiederherstellungsBlatt, code: Data) throws -> SymmetricKey {
        guard blatt.v == 1, code.count == codeBytes, let salt = Data(base64Encoded: blatt.salt), salt.count == 16,
              let n = Data(base64Encoded: blatt.nonce), n.count == 12, let d = Data(base64Encoded: blatt.daten), d.count == 48 else {
            throw WiederherstellungFehler.blattUngueltig
        }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: n), ciphertext: d.dropLast(16), tag: d.suffix(16))
            return SymmetricKey(data: try AES.GCM.open(box, using: umwickelSchluessel(code: code, salt: salt), authenticating: aad))
        } catch {
            throw WiederherstellungFehler.codePasstNicht
        }
    }
}
