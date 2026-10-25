import XCTest
@testable import Heimherz

@MainActor
final class EntwurfTests: XCTestCase {
    func testNeuerLoginBrauchtNamenOderWebseite() {
        var e = Entwurf()
        XCTAssertFalse(e.kannSpeichern)
        e.urlFelder[0].text = "github.com/login"
        XCTAssertTrue(e.kannSpeichern, "Webseite ersetzt den Namen")
        XCTAssertEqual(e.neuerEintrag().name, "github.com")
        e.name = "  GitHub  "
        XCTAssertEqual(e.neuerEintrag().name, "GitHub")
    }

    func testNotizBrauchtEinenNamen() {
        var e = Entwurf(art: Eintrag.artNotiz)
        e.urlFelder[0].text = "github.com"
        XCTAssertFalse(e.kannSpeichern)
        e.name = "WLAN"
        e.notiz = "Passwort am Kühlschrank"
        XCTAssertTrue(e.kannSpeichern)
        let n = e.neuerEintrag()
        XCTAssertEqual(n.art, Eintrag.artNotiz)
        XCTAssertEqual(n.urls, [], "Notizen haben keine Login-Felder")
    }

    func testEinmalcodeMussLesbarSein() {
        var e = Entwurf()
        e.name = "x"
        e.totp = "das ist kein code!"
        XCTAssertFalse(e.kannSpeichern)
        e.totp = " JBSWY3DPEHPK3PXP "
        XCTAssertTrue(e.kannSpeichern)
        e.totp = "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP"
        XCTAssertTrue(e.kannSpeichern)
        XCTAssertEqual(e.neuerEintrag().totp, "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP")
    }

    func testMehrereUrlsLeereFallenWeg() {
        var e = Entwurf()
        e.name = "x"
        e.urlFelder = [.init(text: " https://a.org "), .init(text: ""), .init(text: "https://b.org")]
        XCTAssertEqual(e.neuerEintrag().urls, ["https://a.org", "https://b.org"])
    }

    func testBearbeitenBehaeltIdUndUnbekannteFelder() {
        let alt = Eintrag(id: "42", name: "Alt", benutzer: "a", passwort: "p", urls: ["https://a.org", "https://b.org"], geaendert: "2026-01-01T00:00:00.000Z",
                          unbekannt: ["zukunft": .text("bleibt"), "anzahl": .zahl(3)])
        var e = Entwurf(eintrag: alt)
        XCTAssertEqual(e.urlFelder.count, 2)
        e.name = "Neu"
        e.passwort = "q"
        let neu = e.anwenden(auf: alt)
        XCTAssertEqual(neu.id, "42")
        XCTAssertEqual(neu.name, "Neu")
        XCTAssertEqual(neu.passwort, "q")
        XCTAssertEqual(neu.unbekannt, alt.unbekannt)
        XCTAssertEqual(neu.urls, alt.urls)
    }

    func testLeereURLListeBekommtEinFeld() {
        XCTAssertEqual(Entwurf(eintrag: Eintrag(id: "1", name: "x")).urlFelder.count, 1)
    }
}

@MainActor
final class HilfenTests: XCTestCase {
    func testZwischenablageNurAufDiesemGeraetUndNach60Sekunden() throws {
        let jetzt = Date(timeIntervalSince1970: 1_800_000_000)
        let o = Zwischenablage.optionen(jetzt: jetzt)
        XCTAssertEqual(o[.localOnly] as? Bool, true)
        XCTAssertEqual(o[.expirationDate] as? Date, jetzt.addingTimeInterval(60))
        XCTAssertEqual(Zwischenablage.ablaufSekunden, 60)
    }

    func testTotpAnzeigeMitRfcVektor() throws {
        // RFC 6238: SHA1, Geheimnis "12345678901234567890", t = 59 → 94287082 (8 Stellen)
        let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8"
        let z = try XCTUnwrap(TOTPAnzeige.zustand(uri, datum: Date(timeIntervalSince1970: 59)))
        XCTAssertEqual(z.code, "94287082")
        XCTAssertEqual(z.gruppiert, "9428 7082")
        XCTAssertEqual(z.rest, 1)
        XCTAssertEqual(z.periode, 30)
        XCTAssertEqual(z.anteil, 1.0 / 30.0, accuracy: 0.0001)
        let sechs = try XCTUnwrap(TOTPAnzeige.zustand("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", datum: Date(timeIntervalSince1970: 59)))
        XCTAssertEqual(sechs.code.count, 6)
        XCTAssertEqual(sechs.gruppiert.count, 7)
        XCTAssertNil(TOTPAnzeige.zustand("", datum: Date()))
        XCTAssertNil(TOTPAnzeige.zustand("kein code!", datum: Date()))
    }

    func testNurWebAdressenWerdenGeoeffnet() {
        XCTAssertEqual(EintragDetailView.sichereURL("github.com")?.host, "github.com")
        XCTAssertEqual(EintragDetailView.sichereURL("http://a.org/x")?.scheme, "http")
        for boese in ["javascript:alert(1)", "tel://123", "file:///etc/passwd", "heimherz://koppeln", "itms-apps://x"] {
            let u = EintragDetailView.sichereURL(boese)
            XCTAssertTrue(u == nil || u?.scheme == "https" || u?.scheme == "http", boese)
            XCTAssertNotEqual(u?.scheme, "file")
            XCTAssertNotEqual(u?.scheme, "javascript")
        }
    }
}
