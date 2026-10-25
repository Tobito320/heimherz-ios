import XCTest
@testable import Heimherz

@MainActor
final class DateienModellTests: XCTestCase {
    private func modell(_ h: @escaping FakeNetz.Handler) -> DateienModell {
        let (sitzung, basis) = FakeNetz.neu(h)
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        return DateienModell(istDemo: false) { client }
    }

    private let wurzelListe = #"[{"name":"Scans","ordner":true,"groesse":0,"geaendert":"2026-10-25T10:00:00.000Z"},{"name":"a.pdf","ordner":false,"groesse":12,"geaendert":"2026-10-25T10:00:00.000Z"}]"#

    func testListeNavigationUndZurueck() async throws {
        let pfade = Kasten<[String]>([])
        let liste = wurzelListe
        let m = modell { r, _ in
            let pfad = URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pfad" }?.value ?? "?"
            pfade.mit { $0.append(pfad) }
            return .json(pfad == "" ? liste : "[]")
        }
        await m.lade()
        XCTAssertEqual(m.eintraege.map(\.name), ["Scans", "a.pdf"])
        XCTAssertEqual(m.zustand, .bereit)
        await m.oeffne("Scans")
        XCTAssertEqual(m.ordner, ["Scans"])
        XCTAssertEqual(m.eintraege, [])
        await m.geheZu(tiefe: 0)
        XCTAssertEqual(m.ordner, [])
        XCTAssertEqual(m.eintraege.count, 2)
        XCTAssertEqual(pfade.mit { $0 }, ["", "Scans", ""])
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
        let m = modell { r, _ in
            if r.httpMethod == "PUT" {
                let pfad = URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pfad" }?.value ?? "?"
                ziele.mit { $0.append(pfad) }
                return .json(#"{"name":"x"}"#)
            }
            return .json("[]")
        }
        await m.oeffne("Scans")
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
        await m.lade()
        await m.oeffne("Dokumente")
        XCTAssertEqual(m.ordner, [])
        XCTAssertEqual(m.zustand, .bereit)
    }
}
