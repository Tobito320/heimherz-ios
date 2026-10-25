import XCTest
@testable import Heimherz

final class BildschirmWachTests: XCTestCase {
    func testNurMitLaufendemAbgleichUndStrom() {
        XCTAssertTrue(BildschirmWach.soll(laeuft: true, amStrom: true))
        XCTAssertFalse(BildschirmWach.soll(laeuft: true, amStrom: false), "ohne Strom darf der Bildschirm ausgehen")
        XCTAssertFalse(BildschirmWach.soll(laeuft: false, amStrom: true), "nach dem Ende oder Anhalten wieder normal")
        XCTAssertFalse(BildschirmWach.soll(laeuft: false, amStrom: false))
    }
}
