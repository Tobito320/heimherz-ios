import XCTest
@testable import Heimherz

@MainActor
final class FotosModellTests: XCTestCase {
    func testDemoRuehrtPhotoKitUndNetzNichtAn() async throws {
        let ordner = try tempOrdner()
        let m = FotosModell(istDemo: true, ablage: FotoStandAblage(ordner: ordner))
        XCTAssertEqual(m.erlaubnis, .voll)
        XCTAssertEqual(m.anzeige.zahlen, FotoZahlen(gesamt: 8_312, amPC: 1_234))
        let vorher = m.anzeige
        await m.lade(gekoppelt: true)
        await m.erlaube()
        m.schalteHintergrund(false)
        XCTAssertTrue(m.hintergrundAn, "Demo ändert nichts am System")
        m.starte(client: HeimClient(basis: URL(fileURLWithPath: "/"), token: "x"))
        m.aktualisiere(client: HeimClient(basis: URL(fileURLWithPath: "/"), token: "x"))
        m.halteAn()
        XCTAssertEqual(m.anzeige, vorher, "die Demo startet und stoppt nichts")
    }

    func testICloudSchalterWirdGespeichert() throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        let m = FotosModell(istDemo: true, ablage: ablage)
        XCTAssertTrue(m.iCloudLaden, "Standard an")
        m.setzeICloudLaden(false)
        XCTAssertFalse(m.iCloudLaden)
        XCTAssertEqual(ablage.lade().iCloudLaden, false)
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
