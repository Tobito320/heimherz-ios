import XCTest
@testable import Heimherz

final class FotoRasterTests: XCTestCase {
    private let koepfe = (0..<6).map { FotoRegeln.kopf(assetId: "r\($0)") }

    private func anzeige(fertig: [Int] = [], laufend: [Int] = [], fehler: [Int: String] = [:], laeuft: Bool = false) -> FotoAnzeige {
        FotoAnzeige(laeuft: laeuft, fertig: Set(fertig.map { koepfe[$0].kennung }), laufend: Set(laufend.map { koepfe[$0].kennung }),
                    fehler: Dictionary(uniqueKeysWithValues: fehler.map { (koepfe[$0.key].kennung, $0.value) }))
    }

    func testStatusZuordnung() {
        let a = anzeige(fertig: [0], laufend: [1], fehler: [2: "kaputt"], laeuft: true)
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[0].kennung, anzeige: a), .amPC)
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[1].kennung, anzeige: a), .laeuft)
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[2].kennung, anzeige: a), .fehler("kaputt"))
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[3].kennung, anzeige: a), .wartet, "ein Abgleich läuft, dieses Bild kommt noch dran")
        let still = anzeige(fertig: [0])
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[3].kennung, anzeige: still), .offen)
    }

    func testAmPCSchlaegtLaufendUndFehler() {
        let a = anzeige(fertig: [0], laufend: [0], fehler: [0: "alt"], laeuft: true)
        XCTAssertEqual(FotoRaster.status(kennung: koepfe[0].kennung, anzeige: a), .amPC)
    }

    func testFilterBehaeltReihenfolge() {
        let a = anzeige(fertig: [0, 2, 3])
        XCTAssertEqual(FotoRaster.indizes(koepfe: koepfe, filter: .alle, anzeige: a), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(FotoRaster.indizes(koepfe: koepfe, filter: .amPC, anzeige: a), [0, 2, 3])
        XCTAssertEqual(FotoRaster.indizes(koepfe: koepfe, filter: .nochNicht, anzeige: a), [1, 4, 5])
    }

    func testUebertragenesErscheintImFilterAmPCSobaldEsFertigIst() {
        XCTAssertEqual(FotoRaster.indizes(koepfe: koepfe, filter: .amPC, anzeige: anzeige()), [])
        XCTAssertEqual(FotoRaster.indizes(koepfe: koepfe, filter: .amPC, anzeige: anzeige(fertig: [4])), [4])
    }

    func testStatusHatSymbolUndTextFuerVoiceOver() {
        for s in [FotoStatus.amPC, .laeuft, .wartet, .fehler("x"), .offen] {
            XCTAssertFalse(s.symbol.isEmpty)
            XCTAssertFalse(s.text.isEmpty)
        }
        XCTAssertEqual(FotoStatus.fehler("kaputt").text, "Fehler: kaputt")
    }

    func testCacheFensterBleibtImBereich() {
        XCTAssertEqual(FotoRaster.cacheFenster(mitte: 0, anzahl: 8_000), 0..<80)
        XCTAssertEqual(FotoRaster.cacheFenster(mitte: 1_000, anzahl: 8_000), 960..<1_080)
        XCTAssertEqual(FotoRaster.cacheFenster(mitte: 7_999, anzahl: 8_000), 7_959..<8_000)
        XCTAssertEqual(FotoRaster.cacheFenster(mitte: 5, anzahl: 0), 0..<0)
        XCTAssertEqual(FotoRaster.cacheFenster(mitte: 99, anzahl: 10), 0..<10)
    }

    func testFensterwechselNurRaender() {
        let erster = FotoRaster.fensterwechsel(alt: nil, neu: 0..<100)
        XCTAssertEqual(erster.start, [0..<100])
        XCTAssertEqual(erster.stopp, [])
        let weiter = FotoRaster.fensterwechsel(alt: 0..<100, neu: 30..<130)
        XCTAssertEqual(weiter.start, [100..<130])
        XCTAssertEqual(weiter.stopp, [0..<30])
        let sprung = FotoRaster.fensterwechsel(alt: 0..<100, neu: 500..<600)
        XCTAssertEqual(sprung.start, [500..<600])
        XCTAssertEqual(sprung.stopp, [0..<100])
        let gleich = FotoRaster.fensterwechsel(alt: 10..<50, neu: 10..<50)
        XCTAssertEqual(gleich.start, [])
        XCTAssertEqual(gleich.stopp, [])
        let wachsen = FotoRaster.fensterwechsel(alt: 40..<60, neu: 20..<80)
        XCTAssertEqual(wachsen.start, [20..<40, 60..<80])
        XCTAssertEqual(wachsen.stopp, [])
    }

    func testStandTextUndTempoText() {
        var a = FotoAnzeige(zahlen: FotoZahlen(gesamt: 8_312, amPC: 1_234))
        XCTAssertTrue(FotoText.stand(a).contains("234"), FotoText.stand(a))   // Tausendertrenner hängt von der Sprache ab
        XCTAssertTrue(FotoText.stand(a).hasSuffix("am PC"))
        a.zahlen = FotoZahlen(gesamt: 5, amPC: 5)
        XCTAssertEqual(FotoText.stand(a), "Alles liegt auf dem PC")
        XCTAssertNil(FotoText.tempo(FotoAnzeige()))
        a.restSekunden = 3_600
        XCTAssertEqual(FotoText.tempo(a), "ca. 1 Std. übrig")
    }
}
