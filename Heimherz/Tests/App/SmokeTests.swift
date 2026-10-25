import XCTest
@testable import Heimherz

final class SmokeTests: XCTestCase {
    func testFixtureOrdnerIstImBundle() throws {
        let url = Bundle(for: SmokeTests.self).url(forResource: "umschlag-1", withExtension: "json", subdirectory: "fixtures/tresor")
        XCTAssertNotNil(url)
    }
}
