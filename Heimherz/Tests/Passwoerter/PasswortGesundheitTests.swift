import XCTest
@testable import Heimherz

final class PasswortGesundheitTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_790_000_000)   // fest, 2026-09

    private func login(_ id: String, _ pw: String, vorTagen: Int = 10, totp: String = "", unbekannt: [String: JSONWert] = [:]) -> Eintrag {
        let datum = jetzt.addingTimeInterval(-Double(vorTagen) * 86_400)
        return Eintrag(id: id, name: "Seite \(id)", benutzer: "mia", passwort: pw, urls: ["https://\(id).example.org"], totp: totp,
                       geaendert: Zeit.iso(datum), unbekannt: unbekannt)
    }

    private let starkA = "Zr7!kQpL92xw", starkB = "Hq4#mTe81vNa"
    private let code = "otpauth://totp/Beispiel:mia?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    func testSchwach() {
        let h = PasswortGesundheit.pruefe([login("a", "12345678", totp: code), login("b", starkA, totp: code)], jetzt: jetzt)
        XCTAssertEqual(h.ids(.schwach), ["a"])
    }

    func testGleichesPasswortNurBeiMehrerenEintraegen() {
        let h = PasswortGesundheit.pruefe([login("a", starkA), login("b", starkA), login("c", starkB)], jetzt: jetzt)
        XCTAssertEqual(h.ids(.gleich), ["a", "b"])
    }

    func testAltGrenzeNachEinemJahr() {
        let h = PasswortGesundheit.pruefe([login("jung", starkA, vorTagen: 364), login("grenze", starkA, vorTagen: 365), login("alt", starkB, vorTagen: 366)], jetzt: jetzt)
        XCTAssertEqual(h.ids(.alt), ["alt"], "365 Tage genau ist noch nicht älter als ein Jahr")
    }

    func testOhne2FAAberMitCodeOderPasskeyZaehltNicht() {
        let passkey: [String: JSONWert] = ["passkeys": .liste([.objekt(["rpId": .text("example.org"), "userName": .text("mia")])])]
        let h = PasswortGesundheit.pruefe([login("ohne", starkA), login("mitCode", starkB, totp: code), login("mitPasskey", "Lk9$wXz55rBc", unbekannt: passkey),
                                           login("kaputterCode", "Pm3&cYh67tDe", totp: "kein base32 !!")], jetzt: jetzt)
        XCTAssertEqual(h.ids(.ohne2FA), ["ohne", "kaputterCode"])
    }

    func testNotizenGrabsteineUndEintraegeOhnePasswortZaehlenNicht() {
        let notiz = Eintrag(id: "n", art: Eintrag.artNotiz, name: "N", passwort: "12345678", geaendert: Zeit.iso(jetzt.addingTimeInterval(-9_999 * 86_400)))
        var weg = login("w", "12345678"); weg.geloescht = true
        let h = PasswortGesundheit.pruefe([notiz, weg, login("leer", "")], jetzt: jetzt)
        XCTAssertTrue(h.istLeer)
    }

    func testEinEintragKannInVielenGruppenStehen() {
        let h = PasswortGesundheit.pruefe([login("a", "12345678", vorTagen: 900), login("b", "12345678", vorTagen: 1)], jetzt: jetzt)
        XCTAssertEqual(h.ids(.schwach), ["a", "b"])
        XCTAssertEqual(h.ids(.gleich), ["a", "b"])
        XCTAssertEqual(h.ids(.alt), ["a"])
        XCTAssertEqual(h.ids(.ohne2FA), ["a", "b"])
        XCTAssertFalse(h.istLeer)
        XCTAssertEqual(h.anzahl(.alt), 1)
    }

    func testKachelZahlSicherheitBleibtUnveraendert() {
        // "Ohne 2FA" und "alt" dürfen die Liste "Sicherheit" nicht füllen: ein starkes, einmaliges Passwort ohne Code bleibt dort unsichtbar.
        let e = login("a", starkA, vorTagen: 900)
        XCTAssertEqual(PasswortSicherheit.pruefe([e]), [])
        XCTAssertEqual(PasswortGesundheit.pruefe([e], jetzt: jetzt).ids(.alt), ["a"])
    }

    func testLeerUndGruppenTexte() {
        XCTAssertTrue(PasswortGesundheit.pruefe([], jetzt: jetzt).istLeer)
        XCTAssertEqual(GesundheitGruppe.allCases.map(\.titel), ["Schwach", "Gleiches Passwort", "Alt", "Ohne 2FA"])
    }
}
