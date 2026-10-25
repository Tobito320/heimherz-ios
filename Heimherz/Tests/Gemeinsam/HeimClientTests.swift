import XCTest
@testable import Heimherz

final class HeimClientTests: XCTestCase {
    private let umschlag = Umschlag(v: 1, rev: 4, nonce: Data(count: 12).base64EncodedString(), daten: Data(count: 32).base64EncodedString())

    private func umschlagJSON(_ u: Umschlag) throws -> String {
        String(decoding: try JSONEncoder().encode(u), as: UTF8.self)
    }

    private func client(_ h: @escaping FakeNetz.Handler) -> HeimClient {
        let (sitzung, basis) = FakeNetz.neu(h)
        return HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
    }

    func testJedeAnfrageTraegtDasToken() async throws {
        let c = client { r, _ in
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer \(TestSchluessel.token)")
            return .json(#"{"version":"0.1.0","rev":2,"fotos":5}"#)
        }
        let s = try await c.status()
        XCTAssertEqual(s, ServerStatus(version: "0.1.0", rev: 2, fotos: 5, belegt: nil, frei: nil))
    }

    func testStatusFehlerWerdenZuDeutschenFehlern() async throws {
        for (status, erwartet) in [(401, HeimFehler.nichtBerechtigt), (403, .verboten), (404, .nichtGefunden), (413, .zuGross), (507, .speicherVoll), (500, .serverFehler(500)), (418, .abgelehnt(418))] {
            let c = client { _, _ in .init(status: status) }
            do { _ = try await c.status(); XCTFail("sollte scheitern") } catch { XCTAssertEqual(error as? HeimFehler, erwartet) }
        }
        XCTAssertFalse(HeimFehler.nichtBerechtigt.nutzerText.isEmpty)
    }

    func testNetzFehler() async throws {
        for (code, erwartet) in [(URLError.Code.notConnectedToInternet, HeimFehler.nichtErreichbar), (.timedOut, .zeitueberschreitung)] {
            let c = client { _, _ in .fehler(code) }
            do { _ = try await c.status(); XCTFail("sollte scheitern") } catch { XCTAssertEqual(error as? HeimFehler, erwartet) }
            XCTAssertTrue(erwartet.istNetzproblem)
        }
    }

    func testTresorHolenLeerUndVoll() async throws {
        let leer = client { _, _ in .init(status: 404) }
        let kein = try await leer.tresorHolen()
        XCTAssertNil(kein)
        let json = try umschlagJSON(umschlag)
        let voll = client { _, _ in .json(json) }
        let u = try await voll.tresorHolen()
        XCTAssertEqual(u, umschlag)
        let kaputt = client { _, _ in .json(#"{"v":1,"rev":1,"nonce":"AA==","daten":"AA=="}"#) }
        do { _ = try await kaputt.tresorHolen(); XCTFail("Form falsch") } catch { XCTAssertEqual(error as? HeimFehler, .ungueltigeAntwort) }
    }

    func testTresorSchreibenSendetIfMatchAuchBeiNull() async throws {
        let json = try umschlagJSON(umschlag)
        let erwartet = umschlag
        let c = client { r, body in
            XCTAssertEqual(r.httpMethod, "PUT")
            XCTAssertEqual(r.url?.path, "/v1/tresor")
            XCTAssertEqual(r.value(forHTTPHeaderField: "If-Match"), "0")
            XCTAssertEqual(try? JSONDecoder().decode(Umschlag.self, from: body), erwartet)
            return .json(json)
        }
        let e = try await c.tresorSchreiben(umschlag, ifMatch: 0)
        XCTAssertEqual(e, .gespeichert(umschlag))
    }

    func testTresorSchreiben409LiefertDenAktuellenUmschlag() async throws {
        let json = try umschlagJSON(umschlag)
        let mit = client { _, _ in .json(json, status: 409) }
        let e1 = try await mit.tresorSchreiben(umschlag, ifMatch: 1)
        XCTAssertEqual(e1, .konflikt(aktuell: umschlag))
        let ohne = client { _, _ in .init(status: 409) }
        let e2 = try await ohne.tresorSchreiben(umschlag, ifMatch: 1)
        XCTAssertEqual(e2, .konflikt(aktuell: nil))
        let zuGross = client { _, _ in .init(status: 413) }
        do { _ = try await zuGross.tresorSchreiben(umschlag, ifMatch: 1); XCTFail("413") } catch { XCTAssertEqual(error as? HeimFehler, .zuGross) }
    }

    func testFotosBekannt() async throws {
        let c = client { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/fotos/bekannt")
            return .json(#"[{"kennung":"abc","ressource":"foto","groesse":123},{"kennung":"abc","ressource":"video","groesse":99999999999}]"#)
        }
        let liste = try await c.fotosBekannt()
        XCTAssertEqual(liste, [BekanntesFoto(kennung: "abc", ressource: "foto", groesse: 123), BekanntesFoto(kennung: "abc", ressource: "video", groesse: 99_999_999_999)])
    }

    func testFotoHochladenAnfrage() throws {
        let c = HeimClient(basis: try XCTUnwrap(URL(string: "https://pc.example")), token: "tok")
        let datum = Date(timeIntervalSince1970: 1_792_886_400.25)
        let r = try c.fotoHochladenAnfrage(kennung: "Ab_-9", ressource: "foto", aufnahme: datum, dateiname: "IMG 0001 ü&+.HEIC")
        XCTAssertEqual(r.httpMethod, "PUT")
        XCTAssertEqual(r.url?.absoluteString, "https://pc.example/v1/fotos/Ab_-9/foto")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Aufnahme"), "2026-10-25T00:00:00.250Z")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Dateiname"), "IMG%200001%20%C3%BC%26%2B.HEIC")
        for schlecht in ["", "a/b", "..", "a b", String(repeating: "a", count: 129), "ü"] {
            XCTAssertThrowsError(try c.fotoHochladenAnfrage(kennung: schlecht, ressource: "foto", aufnahme: nil, dateiname: "x"), schlecht)
            XCTAssertThrowsError(try c.fotoHochladenAnfrage(kennung: "ok", ressource: schlecht, aufnahme: nil, dateiname: "x"), schlecht)
        }
    }

    func testPfadWirdProzentkodiert() async throws {
        let c = client { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/dateien")
            XCTAssertEqual(URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.percentEncodedQuery, "pfad=a%2Bb%26c%20d%2F%C3%A9.pdf")
            return .json(#"[{"name":"Ordner","ordner":true,"groesse":0,"geaendert":"2026-10-25T00:00:00.000Z"},{"name":"a.pdf","ordner":false,"groesse":42,"geaendert":"2026-10-24T10:00:00.123Z"}]"#)
        }
        let liste = try await c.dateienListe(pfad: "a+b&c d/é.pdf")
        XCTAssertEqual(liste.map(\.name), ["Ordner", "a.pdf"])
        XCTAssertEqual(liste[1].groesse, 42)
        XCTAssertEqual(liste[1].datum, Date(timeIntervalSince1970: 1_792_836_000.123))
    }

    func testBasisMitPfadUndSchraegstrich() throws {
        let c = HeimClient(basis: try XCTUnwrap(URL(string: "https://pc.example/heim/")), token: "t")
        XCTAssertEqual(try c.anfrage("GET", "/v1/status").url?.absoluteString, "https://pc.example/heim/v1/status")
    }

    func testDateiLaden() async throws {
        let ziel = try tempOrdner().appendingPathComponent("a.bin")
        try Data("alt".utf8).write(to: ziel)
        let c = client { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/datei")
            return FakeNetz.Antwort(status: 200, koerper: Data("inhalt".utf8))
        }
        try await c.dateiLaden(pfad: "x/a.bin", nach: ziel)
        XCTAssertEqual(try Data(contentsOf: ziel), Data("inhalt".utf8))
        let fehl = client { _, _ in .init(status: 404) }
        do { try await fehl.dateiLaden(pfad: "nix", nach: ziel); XCTFail("404") } catch { XCTAssertEqual(error as? HeimFehler, .nichtGefunden) }
    }

    func testDateiHochladenGibtDenNamenZurueck() async throws {
        let quelle = try tempOrdner().appendingPathComponent("q.txt")
        try Data("hallo".utf8).write(to: quelle)
        let c = client { r, body in
            XCTAssertEqual(r.httpMethod, "PUT")
            XCTAssertEqual(body, Data("hallo".utf8))
            return .json(#"{"name":"q (2).txt"}"#)
        }
        let name = try await c.dateiHochladen(pfad: "q.txt", von: quelle)
        XCTAssertEqual(name, "q (2).txt")
    }

    func testPapierkorb() async throws {
        let c = client { r, body in
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.url?.path, "/v1/datei/papierkorb")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(try? JSONSerialization.jsonObject(with: body) as? [String: String], ["pfad": "x/y.txt"])
            return .init(status: 200)
        }
        try await c.inPapierkorb(pfad: "x/y.txt")
        let verboten = client { _, _ in .init(status: 403) }
        do { try await verboten.inPapierkorb(pfad: "../x"); XCTFail("403") } catch { XCTAssertEqual(error as? HeimFehler, .verboten) }
    }
}
