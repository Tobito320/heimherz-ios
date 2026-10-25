import XCTest
@testable import Heimherz

final class FotoTempoTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func nach(_ s: TimeInterval) -> Date { start.addingTimeInterval(s) }

    func testErstNachEinerWeileEineZahl() {
        var t = FotoTempo(start: start)
        XCTAssertNil(t.bytesProSekunde(jetzt: nach(10)), "ohne bestätigte Daten keine Geschwindigkeit")
        t.buche(bytes: 20_000_000, jetzt: nach(1))
        XCTAssertNil(t.bytesProSekunde(jetzt: nach(1)), "nach einer Sekunde wäre es Zufall")
        // Laufzeit 10 s ist kürzer als das Fenster: 20 MB in 10 s
        XCTAssertEqual(try XCTUnwrap(t.bytesProSekunde(jetzt: nach(10))), 2_000_000, accuracy: 0.1)
    }

    func testGleitendNurDieLetztenSekundenZaehlen() throws {
        var t = FotoTempo(start: start)
        // Erst 100 MB bei Sekunde 5, danach 1 MB je Sekunde ab Sekunde 40: der Start darf die Zahl nicht mehr bestimmen.
        t.buche(bytes: 100_000_000, jetzt: nach(5))
        for s in 40...54 { t.buche(bytes: 1_000_000, jetzt: nach(TimeInterval(s))) }
        XCTAssertEqual(try XCTUnwrap(t.bytesProSekunde(jetzt: nach(54))), 1_000_000, accuracy: 100_000, "15 Dateien zu 1 MB in 15 s")
        XCTAssertEqual(t.bytes, 115_000_000)
    }

    func testStillstandZeigtKeineZahl() {
        var t = FotoTempo(start: start)
        t.buche(bytes: 5_000_000, jetzt: nach(3))
        XCTAssertNotNil(t.bytesProSekunde(jetzt: nach(4)))
        XCTAssertNil(t.bytesProSekunde(jetzt: nach(30)), "seit über 15 s nichts bestätigt")
    }

    func testRestzeitAusGleitenderGeschwindigkeit() throws {
        var t = FotoTempo(start: start)
        t.buche(bytes: 1_000_000, jetzt: nach(1)); t.buche(bytes: 1_000_000, jetzt: nach(2))
        XCTAssertNil(t.restSekunden(offen: 100, jetzt: nach(10)), "erst ab drei Dateien")
        t.buche(bytes: 1_000_000, jetzt: nach(3))
        XCTAssertNil(t.restSekunden(offen: 100, jetzt: nach(4)), "erst nach ein paar Sekunden")
        // 3 MB in 10 s = 0,3 MB/s, mittlere Datei 1 MB, 100 offen = 100 MB / 0,3 MB/s
        XCTAssertEqual(try XCTUnwrap(t.restSekunden(offen: 100, jetzt: nach(10))), 100_000_000 / 300_000, accuracy: 0.01)
        XCTAssertNil(t.restSekunden(offen: 0, jetzt: nach(10)))
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

    func testMessungWirdZuKopfzeilenNurMitZahlen() throws {
        var r = URLRequest(url: try XCTUnwrap(URL(string: "https://pc.example/v1/fotos/K/foto-0")))
        FotoMessung(exportMs: 120, warteMs: 35, aktiv: 6, exporte: 3, iCloud: false).setze(in: &r)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Export-Ms"), "120")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Warte-Ms"), "35")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Aktiv"), "6")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Exporte"), "3")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Durchgang"), "lokal")
        FotoMessung(exportMs: -5, warteMs: 0, aktiv: 1, exporte: 0, iCloud: true).setze(in: &r)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Export-Ms"), "0", "nie negativ")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Heim-Durchgang"), "icloud")

        let vorn = FotoMessung.markiere(r, vordergrund: true, zusatzWarteMs: 40)
        XCTAssertEqual(vorn.value(forHTTPHeaderField: "X-Heim-Vordergrund"), "1")
        XCTAssertEqual(vorn.value(forHTTPHeaderField: "X-Heim-Session"), "vorder")
        XCTAssertEqual(vorn.value(forHTTPHeaderField: "X-Heim-Warte-Ms"), "40", "0 + 40")
        let hinten = FotoMessung.markiere(r, vordergrund: false)
        XCTAssertEqual(hinten.value(forHTTPHeaderField: "X-Heim-Vordergrund"), "0")
        XCTAssertEqual(hinten.value(forHTTPHeaderField: "X-Heim-Session"), "hinter")
    }
}
