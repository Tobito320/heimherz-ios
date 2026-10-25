import CryptoKit
import XCTest
@testable import Heimherz

private struct WiederherstellungFixture: Decodable {
    let code: String
    let schluessel: String
    let blatt: WiederherstellungsBlatt
}

final class WiederherstellungTests: XCTestCase {
    private func fixture() throws -> WiederherstellungFixture { try Fixture.lade(WiederherstellungFixture.self, "sicherung", "wiederherstellung-1.json") }

    func testTestvektorAusTSOeffnetSich() throws {
        let f = try fixture()
        let code = try XCTUnwrap(Wiederherstellung.codeDaten(f.code))
        let k = try Wiederherstellung.entwickle(f.blatt, code: code)
        XCTAssertEqual(k.withUnsafeBytes { Data($0) }, Data(base64Encoded: f.schluessel))
    }

    func testMitFestemSaltUndNonceByteGleichZurTSFixture() throws {
        let f = try fixture()
        let code = try XCTUnwrap(Wiederherstellung.codeDaten(f.code))
        let blatt = try Wiederherstellung.umwickle(schluessel: TestSchluessel.schluessel, code: code,
                                                   salt: Data(base64Encoded: f.blatt.salt),
                                                   nonce: AES.GCM.Nonce(data: XCTUnwrap(Data(base64Encoded: f.blatt.nonce))))
        XCTAssertEqual(blatt, f.blatt)
    }

    func testCodeTextRundeUndFormat() throws {
        let f = try fixture()
        let bytes = try XCTUnwrap(Wiederherstellung.codeDaten(f.code))
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(Wiederherstellung.codeText(bytes), f.code)
        XCTAssertEqual(Wiederherstellung.codeDaten(f.code.lowercased().replacingOccurrences(of: "-", with: " ")), bytes)
        let zufall = Wiederherstellung.codeText(Wiederherstellung.neuerCode())
        XCTAssertNotNil(zufall.range(of: "^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$", options: .regularExpression))
    }

    func testSchlechteCodesWerdenAbgelehnt() throws {
        let f = try fixture()
        for schlecht in ["", "ABCD", f.code + "A", f.code.replacingOccurrences(of: "K", with: "0"), f.code.replacingOccurrences(of: "K", with: "1")] {
            XCTAssertNil(Wiederherstellung.codeDaten(schlecht), schlecht)
        }
    }

    func testRundeMitZufallscodeUndFalscherCode() throws {
        let code = Wiederherstellung.neuerCode()
        XCTAssertNotEqual(code, Wiederherstellung.neuerCode())
        let b1 = try Wiederherstellung.umwickle(schluessel: TestSchluessel.schluessel, code: code)
        let b2 = try Wiederherstellung.umwickle(schluessel: TestSchluessel.schluessel, code: code)
        XCTAssertNotEqual(b1.salt, b2.salt)
        XCTAssertEqual(try Wiederherstellung.entwickle(b1, code: code).withUnsafeBytes { Data($0) }, TestSchluessel.roh)
        XCTAssertThrowsError(try Wiederherstellung.entwickle(b1, code: Wiederherstellung.neuerCode())) { XCTAssertEqual($0 as? WiederherstellungFehler, .codePasstNicht) }
    }

    func testVeraendertesOderKaputtesBlatt() throws {
        let f = try fixture()
        let code = try XCTUnwrap(Wiederherstellung.codeDaten(f.code))
        var d = try XCTUnwrap(Data(base64Encoded: f.blatt.daten)); d[3] ^= 1
        var b = f.blatt; b.daten = d.base64EncodedString()
        XCTAssertThrowsError(try Wiederherstellung.entwickle(b, code: code)) { XCTAssertEqual($0 as? WiederherstellungFehler, .codePasstNicht) }
        b = f.blatt; b.salt = "AAAA"
        XCTAssertThrowsError(try Wiederherstellung.entwickle(b, code: code)) { XCTAssertEqual($0 as? WiederherstellungFehler, .blattUngueltig) }
        XCTAssertThrowsError(try Wiederherstellung.entwickle(f.blatt, code: Data(count: 5))) { XCTAssertEqual($0 as? WiederherstellungFehler, .blattUngueltig) }
    }
}
