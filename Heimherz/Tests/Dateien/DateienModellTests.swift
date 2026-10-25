import UIKit
import XCTest
@testable import Heimherz

@MainActor
final class DateienModellTests: XCTestCase {
    private func modell(ordner: [String] = [], _ h: @escaping FakeNetz.Handler) -> DateienModell {
        let (sitzung, basis) = FakeNetz.neu(h)
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        return DateienModell(ordner: ordner, istDemo: false) { client }
    }

    private let wurzelListe = #"[{"name":"Scans","ordner":true,"groesse":0,"geaendert":"2026-10-25T10:00:00.000Z"},{"name":"a.pdf","ordner":false,"groesse":12,"geaendert":"2026-10-25T10:00:00.000Z"}]"#

    func testJederOrdnerLaedtSeinenEigenenPfad() async throws {
        let pfade = Kasten<[String]>([])
        let liste = wurzelListe
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            let pfad = URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pfad" }?.value ?? "?"
            pfade.mit { $0.append(pfad) }
            return .json(pfad == "" ? liste : "[]")
        }
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        let wurzel = DateienModell(istDemo: false) { client }
        await wurzel.lade()
        XCTAssertEqual(wurzel.eintraege.map(\.name), ["Scans", "a.pdf"])
        XCTAssertEqual(wurzel.zustand, .bereit)
        XCTAssertEqual(wurzel.pfad, "")
        let unten = DateienModell(ordner: ["Scans", "2026"], istDemo: false) { client }
        XCTAssertEqual(unten.pfad, "Scans/2026")
        await unten.lade()
        XCTAssertEqual(unten.eintraege, [])
        XCTAssertEqual(unten.zustand, .bereit)
        XCTAssertEqual(wurzel.eintraege.count, 2, "die Wurzel behält ihre Liste")
        XCTAssertEqual(pfade.mit { $0 }, ["", "Scans/2026"])
    }

    func testOrdnerTragenAnzahlWennDerDienstSieSchickt() async throws {
        let m = modell { _, _ in .json(#"[{"name":"Büro","ordner":true,"groesse":0,"geaendert":"2026-10-25T10:00:00.000Z","anzahl":12},{"name":"a.pdf","ordner":false,"groesse":12,"geaendert":"2026-10-25T10:00:00.000Z"}]"#) }
        await m.lade()
        XCTAssertEqual(m.eintraege.map(\.anzahl), [12, nil])
    }

    func testOfflineBehaeltDieLetzteListe() async throws {
        let aus = Kasten(false)
        let liste = wurzelListe
        let m = modell { _, _ in aus.mit { $0 } ? .fehler(.notConnectedToInternet) : .json(liste) }
        await m.lade()
        aus.mit { $0 = true }
        await m.lade()
        XCTAssertEqual(m.eintraege.count, 2, "die letzte Liste bleibt sichtbar")
        XCTAssertEqual(m.zustand, .fehler(HeimFehler.nichtErreichbar.nutzerText, offline: true))
    }

    func testFehlerOhneNetzproblemIstNichtOffline() async {
        let m = modell { _, _ in .init(status: 404) }
        await m.lade()
        XCTAssertEqual(m.zustand, .fehler(HeimFehler.nichtGefunden.nutzerText, offline: false))
    }

    func testPapierkorbSendetPfadUndLaedtNeu() async throws {
        let gesendet = Kasten<[String]>([])
        let liste = wurzelListe
        let m = modell { r, body in
            if r.httpMethod == "POST" { gesendet.mit { $0.append(String(decoding: body, as: UTF8.self)) }; return .init(status: 200) }
            return .json(liste)
        }
        await m.lade()
        let ok = await m.inPapierkorb(m.eintraege[1])
        XCTAssertTrue(ok)
        XCTAssertEqual(gesendet.mit { $0 }, [#"{"pfad":"a.pdf"}"#])
        XCTAssertEqual(m.meldung, "„a.pdf“ liegt jetzt im Papierkorb am PC.")
        XCTAssertFalse(m.meldungIstFehler)
        let aus = await m.inPapierkorb(pfad: "Büro/2026/b.pdf", name: "b.pdf")
        XCTAssertTrue(aus)
        let letzter = try XCTUnwrap(gesendet.mit { $0 }.last)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(letzter.utf8)) as? [String: String])
        XCTAssertEqual(json["pfad"], "Büro/2026/b.pdf", "ganzer Pfad auch für Treffer aus anderen Ordnern")
    }

    func testPapierkorbFehlerMeldetKlartext() async {
        let m = modell { r, _ in r.httpMethod == "POST" ? .init(status: 403) : .json("[]") }
        let ok = await m.inPapierkorb(DateiInfo(name: "x", ordner: false, groesse: 1, geaendert: ""))
        XCTAssertFalse(ok)
        XCTAssertEqual(m.meldung, HeimFehler.verboten.nutzerText)
        XCTAssertTrue(m.meldungIstFehler)
    }

    func testHochladenInAktuellenOrdner() async throws {
        let ziele = Kasten<[String]>([])
        let m = modell(ordner: ["Scans"]) { r, _ in
            if r.httpMethod == "PUT" {
                let pfad = URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pfad" }?.value ?? "?"
                ziele.mit { $0.append(pfad) }
                return .json(#"{"name":"x"}"#)
            }
            return .json("[]")
        }
        let u = try tempOrdner().appending(path: "a.txt")
        try Data("hallo".utf8).write(to: u)
        await m.hochladen([(u, "a.txt"), (u, "b.txt")])
        XCTAssertEqual(ziele.mit { $0 }, ["Scans/a.txt", "Scans/b.txt"])
        XCTAssertEqual(m.meldung, "2 Dateien hochgeladen.")
        XCTAssertEqual(m.uebertragungen, 0)
    }

    func testHochladenNetzFehlerBrichtAbUndMeldet() async throws {
        let m = modell { r, _ in r.httpMethod == "PUT" ? .fehler(.notConnectedToInternet) : .json("[]") }
        let u = try tempOrdner().appending(path: "a.txt")
        try Data("x".utf8).write(to: u)
        await m.hochladen([(u, "a.txt"), (u, "b.txt")])
        XCTAssertEqual(m.meldung, HeimFehler.nichtErreichbar.nutzerText)
        XCTAssertTrue(m.meldungIstFehler)
    }

    func testLadenLegtDateiMitOriginalnamenInDenCache() async throws {
        let m = modell { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/datei")
            return .init(status: 200, koerper: Data("PDF!".utf8))
        }
        let url = try await m.laden(DateiInfo(name: "Vertrag.pdf", ordner: false, groesse: 4, geaendert: ""))
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "Vertrag.pdf")
        XCTAssertEqual(try Data(contentsOf: url), Data("PDF!".utf8))
    }

    func testDemoRuehrtDasNetzNichtAn() async {
        let m = DateienModell(istDemo: true) { throw HeimFehler.nichtGekoppelt }
        XCTAssertFalse(m.eintraege.isEmpty)
        let vorher = m.eintraege
        await m.lade()
        XCTAssertEqual(m.eintraege, vorher)
        XCTAssertEqual(m.zustand, .bereit)
        XCTAssertFalse(DateienModell(ordner: ["Büro"], istDemo: true) { throw HeimFehler.nichtGekoppelt }.eintraege.isEmpty)
        let ok = await m.inPapierkorb(m.eintraege[0])
        XCTAssertFalse(ok)
    }
}

private func abfrageWerte(_ r: URLRequest) -> [String: String] {
    let items = URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
}

@MainActor
final class DateienSucheModellTests: XCTestCase {
    private func suche(entprellung: Duration = .milliseconds(5), _ h: @escaping FakeNetz.Handler) -> DateienSucheModell {
        let (sitzung, basis) = FakeNetz.neu(h)
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        return DateienSucheModell(entprellung: entprellung) { client }
    }

    private let treffer = #"[{"pfad":"Büro/Rechnung.pdf","name":"Rechnung.pdf","ordner":false,"groesse":12,"geaendert":"2026-10-25T10:00:00.000Z"}]"#

    func testTippenWirdEntprelltNurDieLetzteAnfrageGeht() async {
        let anfragen = Kasten<[[String: String]]>([])
        let json = treffer
        let m = suche(entprellung: .milliseconds(50)) { r, _ in
            anfragen.mit { $0.append(abfrageWerte(r)) }
            return .json(json)
        }
        m.suche(text: "r", pfad: "")
        m.suche(text: "re", pfad: "")
        m.suche(text: "rechnung", pfad: "Büro")
        XCTAssertEqual(m.zustand, .laedt)
        await m.warteAufEnde()
        XCTAssertEqual(anfragen.mit { $0 }, [["q": "rechnung", "pfad": "Büro"]])
        XCTAssertEqual(m.treffer.map(\.pfad), ["Büro/Rechnung.pdf"])
        XCTAssertEqual(m.zustand, .bereit)
    }

    func testLeereSucheFragtNieUndLeertDieTreffer() async {
        let anzahl = Kasten(0)
        let json = treffer
        let m = suche { _, _ in anzahl.mit { $0 += 1 }; return .json(json) }
        m.suche(text: "rechnung", pfad: "")
        await m.warteAufEnde()
        XCTAssertEqual(m.treffer.count, 1)
        m.suche(text: "   ", pfad: "")
        await m.warteAufEnde()
        XCTAssertEqual(m.treffer, [])
        XCTAssertEqual(m.zustand, .leer)
        XCTAssertEqual(anzahl.mit { $0 }, 1)
    }

    func testFehlerBleibtEinFehlerUndSpaeterErsetztEinNeuerTreffer() async {
        let aus = Kasten(true)
        let json = treffer
        let m = suche { _, _ in aus.mit { $0 } ? .fehler(.notConnectedToInternet) : .json(json) }
        m.suche(text: "a", pfad: "")
        await m.warteAufEnde()
        XCTAssertEqual(m.zustand, .fehler(HeimFehler.nichtErreichbar.nutzerText))
        aus.mit { $0 = false }
        m.wiederhole()
        await m.warteAufEnde()
        XCTAssertEqual(m.zustand, .bereit)
        XCTAssertEqual(m.treffer.count, 1)
    }

    func testAbbruchIstKeinFehler() {
        XCTAssertTrue(DateienModell.istAbbruch(CancellationError()))
        XCTAssertTrue(DateienModell.istAbbruch(HeimFehler.abgebrochen))
        XCTAssertFalse(DateienModell.istAbbruch(HeimFehler.nichtErreichbar))
        XCTAssertFalse(DateienModell.istAbbruch(URLError(.notConnectedToInternet)))
    }

    func testDemoSuchtInDerDemoListeOhneNetz() async {
        let m = DateienSucheModell(demo: DateienDemo.treffer) { throw HeimFehler.nichtGekoppelt }
        m.suche(text: "RECHNUNG", pfad: "")
        XCTAssertEqual(m.zustand, .bereit)
        XCTAssertTrue(m.treffer.contains { $0.name == "Rechnung Strom Oktober.pdf" })
        XCTAssertTrue(m.treffer.contains { $0.pfad == "Büro/Rechnung Internet.pdf" })
        m.suche(text: "rechnung", pfad: "Büro")
        XCTAssertTrue(m.treffer.allSatisfy { $0.pfad.hasPrefix("Büro/") })
        m.suche(text: "gibt es nicht", pfad: "")
        XCTAssertEqual(m.treffer, [])
        XCTAssertEqual(m.zustand, .bereit)
    }
}

@MainActor
final class DateiVorschauLaderTests: XCTestCase {
    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func testLaedtEinmalUndMerktDasBild() async {
        let aufrufe = Kasten(0)
        let daten = jpeg()
        let l = DateiVorschauLader { _, _ in aufrufe.mit { $0 += 1 }; return daten }
        let a = await l.lade(pfad: "a.pdf", schluessel: "k1", px: 120)
        let b = await l.lade(pfad: "a.pdf", schluessel: "k1", px: 120)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotNil(l.bild(schluessel: "k1"))
        XCTAssertEqual(aufrufe.mit { $0 }, 1)
    }

    func testKeinBildVomPCWirdNichtNochEinmalGefragtEinNetzfehlerSchon() async {
        let aufrufe = Kasten(0)
        let l = DateiVorschauLader { _, _ in aufrufe.mit { $0 += 1 }; return nil }
        let a = await l.lade(pfad: "a.pdf", schluessel: "k", px: 120)
        _ = await l.lade(pfad: "a.pdf", schluessel: "k", px: 120)
        XCTAssertNil(a)
        XCTAssertEqual(aufrufe.mit { $0 }, 1, "404 gilt für diese Sitzung")
        let n = Kasten(0)
        let aus = DateiVorschauLader { _, _ in n.mit { $0 += 1 }; throw HeimFehler.nichtErreichbar }
        _ = await aus.lade(pfad: "b.pdf", schluessel: "k2", px: 120)
        _ = await aus.lade(pfad: "b.pdf", schluessel: "k2", px: 120)
        XCTAssertEqual(n.mit { $0 }, 2, "bei Netzfehler beim nächsten Erscheinen wieder versuchen")
    }

    func testOhneVerbindungBleibtEsBeimSymbol() async {
        let l = DateiVorschauLader()
        let b = await l.lade(pfad: "a.pdf", schluessel: "k", px: 120)
        XCTAssertNil(b)
    }

    func testHoechstensParallelGleichzeitig() async {
        let aktiv = Kasten((jetzt: 0, hoechstens: 0))
        let daten = jpeg()
        let l = DateiVorschauLader(holen: { _, _ in
            aktiv.mit { $0.jetzt += 1; $0.hoechstens = max($0.hoechstens, $0.jetzt) }
            try? await Task.sleep(for: .milliseconds(30))
            aktiv.mit { $0.jetzt -= 1 }
            return daten
        }, parallel: 2)
        let aufgaben = (0..<6).map { i in
            Task { _ = await l.lade(pfad: "p\(i)", schluessel: "k\(i)", px: 120) }
        }
        for a in aufgaben { await a.value }
        XCTAssertEqual(aktiv.mit { $0.hoechstens }, 2)
        XCTAssertEqual(aktiv.mit { $0.jetzt }, 0)
    }

    func testDemoBilderSindEchteJPEGs() throws {
        for pfad in ["Urlaub Strand.jpg", "Mietvertrag.pdf"] {
            let daten = try XCTUnwrap(DateiVorschauLader.demoBild(pfad: pfad, px: 120))
            XCTAssertNotNil(UIImage(data: daten), pfad)
        }
    }
}
