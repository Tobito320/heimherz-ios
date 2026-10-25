import XCTest
@testable import Heimherz

final class DateienLogikTests: XCTestCase {
    func testPfadUndBrotkrumen() {
        XCTAssertEqual(DateiPfad.zusammen([], "a.pdf"), "a.pdf")
        XCTAssertEqual(DateiPfad.zusammen(["Scans", "2026"], "a b.pdf"), "Scans/2026/a b.pdf")
        let k = DateiPfad.krumen(ordner: ["Scans", "2026"])
        XCTAssertEqual(k.map(\.titel), ["Dateien", "Scans", "2026"])
        XCTAssertEqual(k.map(\.tiefe), [0, 1, 2])
        XCTAssertEqual(DateiPfad.krumen(ordner: []).count, 1)
    }

    func testSymbole() {
        XCTAssertEqual(DateiAnzeige.symbol(name: "x", ordner: true), "folder.fill")
        XCTAssertEqual(DateiAnzeige.symbol(name: "A.PDF", ordner: false), "doc.richtext.fill")
        XCTAssertEqual(DateiAnzeige.symbol(name: "film.MOV", ordner: false), "film.fill")
        XCTAssertEqual(DateiAnzeige.symbol(name: "ohneendung", ordner: false), "doc.fill")
    }

    func testUntertitelMitGroesseUndDatum() {
        let datei = DateiInfo(name: "a.pdf", ordner: false, groesse: 1_500_000, geaendert: "2026-10-25T10:00:00.000Z")
        XCTAssertTrue(DateiAnzeige.untertitel(datei).contains("2026"), DateiAnzeige.untertitel(datei))
        XCTAssertTrue(DateiAnzeige.untertitel(DateiInfo(name: "o", ordner: true, groesse: 0, geaendert: "2026-10-25T10:00:00.000Z")).hasPrefix("Ordner"))
        XCTAssertEqual(DateiAnzeige.untertitel(DateiInfo(name: "o", ordner: true, groesse: 0, geaendert: "kaputt")), "Ordner")
    }

    func testVorschauPfadTrenntGleicheNamenAusAnderenOrdnern() {
        let w = URL(fileURLWithPath: "/cache")
        let a = VorschauCache.ziel(wurzel: w, pfad: "A/rechnung.pdf", name: "rechnung.pdf")
        let b = VorschauCache.ziel(wurzel: w, pfad: "B/rechnung.pdf", name: "rechnung.pdf")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.lastPathComponent, "rechnung.pdf", "die Endung bleibt für QuickLook")
        XCTAssertEqual(a, VorschauCache.ziel(wurzel: w, pfad: "A/rechnung.pdf", name: "rechnung.pdf"))
        XCTAssertEqual(a.deletingLastPathComponent().lastPathComponent.count, 16)
    }

    func testFotoNamen() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let d = Date(timeIntervalSince1970: 1_792_922_407) // 2026-10-25 10:00:07 UTC
        XCTAssertEqual(DateiNamen.fotoName(datum: d, endung: "HEIC", nummer: 1, zeitzone: utc), "Foto 2026-10-25 10-00-07.heic")
        XCTAssertEqual(DateiNamen.fotoName(datum: d, endung: "mov", nummer: 3, zeitzone: utc), "Foto 2026-10-25 10-00-07 3.mov")
        XCTAssertEqual(DateiNamen.fotoName(datum: d, endung: "", nummer: 1, zeitzone: utc), "Foto 2026-10-25 10-00-07")
    }

    func testErgebnisTexte() {
        XCTAssertEqual(DateienModell.ergebnisText(ok: 1, von: 1, fehler: nil).text, "1 Datei hochgeladen.")
        XCTAssertEqual(DateienModell.ergebnisText(ok: 3, von: 3, fehler: nil).text, "3 Dateien hochgeladen.")
        XCTAssertTrue(DateienModell.ergebnisText(ok: 1, von: 3, fehler: "x").istFehler)
        XCTAssertEqual(DateienModell.ergebnisText(ok: 0, von: 2, fehler: "Weg.").text, "Weg.")
    }
}
