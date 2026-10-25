import AuthenticationServices
import CryptoKit
import XCTest
@testable import Heimherz

/// Passkeys (SPEC 24). Testvektoren unabhängig mit Python `cryptography` berechnet: privater Schlüssel = Bytes 0x01…0x20 (erfundener Testwert),
/// rpId `webauthn.io`, Kennung 0xA0…0xAF.
final class PasskeyTests: XCTestCase {
    private static func hex(_ s: String) -> Data {
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    private static let x = hex("515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f")
    private static let y = hex("4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354")
    /// Derselbe Testschlüssel als PKCS#8 (Base64url wie Apple-Import, Base64 wie manche Bitwarden-Exporte) und als SEC1.
    private static let pkcs8Url = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyChRANCAARRXD1uueOWuQTT_sp_VP3NDMHpl783XcpRWtCmw7QDX0U2vjpQ8xj7-aVHWQKiIVAr7w1X4IxTsswKVvF9n5NU"
    private static let pkcs8 = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyChRANCAARRXD1uueOWuQTT/sp/VP3NDMHpl783XcpRWtCmw7QDX0U2vjpQ8xj7+aVHWQKiIVAr7w1X4IxTsswKVvF9n5NU"
    private static let sec1Url = "MHcCAQEEIAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8goAoGCCqGSM49AwEHoUQDQgAEUVw9brnjlrkE0_7Kf1T9zQzB6Ze_N13KUVrQpsO0A19FNr46UPMY-_mlR1kCoiFQK-8NV-CMU7LMClbxfZ-TVA"
    private static let kennung = Data((0xA0...0xAF).map { UInt8($0) })
    private static let anmeldeDaten = hex("74a6ea9213c99c2f74b22492b320cf40262a94c1a950a0397f29250b60841ef01d00000000")
    private static let attestation = hex("a363666d74646e6f6e656761747453746d74a0686175746844617461589474a6ea9213c99c2f74b22492b320cf40262a94c1a950a0397f29250b60841ef05d00000000000000000000000000000000000000000010a0a1a2a3a4a5a6a7a8a9aaabacadaeafa5010203262001215820515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f2258204536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354")
    private static let hash = Data(repeating: 0x42, count: 32)

    private static func eigener(rp: String = "webauthn.io", id: Data = kennung, key: String = pkcs8Url, user: String = "mia") -> JSONWert {
        .objekt(["credentialId": .text(Passkeys.base64url(id)), "rpId": .text(rp), "userName": .text(user), "userDisplayName": .text("Mia"),
                 "userHandle": .text("AQI"), "key": .text(key)])
    }

    // MARK: Lesen

    func testSchluesselformateUndOeffentlicherSchluessel() throws {
        for text in [Self.pkcs8Url, Self.pkcs8, Self.sec1Url] {
            let k = try XCTUnwrap(Passkeys.privaterSchluessel(text), text.prefix(8) + "…")
            XCTAssertEqual(k.publicKey.rawRepresentation, Self.x + Self.y)
        }
        XCTAssertNil(Passkeys.privaterSchluessel("kaputt"))
        XCTAssertNil(Passkeys.privaterSchluessel(""))
    }

    func testBitwardenKennung() {
        XCTAssertEqual(Passkeys.bitwardenKennung("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"), Self.hex("0f1e2d3c4b5a69788796a5b4c3d2e1f0"))
        XCTAssertEqual(Passkeys.bitwardenKennung("b64.oKGio6SlpqeoqaqrrK2urw"), Self.kennung)
        XCTAssertEqual(Passkeys.daten("oKGio6SlpqeoqaqrrK2urw=="), Self.kennung, "Base64 mit Füllzeichen")
    }

    func testBeideFelderUnlesbaresFaelltWeg() {
        let bitwarden = JSONWert.objekt(["credentialId": .text("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"), "keyType": .text("public-key"),
                                         "keyAlgorithm": .text("ECDSA"), "keyCurve": .text("P-256"), "keyValue": .text(Self.pkcs8Url),
                                         "rpId": .text("GitHub.com"), "userHandle": .text("AQI"), "counter": .text("0")])
        let fremdesVerfahren = JSONWert.objekt(["credentialId": .text("b64.AQ"), "keyAlgorithm": .text("EdDSA"), "keyValue": .text(Self.pkcs8Url), "rpId": .text("x.de")])
        let kaputt = Self.eigener(key: "kaputt")
        let e = Eintrag(id: "e", name: "GitHub", benutzer: "tobito", unbekannt: ["passkeys": .liste([Self.eigener(), kaputt]),
                                                                                 "bitwardenFido2": .liste([bitwarden, fremdesVerfahren])])
        let p = Passkeys.von(e)
        XCTAssertEqual(p.map(\.rpId), ["webauthn.io", "github.com"], "rpId kleingeschrieben")
        XCTAssertEqual(p.map(\.userName), ["mia", "tobito"], "ohne userName der Benutzer des Eintrags")
        XCTAssertEqual(p[0].userHandle, Data([1, 2]))
        XCTAssertEqual(p[1].credentialID.count, 16)
        let grab = Eintrag(id: "g", name: "", geloescht: true, unbekannt: ["passkeys": .liste([Self.eigener()])])
        XCTAssertEqual(Passkeys.alle(in: Tresor(eintraege: [e, grab])).count, 2, "Grabstein zählt nicht")
    }

    func testKandidatenNurGleicheRpId() {
        let t = Tresor(eintraege: [
            Eintrag(id: "a", name: "A", unbekannt: ["passkeys": .liste([Self.eigener(), Self.eigener(id: Data([9]), user: "tom")])]),
            Eintrag(id: "b", name: "B", unbekannt: ["passkeys": .liste([Self.eigener(rp: "login.webauthn.io", id: Data([7]))])])
        ])
        XCTAssertEqual(Passkeys.kandidaten(PasskeyAnfrage(rpId: "WebAuthn.io", clientDataHash: Self.hash), in: t).map(\.userName), ["mia", "tom"])
        XCTAssertEqual(Passkeys.kandidaten(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: Self.hash, credentialID: Data([9])), in: t).map(\.userName), ["tom"])
        XCTAssertEqual(Passkeys.kandidaten(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: Self.hash, erlaubt: [Self.kennung]), in: t).map(\.userName), ["mia"])
        XCTAssertEqual(Passkeys.kandidaten(PasskeyAnfrage(rpId: "evilwebauthn.io", clientDataHash: Self.hash), in: t), [])
    }

    func testIdentitaetenOhneSchluessel() throws {
        let t = Tresor(eintraege: [Eintrag(id: "a", name: "A", benutzer: "mia", passwort: "pw", urls: ["https://webauthn.io"],
                                           unbekannt: ["passkeys": .liste([Self.eigener()])])])
        let ids = AutoFillIdentitaeten.baue(aus: t)
        XCTAssertEqual(ids.count, 2)
        let p = try XCTUnwrap(ids.compactMap { $0 as? ASPasskeyCredentialIdentity }.first)
        XCTAssertEqual(p.relyingPartyIdentifier, "webauthn.io")
        XCTAssertEqual(p.credentialID, Self.kennung)
        XCTAssertEqual(p.userName, "mia")
        XCTAssertEqual(p.userHandle, Data([1, 2]))
        XCTAssertEqual(p.recordIdentifier, "a")
    }

    // MARK: Anmelden und Anlegen

    func testAnmeldenTestvektorUndSignatur() throws {
        let p = try XCTUnwrap(Passkeys.von(Eintrag(id: "a", name: "A", unbekannt: ["passkeys": .liste([Self.eigener()])])).first)
        let a = try Passkeys.anmelden(p, clientDataHash: Self.hash)
        XCTAssertEqual(a.authenticatorData, Self.anmeldeDaten)
        XCTAssertEqual(a.credentialID, Self.kennung)
        XCTAssertEqual(a.userHandle, Data([1, 2]))
        XCTAssertEqual(a.rpId, "webauthn.io")
        let pub = try P256.Signing.PublicKey(rawRepresentation: Self.x + Self.y)
        let sig = try P256.Signing.ECDSASignature(derRepresentation: a.signatur)
        XCTAssertTrue(pub.isValidSignature(sig, for: Self.anmeldeDaten + Self.hash))
        XCTAssertFalse(pub.isValidSignature(sig, for: Self.anmeldeDaten + Data(repeating: 0, count: 32)))
    }

    func testAnlegenTestvektorUndTresorWert() throws {
        let k = try XCTUnwrap(Passkeys.privaterSchluessel(Self.pkcs8Url))
        let r = PasskeyRegistrierung(rpId: "WebAuthn.io", userName: "mia", userHandle: Data([1, 2]), clientDataHash: Self.hash)
        let neu = Passkeys.anlegen(r, jetzt: Date(timeIntervalSince1970: 0), schluessel: k, kennung: Self.kennung)
        XCTAssertEqual(neu.antwort.attestation, Self.attestation)
        XCTAssertEqual(neu.antwort.rpId, "webauthn.io")
        XCTAssertEqual(neu.antwort.credentialID, Self.kennung)
        // Der Tresor-Wert ist sofort wieder ein lesbarer Passkey, der zur Attestation passt.
        let gelesen = try XCTUnwrap(Passkeys.von(Eintrag(id: "a", name: "A", unbekannt: ["passkeys": .liste([neu.wert])])).first)
        XCTAssertEqual(gelesen.credentialID, Self.kennung)
        XCTAssertEqual(Passkeys.privaterSchluessel(gelesen.schluessel)?.publicKey.rawRepresentation, Self.x + Self.y)
        guard case .objekt(let d) = neu.wert else { return XCTFail() }
        XCTAssertEqual(d["erstellt"]?.alsText, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(d["userHandle"]?.alsText, "AQI")
    }

    func testZufallsKennungUndFrischerSchluessel() {
        let r = PasskeyRegistrierung(rpId: "webauthn.io", userName: "mia", userHandle: Data([1]), clientDataHash: Self.hash)
        let a = Passkeys.anlegen(r, jetzt: Date())
        let b = Passkeys.anlegen(r, jetzt: Date())
        XCTAssertEqual(a.antwort.credentialID.count, 16)
        XCTAssertNotEqual(a.antwort.credentialID, b.antwort.credentialID)
        XCTAssertNotEqual(a.wert, b.wert)
    }

    func testAblegenAmPassendenLoginSonstNeu() {
        let t = Tresor(eintraege: [
            Eintrag(id: "sub", name: "Sub", benutzer: "Mia", urls: ["https://m.webauthn.io"]),
            Eintrag(id: "genau", name: "Genau", benutzer: "mia", urls: ["https://webauthn.io"], unbekannt: ["passkeys": .liste([Self.eigener(id: Data([5]))])])
        ])
        let jetzt = Date(timeIntervalSince1970: 0)
        guard case .aktualisieren(let e) = Passkeys.ablegen(Self.eigener(), rpId: "webauthn.io", userName: "MIA", in: t, jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.id, "genau")
        XCTAssertEqual(e.unbekannt["passkeys"]?.alsListe?.count, 2, "alter Passkey bleibt")
        XCTAssertEqual(e.geaendert, Zeit.iso(jetzt))
        guard case .neu(let n) = Passkeys.ablegen(Self.eigener(), rpId: "webauthn.io", userName: "tom", in: t, jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(n.name, "webauthn.io")
        XCTAssertEqual(n.urls, ["https://webauthn.io"])
        XCTAssertEqual(n.benutzer, "tom")
        XCTAssertEqual(n.passwort, "")
    }

    func testCBORGrundformen() {
        XCTAssertEqual(CBOR.zahl(-7), Data([0x26]))
        XCTAssertEqual(CBOR.zahl(24), Data([0x18, 24]))
        XCTAssertEqual(CBOR.zahl(-1), Data([0x20]))
        XCTAssertEqual(CBOR.bytes(Data(count: 300)).prefix(3), Data([0x59, 0x01, 0x2C]))
        XCTAssertEqual(CBOR.text("fmt"), Data([0x63, 0x66, 0x6D, 0x74]))
        XCTAssertEqual(CBOR.karte([]), Data([0xA0]))
    }
}

/// Ablauf in der Erweiterung mit Attrappen (kein Face ID, kein System).
@MainActor
final class PasskeyModellTests: XCTestCase {
    private let k = TestSchluessel.schluessel

    private func modell(_ auftrag: AutoFillAuftrag, tresor: Tresor, ergebnis: @escaping (AutoFillErgebnis) -> Void) throws -> (AutoFillModell, TresorAblage) {
        let bund = Schluesselbund(speicher: MemorySpeicher(), dauer: { .aus })
        try bund.speichereSchluessel(k)
        try bund.speichereGeraet(Geraet(url: URL(string: "https://pc.test")!, token: TestSchluessel.token))
        let ablage = TresorAblage(ordner: try tempOrdner())
        try ablage.speichere(Umschlag.verschliesse(tresor, schluessel: k, rev: 1))
        let s = AutoFillSitzung(bund: bund, ablage: ablage, client: nil, identitaeten: { _ in })
        let m = AutoFillModell(auftrag: auftrag, sitzung: s, jetzt: { Date(timeIntervalSince1970: 59) },
                               einstellungen: GeteilteEinstellungen(speicher: UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)")!),
                               nutzung: Nutzung(speicher: UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)")!), warten: { _ in })
        m.abschluss = ergebnis
        m.zwischenablage = { _ in }
        return (m, ablage)
    }

    private static func passkey(_ id: UInt8, user: String) -> JSONWert {
        let schluessel = P256.Signing.PrivateKey()
        return .objekt(["credentialId": .text(Passkeys.base64url(Data([id]))), "rpId": .text("webauthn.io"), "userName": .text(user),
                        "userHandle": .text("AQI"), "key": .text(Passkeys.base64url(schluessel.derRepresentation))])
    }

    private let hash = Data(repeating: 7, count: 32)

    private lazy var tresor = Tresor(eintraege: [
        Eintrag(id: "a", name: "WebAuthn", benutzer: "mia", passwort: "pw", urls: ["https://webauthn.io"],
                geaendert: "2026-01-01T00:00:00.000Z", unbekannt: ["passkeys": .liste([Self.passkey(1, user: "mia"), Self.passkey(2, user: "tom")])])
    ])

    func testEinPasskeyAusDerLeisteMeldetSofortAn() async throws {
        var ergebnis: AutoFillErgebnis?
        let (m, _) = try modell(.passkey(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: hash, credentialID: Data([2]))), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        guard case .passkeyAnmeldung(let a) = ergebnis else { return XCTFail("\(String(describing: ergebnis))") }
        XCTAssertEqual(a.credentialID, Data([2]))
        XCTAssertEqual(a.clientDataHash, hash)
        XCTAssertFalse(a.signatur.isEmpty)
    }

    func testMehrerePasskeysZeigenAuswahl() async throws {
        var ergebnis: AutoFillErgebnis?
        let (m, _) = try modell(.passkey(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: hash)), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        guard case .passkeyWahl(let liste) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(liste.map(\.userName), ["mia", "tom"])
        m.waehlePasskey(liste[1])
        guard case .passkeyAnmeldung(let a) = ergebnis else { return XCTFail() }
        XCTAssertEqual(a.credentialID, Data([2]))
    }

    func testKeinPasskeyZeigtPasswoerterDerSeite() async throws {
        var ergebnis: AutoFillErgebnis?
        let (m, _) = try modell(.passkey(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: hash, erlaubt: [Data([9])])), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        XCTAssertEqual(m.phase, .liste)
        XCTAssertEqual(m.gruppen.passend.map(\.id), ["a"])
        m.waehle(m.gruppen.passend[0])
        XCTAssertEqual(ergebnis, .passwort(benutzer: "mia", passwort: "pw"))
    }

    func testUnbekannteKennungAusDerLeiste() async throws {
        var ergebnis: AutoFillErgebnis?
        let (m, _) = try modell(.passkey(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: hash, credentialID: Data([9]))), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        XCTAssertEqual(ergebnis, .nichtGefunden)
    }

    func testOhneFensterBrauchtEsDasBlatt() async throws {
        var ergebnis: AutoFillErgebnis?
        let (m, _) = try modell(.passkey(PasskeyAnfrage(rpId: "webauthn.io", clientDataHash: hash, credentialID: Data([1]))), tresor: tresor) { ergebnis = $0 }
        await m.starteOhneAbfrage()
        XCTAssertEqual(ergebnis, .abfrageNoetig, "MemorySpeicher ohne Entsperr-Fenster")
    }

    func testAnlegenSpeichertImTresor() async throws {
        var ergebnis: AutoFillErgebnis?
        let r = PasskeyRegistrierung(rpId: "webauthn.io", userName: "mia", userHandle: Data([1, 2]), clientDataHash: hash)
        let (m, ablage) = try modell(.passkeyNeu(r), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        guard case .passkeyAngelegt(let a) = ergebnis else { return XCTFail("\(String(describing: ergebnis))") }
        let gelesen = try await TresorDienst(ablage: ablage, client: nil).lokal(schluessel: k)
        let e = try XCTUnwrap(gelesen?.lebendige.first { $0.id == "a" })
        XCTAssertEqual(Passkeys.von(e).map(\.credentialID).last, a.credentialID, "am Login mit gleichem Benutzer")
        XCTAssertEqual(Passkeys.von(e).count, 3)
    }

    func testAnlegenBeiBekannterKennungBrichtAb() async throws {
        var ergebnis: AutoFillErgebnis?
        let r = PasskeyRegistrierung(rpId: "webauthn.io", userName: "mia", userHandle: Data([1]), clientDataHash: hash, ausgeschlossen: [Data([1])])
        let (m, ablage) = try modell(.passkeyNeu(r), tresor: tresor) { ergebnis = $0 }
        await m.starte()
        XCTAssertEqual(ergebnis, .passkeySchonDa)
        let gelesen = try await TresorDienst(ablage: ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(gelesen?.lebendige.first.map { Passkeys.von($0).count }, 2, "nichts angelegt")
    }
}
