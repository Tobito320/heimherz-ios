import CryptoKit
import Foundation

/// Ein lesbarer Passkey aus dem Tresor (SPEC 24): aus `passkeys` (Import aus Apple Passwörter, neu angelegte) oder `bitwardenFido2`.
/// Der private Schlüssel bleibt Text (PKCS#8, Base64url oder Base64) bis zum Signieren und wird nie angezeigt oder geloggt.
struct Passkey: Equatable, Sendable {
    let eintragId: String
    let rpId: String
    let userName: String
    let credentialID: Data
    let userHandle: Data
    let schluessel: String
}

/// Anmelden mit Passkey. `credentialID`: aus der Vorschlagsleiste genau dieser; sonst gelten `erlaubt` (leer = alle der rpId).
struct PasskeyAnfrage: Equatable, Sendable {
    let rpId: String
    let clientDataHash: Data
    var credentialID: Data? = nil
    var erlaubt: [Data] = []
}

/// Neuen Passkey anlegen. `ausgeschlossen`: Kennungen, die die Seite schon kennt (`excludedCredentials`).
struct PasskeyRegistrierung: Equatable, Sendable {
    let rpId: String
    let userName: String
    let userHandle: Data
    let clientDataHash: Data
    var ausgeschlossen: [Data] = []
}

/// Was der View Controller in `ASPasskeyAssertionCredential` oder `ASPasskeyRegistrationCredential` übersetzt.
struct PasskeyAntwort: Equatable, Sendable {
    let rpId: String
    let credentialID: Data
    let userHandle: Data
    let clientDataHash: Data
    let authenticatorData: Data
    /// Anmelden: ECDSA-Signatur (DER). Anlegen: leer.
    var signatur = Data()
    /// Anlegen: Attestation-Objekt (CBOR, "none"). Anmelden: leer.
    var attestation = Data()
}

enum Passkeys {
    /// User Present, User Verified, Backup Eligible, Backup State (synchronisierter Passkey wie bei Apple und Bitwarden).
    static let flagsAnmelden: UInt8 = 0x1D
    /// Dazu Attested Credential Data.
    static let flagsAnlegen: UInt8 = 0x5D

    // MARK: Lesen

    /// Alle lesbaren Passkeys lebendiger Logins.
    static func alle(in tresor: Tresor) -> [Passkey] {
        tresor.lebendige.filter { $0.art == Eintrag.artLogin }.flatMap { von($0) }
    }

    /// Passkeys eines Eintrags. Unlesbare (anderes Verfahren, kaputter Schlüssel) fallen weg, bleiben aber im Tresor stehen.
    static func von(_ e: Eintrag) -> [Passkey] {
        let eigene = (e.unbekannt["passkeys"]?.alsListe ?? []).compactMap { w -> Passkey? in
            guard case .objekt(let d) = w, let id = d["credentialId"]?.alsText.flatMap(daten) else { return nil }
            return passkey(d, eintrag: e, id: id, schluessel: d["key"]?.alsText)
        }
        let bitwarden = (e.unbekannt["bitwardenFido2"]?.alsListe ?? []).compactMap { w -> Passkey? in
            guard case .objekt(let d) = w, (d["keyAlgorithm"]?.alsText ?? "ECDSA") == "ECDSA", (d["keyCurve"]?.alsText ?? "P-256") == "P-256",
                  let id = d["credentialId"]?.alsText.flatMap(bitwardenKennung) else { return nil }
            return passkey(d, eintrag: e, id: id, schluessel: d["keyValue"]?.alsText)
        }
        return eigene + bitwarden
    }

    private static func passkey(_ d: [String: JSONWert], eintrag e: Eintrag, id: Data, schluessel: String?) -> Passkey? {
        guard let rp = d["rpId"]?.alsText?.lowercased(), !rp.isEmpty, !id.isEmpty, let schluessel, privaterSchluessel(schluessel) != nil else { return nil }
        let name = [d["userName"]?.alsText, d["userDisplayName"]?.alsText, e.benutzer].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        return Passkey(eintragId: e.id, rpId: rp, userName: name, credentialID: id, userHandle: d["userHandle"]?.alsText.flatMap(daten) ?? Data(),
                       schluessel: schluessel)
    }

    /// Bitwarden speichert die Kennung als UUID (16 Bytes) oder als `b64.<Base64url>`.
    static func bitwardenKennung(_ text: String) -> Data? {
        if text.hasPrefix("b64.") { return daten(String(text.dropFirst(4))) }
        if let u = UUID(uuidString: text) { return withUnsafeBytes(of: u.uuid) { Data($0) } }
        return daten(text)
    }

    /// Base64url (ohne Füllzeichen) oder Base64.
    static func daten(_ text: String) -> Data? {
        if let d = KoppelLink.base64url(text) { return d }
        var s = text
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// PKCS#8 (Apple, Bitwarden) oder SEC1, als DER in Base64url/Base64.
    static func privaterSchluessel(_ text: String) -> P256.Signing.PrivateKey? {
        guard let d = daten(text) else { return nil }
        return try? P256.Signing.PrivateKey(derRepresentation: d)
    }

    /// Kandidaten für eine Anmeldung: genau gleiche rpId (WebAuthn kennt keine Unterdomain-Regel), dann Kennung oder Erlaubt-Liste.
    static func kandidaten(_ a: PasskeyAnfrage, in tresor: Tresor) -> [Passkey] {
        let rp = a.rpId.lowercased()
        return alle(in: tresor).filter { p in
            guard p.rpId == rp else { return false }
            if let id = a.credentialID { return p.credentialID == id }
            return a.erlaubt.isEmpty || a.erlaubt.contains(p.credentialID)
        }
    }

    // MARK: Anmelden

    /// SHA-256(rpId) ‖ Flags ‖ signCount ‖ angehängte Daten.
    /// shortcut: signCount immer 0 wie bei synchronisierten Passkeys; Seiten, die einen steigenden Zähler verlangen, bräuchten einen gespeicherten Zähler.
    static func authenticatorData(rpId: String, flags: UInt8, angehaengt: Data = Data()) -> Data {
        Data(SHA256.hash(data: Data(rpId.utf8))) + Data([flags, 0, 0, 0, 0]) + angehaengt
    }

    /// Signiert authenticatorData ‖ clientDataHash mit dem Schlüssel des Passkeys.
    static func anmelden(_ p: Passkey, clientDataHash: Data) throws -> PasskeyAntwort {
        guard let schluessel = privaterSchluessel(p.schluessel) else { throw TresorFehler.inhaltUngueltig }
        let auth = authenticatorData(rpId: p.rpId, flags: flagsAnmelden)
        let signatur = try schluessel.signature(for: auth + clientDataHash).derRepresentation
        return PasskeyAntwort(rpId: p.rpId, credentialID: p.credentialID, userHandle: p.userHandle, clientDataHash: clientDataHash,
                              authenticatorData: auth, signatur: signatur)
    }

    // MARK: Anlegen

    /// Neues Schlüsselpaar, Attestation "none" und der Tresor-Wert (gleiches Format wie der Import, dazu `erstellt`).
    static func anlegen(_ r: PasskeyRegistrierung, jetzt: Date, schluessel: P256.Signing.PrivateKey = P256.Signing.PrivateKey(),
                        kennung: Data = zufall(16)) -> (antwort: PasskeyAntwort, wert: JSONWert) {
        let rp = r.rpId.lowercased()
        let xy = schluessel.publicKey.rawRepresentation
        let cose = CBOR.karte([(CBOR.zahl(1), CBOR.zahl(2)), (CBOR.zahl(3), CBOR.zahl(-7)), (CBOR.zahl(-1), CBOR.zahl(1)),
                               (CBOR.zahl(-2), CBOR.bytes(xy.prefix(32))), (CBOR.zahl(-3), CBOR.bytes(xy.suffix(32)))])
        let laenge = Data([UInt8(kennung.count >> 8), UInt8(kennung.count & 0xFF)])
        let auth = authenticatorData(rpId: rp, flags: flagsAnlegen, angehaengt: Data(count: 16) + laenge + kennung + cose)
        let attestation = CBOR.karte([(CBOR.text("fmt"), CBOR.text("none")), (CBOR.text("attStmt"), CBOR.karte([])),
                                      (CBOR.text("authData"), CBOR.bytes(auth))])
        let wert = JSONWert.objekt(["credentialId": .text(base64url(kennung)), "rpId": .text(rp), "userName": .text(r.userName),
                                    "userDisplayName": .text(r.userName), "userHandle": .text(base64url(r.userHandle)),
                                    "key": .text(base64url(schluessel.derRepresentation)), "erstellt": .text(Zeit.iso(jetzt))])
        let antwort = PasskeyAntwort(rpId: rp, credentialID: kennung, userHandle: r.userHandle, clientDataHash: r.clientDataHash,
                                     authenticatorData: auth, attestation: attestation)
        return (antwort, wert)
    }

    /// Login mit gleichem Benutzer und passendem Host (genauer Host zuerst) bekommt den Passkey dazu, sonst ein neuer Login.
    static func ablegen(_ wert: JSONWert, rpId: String, userName: String, in tresor: Tresor, jetzt: Date) -> SpeicherAktion {
        let stempel = Zeit.iso(jetzt)
        let treffer = tresor.lebendige.filter { e in
            e.art == Eintrag.artLogin && e.benutzer.caseInsensitiveCompare(userName) == .orderedSame
                && EintragSuche.hosts(von: e).contains { EintragSuche.passt(eintragHost: $0, anfrageHost: rpId) }
        }
        if var e = treffer.first(where: { EintragSuche.hosts(von: $0).contains(rpId) }) ?? treffer.first {
            e.unbekannt["passkeys"] = .liste((e.unbekannt["passkeys"]?.alsListe ?? []) + [wert])
            e.geaendert = stempel
            return .aktualisieren(e)
        }
        return .neu(Eintrag(name: rpId, benutzer: userName, urls: ["https://" + rpId], geaendert: stempel, unbekannt: ["passkeys": .liste([wert])]))
    }

    static func zufall(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &g) })
    }
}

/// Nur was WebAuthn hier braucht: Zahlen, Bytes, Text, Karten in der übergebenen (kanonischen) Reihenfolge.
enum CBOR {
    static func kopf(_ art: UInt8, _ n: UInt64) -> Data {
        let a = art << 5
        switch n {
        case 0..<24: return Data([a | UInt8(n)])
        case 24..<256: return Data([a | 24, UInt8(n)])
        case 256..<65_536: return Data([a | 25, UInt8(n >> 8), UInt8(n & 0xFF)])
        default: return Data([a | 26, UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
        }
    }

    static func zahl(_ i: Int) -> Data { i >= 0 ? kopf(0, UInt64(i)) : kopf(1, UInt64(-1 - i)) }
    static func bytes(_ d: Data) -> Data { kopf(2, UInt64(d.count)) + d }
    static func text(_ s: String) -> Data { kopf(3, UInt64(s.utf8.count)) + Data(s.utf8) }
    static func karte(_ paare: [(Data, Data)]) -> Data { paare.reduce(kopf(5, UInt64(paare.count))) { $0 + $1.0 + $1.1 } }
}
