import XCTest
@testable import Heimherz

final class DateienLogikTests: XCTestCase {
    func testPfadUndStufen() {
        XCTAssertEqual(DateiPfad.zusammen([], "a.pdf"), "a.pdf")
        XCTAssertEqual(DateiPfad.zusammen(["Scans", "2026"], "a b.pdf"), "Scans/2026/a b.pdf")
        XCTAssertEqual(DateiPfad.teile("Scans/2026/a b.pdf"), ["Scans", "2026", "a b.pdf"])
        XCTAssertEqual(DateiPfad.teile(""), [])
        XCTAssertEqual(DateiPfad.stufen(["Scans", "2026", "Q3"]), [["Scans"], ["Scans", "2026"], ["Scans", "2026", "Q3"]])
        XCTAssertEqual(DateiPfad.stufen([]), [])
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

    func testZwischenspeicherGroesseUndLeeren() throws {
        let wurzel = try tempOrdner().appending(path: "cache", directoryHint: .isDirectory)
        XCTAssertEqual(VorschauCache.groesse(wurzel: wurzel), 0, "ohne Ordner nichts")
        let unter = wurzel.appending(path: "ab12", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unter, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: wurzel.appending(path: "a.bin"))
        try Data(count: 2_500).write(to: unter.appending(path: "b.bin"))
        XCTAssertEqual(VorschauCache.groesse(wurzel: wurzel), 3_500, "Dateien in Unterordnern zählen mit, Ordner selbst nicht")
        VorschauCache.leere(wurzel: wurzel)
        XCTAssertEqual(VorschauCache.groesse(wurzel: wurzel), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wurzel.path))
    }

    // MARK: Sortierung

    private func datei(_ name: String, ordner: Bool = false, groesse: Int64 = 0, tag: Int = 1) -> DateiInfo {
        DateiInfo(name: name, ordner: ordner, groesse: groesse, geaendert: String(format: "2026-10-%02dT10:00:00.000Z", tag))
    }

    private func namen(_ liste: [DateiInfo], _ s: DateiSortierung) -> [String] { s.sortiere(liste).map(\.name) }

    func testSortierenNachNameMitOrdnernOben() {
        let l = [datei("b.pdf"), datei("Zeta", ordner: true), datei("a.pdf"), datei("Alpha", ordner: true), datei("Datei 10.txt"), datei("Datei 2.txt")]
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .name, aufsteigend: true)), ["Alpha", "Zeta", "a.pdf", "b.pdf", "Datei 2.txt", "Datei 10.txt"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .name, aufsteigend: false)), ["Zeta", "Alpha", "Datei 10.txt", "Datei 2.txt", "b.pdf", "a.pdf"])
    }

    func testSortierenNachDatumGroesseUndArt() {
        let l = [datei("alt.pdf", groesse: 300, tag: 3), datei("neu.png", groesse: 100, tag: 20), datei("mitte.pdf", groesse: 200, tag: 10), datei("Ordner", ordner: true, tag: 1)]
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .datum, aufsteigend: false)), ["Ordner", "neu.png", "mitte.pdf", "alt.pdf"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .datum, aufsteigend: true)), ["Ordner", "alt.pdf", "mitte.pdf", "neu.png"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .groesse, aufsteigend: false)), ["Ordner", "alt.pdf", "mitte.pdf", "neu.png"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .groesse, aufsteigend: true)), ["Ordner", "neu.png", "mitte.pdf", "alt.pdf"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .art, aufsteigend: true)), ["Ordner", "alt.pdf", "mitte.pdf", "neu.png"], "gleiche Art: nach Name")
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .art, aufsteigend: false)), ["Ordner", "neu.png", "alt.pdf", "mitte.pdf"], "Richtung dreht nur die Art, Gleichstand bleibt A bis Z")
    }

    func testGleichstandEntscheidetDerNameAuchRueckwaerts() {
        let l = [datei("b", groesse: 5), datei("a", groesse: 5), datei("c", groesse: 9)]
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .groesse, aufsteigend: false)), ["c", "a", "b"])
        XCTAssertEqual(namen(l, DateiSortierung(kriterium: .groesse, aufsteigend: true)), ["a", "b", "c"])
    }

    func testMenueTippenStartetInUeblicherRichtungUndDrehtUm() {
        var s = DateiSortierung.standard
        XCTAssertEqual(s, DateiSortierung(kriterium: .name, aufsteigend: true))
        s = s.nachTippen(auf: .name)
        XCTAssertEqual(s, DateiSortierung(kriterium: .name, aufsteigend: false), "zweites Tippen dreht")
        s = s.nachTippen(auf: .datum)
        XCTAssertEqual(s, DateiSortierung(kriterium: .datum, aufsteigend: false), "Datum: Neuestes zuerst")
        s = s.nachTippen(auf: .datum)
        XCTAssertEqual(s, DateiSortierung(kriterium: .datum, aufsteigend: true))
        s = s.nachTippen(auf: .groesse)
        XCTAssertEqual(s, DateiSortierung(kriterium: .groesse, aufsteigend: false))
        s = s.nachTippen(auf: .art)
        XCTAssertEqual(s, DateiSortierung(kriterium: .art, aufsteigend: true))
    }

    func testSortierungWirdGemerktUndKaputtesFaelltZurueck() {
        for k in SortierKriterium.allCases {
            for auf in [true, false] {
                let s = DateiSortierung(kriterium: k, aufsteigend: auf)
                XCTAssertEqual(DateiSortierung(rohwert: s.rohwert), s, s.rohwert)
            }
        }
        for kaputt in ["", "name", "name-hoch", "farbe-auf", "name-auf-x"] {
            XCTAssertNil(DateiSortierung(rohwert: kaputt), kaputt)
        }
    }

    // MARK: Texte

    func testObjekte() {
        XCTAssertEqual(DateiAnzeige.objekte(0), "0 Objekte")
        XCTAssertEqual(DateiAnzeige.objekte(1), "1 Objekt")
        XCTAssertEqual(DateiAnzeige.objekte(12), "12 Objekte")
        XCTAssertEqual(DateiAnzeige.synchron, "Mit PC synchronisiert")
        XCTAssertEqual(DateiAnzeige.getrennt, "PC nicht erreichbar")
    }

    func testZeilenTexte() {
        let d = datei("a.pdf", groesse: 482_000, tag: 25)
        let l = DateiAnzeige.listenUntertitel(d)
        XCTAssertTrue(l.contains(" – "), l)
        XCTAssertTrue(l.contains("2026"), l)
        XCTAssertTrue(l.hasSuffix("KB"), l)
        var o = datei("Büro", ordner: true, tag: 25)
        XCTAssertFalse(DateiAnzeige.listenUntertitel(o).contains("Objekt"), "ohne anzahl keine Zahl erfinden")
        o.anzahl = 12
        XCTAssertTrue(DateiAnzeige.listenUntertitel(o).hasSuffix(" – 12 Objekte"), DateiAnzeige.listenUntertitel(o))
        XCTAssertEqual(DateiAnzeige.rasterZeilen(o), ["12 Objekte"])
        XCTAssertEqual(DateiAnzeige.rasterZeilen(datei("x", ordner: true)), [])
        XCTAssertEqual(DateiAnzeige.rasterZeilen(d).count, 2)
        XCTAssertEqual(DateiAnzeige.ort([]), "Dateien")
        XCTAssertEqual(DateiAnzeige.ort(["Büro", "2026"]), "Büro › 2026")
    }

    func testVorschauNurFuerWasDerPCKann() {
        for n in ["a.pdf", "A.PDF", "x.jpg", "x.JPEG", "x.heic", "v.mp4", "v.MOV", "v.webm"] { XCTAssertTrue(DateiAnzeige.hatVorschau(name: n), n) }
        for n in ["a.docx", "a.txt", "a", "a.zip", "a.mp3", "pdf"] { XCTAssertFalse(DateiAnzeige.hatVorschau(name: n), n) }
    }

    // MARK: Suche (gleiche Regeln wie der Dienst)

    func testSucheNormalisiertWieDerDienst() {
        XCTAssertEqual(DateiSuche.normalisiere("Überweisung STRAßE Öl Ärger"), "ueberweisung strasse oel aerger")
        XCTAssertEqual(DateiSuche.normalisiere("Mu\u{0308}nchen"), "muenchen", "zerlegtes ü (Mac)")
        XCTAssertEqual(DateiSuche.woerter("  Rechnung   März "), ["rechnung", "maerz"])
        XCTAssertTrue(DateiSuche.passt(name: "Rechnung März.pdf", woerter: DateiSuche.woerter("maerz rechnung")))
        XCTAssertTrue(DateiSuche.passt(name: "Überweisung.pdf", woerter: DateiSuche.woerter("ueberweisung")))
        XCTAssertFalse(DateiSuche.passt(name: "Rechnung März.pdf", woerter: DateiSuche.woerter("rechnung april")))
        XCTAssertFalse(DateiSuche.passt(name: "x", woerter: []), "leere Suche findet nichts")
    }

    func testTrefferKenntSeinenOrdner() {
        let t = SuchTreffer(pfad: "Büro/2026/a.pdf", name: "a.pdf", ordner: false, groesse: 5, geaendert: "2026-10-25T10:00:00.000Z")
        XCTAssertEqual(t.uebergeordnet, ["Büro", "2026"])
        XCTAssertEqual(t.id, "Büro/2026/a.pdf")
        XCTAssertEqual(t.info.name, "a.pdf")
        XCTAssertEqual(SuchTreffer(pfad: "x", name: "x", ordner: true, groesse: 0, geaendert: "").uebergeordnet, [])
    }
}
