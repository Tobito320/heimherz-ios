import XCTest
@testable import Heimherz

private struct TOTPFixture: Decodable {
    struct Vektor: Decodable { let geheim: String; let algorithmus: String; let stellen: Int; let periode: Int; let zeit: Int; let code: String }
    struct Uri: Decodable { let uri: String; let geheim: String; let algorithmus: String; let stellen: Int; let periode: Int }
    let vektoren: [Vektor]
    let uris: [Uri]
}

final class TOTPTests: XCTestCase {
    func testRFC6238Vektoren() throws {
        let f = try Fixture.lade(TOTPFixture.self, "totp", "rfc6238.json")
        XCTAssertGreaterThanOrEqual(f.vektoren.count, 18)
        for v in f.vektoren {
            let e = TOTPEinstellung(geheim: try XCTUnwrap(TOTP.base32(v.geheim)), algorithmus: try XCTUnwrap(.init(rawValue: v.algorithmus)), stellen: v.stellen, periode: v.periode)
            XCTAssertEqual(TOTP.code(e, zeit: v.zeit), v.code, "\(v.algorithmus) \(v.zeit)")
        }
    }

    func testUrisUndRohesBase32() throws {
        let f = try Fixture.lade(TOTPFixture.self, "totp", "rfc6238.json")
        XCTAssertGreaterThanOrEqual(f.uris.count, 3)
        for u in f.uris {
            let e = try XCTUnwrap(TOTP.einstellung(aus: u.uri), u.uri)
            XCTAssertEqual(e.geheim, TOTP.base32(u.geheim), u.uri)
            XCTAssertEqual(e.algorithmus.rawValue, u.algorithmus, u.uri)
            XCTAssertEqual(e.stellen, u.stellen, u.uri)
            XCTAssertEqual(e.periode, u.periode, u.uri)
        }
    }

    func testFuehrendeNullenUndPeriode() throws {
        // RFC-Vektor SHA1 bei t=1111111109 hat den Code 07081804 (führende Null)
        let e = TOTPEinstellung(geheim: try XCTUnwrap(TOTP.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")), stellen: 8)
        XCTAssertEqual(TOTP.code(e, zeit: 1_111_111_109), "07081804")
        XCTAssertEqual(TOTP.code(e, zeit: 59), "94287082")
        XCTAssertEqual(TOTP.code(e, zeit: 59), TOTP.code(e, zeit: 30))
        XCTAssertEqual(TOTP.restsekunden(e, zeit: 59), 1)
        XCTAssertEqual(TOTP.restsekunden(e, zeit: 60), 30)
    }

    func testAblehnen() {
        XCTAssertNil(TOTP.einstellung(aus: "otpauth://hotp/x?secret=GEZDGNBV&counter=1"))
        XCTAssertNil(TOTP.einstellung(aus: "otpauth://totp/x?issuer=nurName"))
        XCTAssertNil(TOTP.einstellung(aus: "otpauth://totp/x?secret=GEZDGNBV&digits=4"))
        XCTAssertNil(TOTP.einstellung(aus: "otpauth://totp/x?secret=GEZDGNBV&algorithm=MD5"))
        XCTAssertNil(TOTP.einstellung(aus: "otpauth://totp/x?secret=1890"))
        XCTAssertNil(TOTP.einstellung(aus: ""))
        XCTAssertNil(TOTP.einstellung(aus: "kein geheimnis!"))
    }

    func testBase32MitLeerzeichenUndKleinschreibung() {
        XCTAssertEqual(TOTP.base32("gezd gnbv-GY3T qojq==")?.count, 10)
        XCTAssertEqual(TOTP.base32("MFRGG"), Data("abc".utf8))
    }
}
