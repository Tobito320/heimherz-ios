import XCTest
@testable import Heimherz

final class TeilenRegelnTests: XCTestCase {
    func testZielPfadLiegtImmerDirektInEingang() {
        XCTAssertEqual(TeilenRegeln.zielPfad(name: "Scan 2026-10-26.pdf"), "Eingang/Scan 2026-10-26.pdf")
        XCTAssertEqual(TeilenRegeln.zielPfad(name: "../a/b.pdf"), "Eingang/-a-b.pdf")
        XCTAssertEqual(TeilenRegeln.sauber(".heimherz-x.teil"), "heimherz-x.teil")
        XCTAssertEqual(TeilenRegeln.sauber("  "), "Datei")
        XCTAssertEqual(TeilenRegeln.sauber("..."), "Datei")
    }

    func testZeilen() {
        XCTAssertEqual(TeilenRegeln.kopfzeile(anzahl: 1), "1 Datei an den PC")
        XCTAssertEqual(TeilenRegeln.kopfzeile(anzahl: 3), "3 Dateien an den PC")
        XCTAssertEqual(TeilenRegeln.fortschritt(gesendet: 2, von: 5), "2 von 5")
    }

    func testFehlerTexte() {
        XCTAssertEqual(TeilenRegeln.fehlerText(HeimFehler.nichtGekoppelt), "Cloud ist nicht gekoppelt")
        XCTAssertEqual(TeilenRegeln.fehlerText(HeimFehler.nichtErreichbar), "PC nicht erreichbar")
        XCTAssertEqual(TeilenRegeln.fehlerText(HeimFehler.zeitueberschreitung), "PC nicht erreichbar")
        XCTAssertEqual(TeilenRegeln.fehlerText(HeimFehler.zuGross), HeimFehler.zuGross.nutzerText)
        XCTAssertEqual(TeilenRegeln.fehlerText(TeilenFehler.nichtLesbar), "Die Datei konnte nicht gelesen werden")
        XCTAssertEqual(TeilenRegeln.fehlerZeile(HeimFehler.nichtErreichbar, gesendet: 0, von: 3), "PC nicht erreichbar")
        XCTAssertEqual(TeilenRegeln.fehlerZeile(HeimFehler.nichtErreichbar, gesendet: 2, von: 3), "2 von 3 gesendet. PC nicht erreichbar")
    }

    func testNurNetzBerechtigungUndPlatteHaltenDenRestAn() {
        XCTAssertTrue(TeilenRegeln.haeltAn(HeimFehler.nichtErreichbar))
        XCTAssertTrue(TeilenRegeln.haeltAn(HeimFehler.nichtBerechtigt))
        XCTAssertTrue(TeilenRegeln.haeltAn(HeimFehler.speicherVoll))
        XCTAssertTrue(TeilenRegeln.haeltAn(HeimFehler.nichtGekoppelt))
        XCTAssertFalse(TeilenRegeln.haeltAn(HeimFehler.zuGross))
        XCTAssertFalse(TeilenRegeln.haeltAn(TeilenFehler.nichtLesbar))
    }
}
