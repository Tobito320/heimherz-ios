import XCTest
@testable import Heimherz

final class SicherungStandTests: XCTestCase {
    private func datei(_ name: String, _ iso: String, ordner: Bool = false) -> DateiInfo {
        DateiInfo(name: name, ordner: ordner, groesse: 1, geaendert: iso)
    }

    func testNeuesteSicherungsdatei() {
        let liste = [datei("heimherz-tresor-2026-10-25.heimsicherung", "2026-10-25T10:00:00.000Z"),
                     datei("heimherz-tresor-2026-10-26.heimsicherung", "2026-10-26T10:00:00.000Z"),
                     datei("notiz.txt", "2026-10-27T10:00:00.000Z"),
                     datei("Ordner.heimsicherung", "2026-10-28T10:00:00.000Z", ordner: true)]
        XCTAssertEqual(SicherungStand.neueste(liste), Date(timeIntervalSince1970: Double(Zeit.millis(iso: "2026-10-26T10:00:00.000Z") ?? 0) / 1000))
    }

    func testLeereListeUndText() {
        XCTAssertNil(SicherungStand.neueste([]))
        XCTAssertEqual(SicherungStand.text(nil), "noch keine")
        XCTAssertFalse(SicherungStand.text(Date()).isEmpty)
    }
}
