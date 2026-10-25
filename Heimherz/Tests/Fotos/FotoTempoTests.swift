import XCTest
@testable import Heimherz

final class FotoTempoTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testErstNachEinerWeileEineZahl() {
        var t = FotoTempo(start: start)
        XCTAssertNil(t.bytesProSekunde(jetzt: start.addingTimeInterval(10)), "ohne Daten keine Geschwindigkeit")
        t.buche(bytes: 20_000_000)
        XCTAssertNil(t.bytesProSekunde(jetzt: start.addingTimeInterval(1)), "nach einer Sekunde wäre es Zufall")
        XCTAssertEqual(try XCTUnwrap(t.bytesProSekunde(jetzt: start.addingTimeInterval(10))), 2_000_000, accuracy: 0.1)
    }

    func testRestzeitAusDemSchnittJeDatei() throws {
        var t = FotoTempo(start: start)
        t.buche(bytes: 1); t.buche(bytes: 1)
        XCTAssertNil(t.restSekunden(offen: 100, jetzt: start.addingTimeInterval(60)), "erst ab drei Dateien")
        t.buche(bytes: 1)
        // 3 Dateien in 30 Sekunden = 10 s je Datei, 100 offen = 1000 s
        XCTAssertEqual(try XCTUnwrap(t.restSekunden(offen: 100, jetzt: start.addingTimeInterval(30))), 1_000, accuracy: 0.001)
        XCTAssertNil(t.restSekunden(offen: 0, jetzt: start.addingTimeInterval(30)))
        XCTAssertNil(t.restSekunden(offen: 100, jetzt: start.addingTimeInterval(3)), "erst nach ein paar Sekunden")
    }

    func testRestText() {
        XCTAssertEqual(FotoTempo.restText(10), "weniger als 1 Min.")
        XCTAssertEqual(FotoTempo.restText(60), "weniger als 1 Min.")
        XCTAssertEqual(FotoTempo.restText(61), "ca. 2 Min.")
        XCTAssertEqual(FotoTempo.restText(25 * 60), "ca. 25 Min.")
        XCTAssertEqual(FotoTempo.restText(60 * 60), "ca. 1 Std.")
        XCTAssertEqual(FotoTempo.restText(95 * 60), "ca. 1 Std. 35 Min.")
        XCTAssertEqual(FotoTempo.restText(30 * 3_600), "mehr als 1 Tag")
    }
}
