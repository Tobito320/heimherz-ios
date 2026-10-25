import XCTest
@testable import Heimherz

@MainActor
final class FotosModellTests: XCTestCase {
    func testDemoRuehrtPhotoKitUndNetzNichtAn() async throws {
        let ordner = try tempOrdner()
        let m = FotosModell(istDemo: true, ablage: FotoStandAblage(ordner: ordner))
        XCTAssertEqual(m.erlaubnis, .voll)
        XCTAssertEqual(m.anzeige.zahlen, FotoZahlen(gesamt: 1_390, amPC: 1_342))
        await m.lade(gekoppelt: true)
        await m.erlaube()
        m.schalteHintergrund(false)
        XCTAssertTrue(m.hintergrundAn, "Demo ändert nichts am System")
        m.abgleichen(client: HeimClient(basis: URL(fileURLWithPath: "/"), token: "x"))
        XCTAssertFalse(m.laeuft)
    }

    func testNurWLANWirdGespeichert() throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        let m = FotosModell(istDemo: true, ablage: ablage)
        XCTAssertTrue(m.nurWLAN, "Standard an")
        m.setzeNurWLAN(false)
        XCTAssertFalse(m.nurWLAN)
        XCTAssertEqual(ablage.lade().nurWLAN, false, "die Erweiterung liest denselben Wert")
    }
}
