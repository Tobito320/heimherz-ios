import CryptoKit
import Foundation

/// Der verschlüsselte Tresor (SPEC 5): `{"v":1,"rev":N,"nonce":"b64(12)","daten":"b64(ciphertext||tag16)"}`.
/// AES-256-GCM mit dem Tresorschlüssel K, zusätzliche Daten (AAD) `heimherz-tresor-v1`. `rev` vergibt der Server und steht nur außen.
/// Nur dieser Umschlag liegt auf Platte (App-Group-Ordner) und im Netz, nie der Klartext.
struct Umschlag: Codable, Sendable, Equatable {
    static let aad = Data("heimherz-tresor-v1".utf8)

    var v: Int
    var rev: Int
    var nonce: String
    var daten: String

    /// Nur die Form (wie `istUmschlag` in TS), nie der Inhalt.
    var istGueltigeForm: Bool {
        v == 1 && rev >= 0 && Data(base64Encoded: nonce)?.count == 12 && (Data(base64Encoded: daten)?.count ?? 0) >= 16
    }

    /// Verschließt den Tresor. Ohne Angabe nimmt `AES.GCM.Nonce()` eine frische Zufalls-Nonce; feste Nonce nur für Tests (byte-gleich zur TS-Fixture).
    static func verschliesse(_ tresor: Tresor, schluessel: SymmetricKey, rev: Int = 0, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> Umschlag {
        let box = try AES.GCM.seal(tresor.jsonDaten, using: schluessel, nonce: nonce, authenticating: aad)
        return Umschlag(v: 1, rev: rev, nonce: Data(nonce).base64EncodedString(), daten: (box.ciphertext + box.tag).base64EncodedString())
    }

    /// Öffnet den Umschlag. Falscher Schlüssel oder veränderte Daten ergeben `entschluesselungFehlgeschlagen`.
    func oeffne(schluessel: SymmetricKey) throws -> Tresor {
        guard istGueltigeForm, let n = Data(base64Encoded: nonce), let d = Data(base64Encoded: daten) else {
            throw TresorFehler.umschlagUngueltig
        }
        let klar: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: n), ciphertext: d.dropLast(16), tag: d.suffix(16))
            klar = try AES.GCM.open(box, using: schluessel, authenticating: Umschlag.aad)
        } catch {
            throw TresorFehler.entschluesselungFehlgeschlagen
        }
        return try Tresor.aus(daten: klar)
    }
}

/// Der Tresorschlüssel K: genau 32 Byte.
enum TresorSchluessel {
    static func aus(_ roh: Data) throws -> SymmetricKey {
        guard roh.count == 32 else { throw TresorFehler.schluesselLaenge }
        return SymmetricKey(data: roh)
    }
}
