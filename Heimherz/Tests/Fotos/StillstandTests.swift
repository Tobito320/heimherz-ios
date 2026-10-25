import XCTest
@testable import Heimherz

final class StillstandTests: XCTestCase {
    func testFrischRuhtNicht() {
        XCTAssertFalse(Stillstand().ruht(laengerAls: .seconds(1)))
    }

    func testOhneDatenRuhtNachDerGrenze() async throws {
        let s = Stillstand()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(s.ruht(laengerAls: .milliseconds(50)))
    }

    func testDatenSetzenDieUhrZurueck() async throws {
        let s = Stillstand()
        try await Task.sleep(for: .milliseconds(80))
        s.regt()
        XCTAssertFalse(s.ruht(laengerAls: .milliseconds(50)))
    }
}
