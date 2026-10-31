import XCTest
@testable import Heimherz

final class SyncRegelnTests: XCTestCase {
    private let eintrag = SyncEintrag(id: "a1", eltern: "", name: "x.txt", ordner: false, groesse: 3, geaendert: "2026-10-31T10:00:00.000Z", fassung: "1793440800000-3")

    func testFehlerArten() {
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.nichtErreichbar), .serverUnreachable)
        XCTAssertEqual(SyncRegeln.fehlerArt(URLError(.notConnectedToInternet)), .serverUnreachable)
        XCTAssertEqual(SyncRegeln.fehlerArt(URLError(.cancelled)), .abgebrochen)
        XCTAssertEqual(SyncRegeln.fehlerArt(CancellationError()), .abgebrochen)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.nichtGekoppelt), .notAuthenticated)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.nichtGefunden), .noSuchItem)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.speicherVoll), .insufficientQuota)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.abgelehnt(410)), .syncAnchorExpired)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.konflikt), .konflikt)
        XCTAssertEqual(SyncRegeln.fehlerArt(HeimFehler.abgelehnt(500)), .cannotSynchronize)
    }

    func testAlternativeNamen() {
        XCTAssertEqual(SyncRegeln.alternativeNamen(zu: "a.txt", anzahl: 2), ["a (2).txt", "a (3).txt"])
        XCTAssertEqual(SyncRegeln.alternativeNamen(zu: "Ordner", anzahl: 1), ["Ordner (2)"])
        XCTAssertEqual(SyncRegeln.alternativeNamen(zu: "", anzahl: 3), [])
    }

    func testVersionen() {
        XCTAssertEqual(SyncRegeln.fassung(ausVersion: SyncRegeln.inhaltsVersion(eintrag)), "1793440800000-3")
        XCTAssertNil(SyncRegeln.fassung(ausVersion: Data()))
        var umbenannt = eintrag
        umbenannt.name = "y.txt"
        XCTAssertEqual(SyncRegeln.inhaltsVersion(umbenannt), SyncRegeln.inhaltsVersion(eintrag))
        XCTAssertNotEqual(SyncRegeln.metadatenVersion(umbenannt), SyncRegeln.metadatenVersion(eintrag))
    }

    func testDomainAktion() {
        XCTAssertEqual(DomainAktion.bestimme(gekoppelt: true, vorhanden: false), .hinzufuegen)
        XCTAssertEqual(DomainAktion.bestimme(gekoppelt: false, vorhanden: true), .entfernen)
        XCTAssertEqual(DomainAktion.bestimme(gekoppelt: true, vorhanden: true), .nichts)
        XCTAssertEqual(DomainAktion.bestimme(gekoppelt: false, vorhanden: false), .nichts)
        XCTAssertEqual(DomainAktion.anzeigename, "Lumen Cloud")
    }

    func testDatum() {
        XCTAssertEqual(eintrag.datum, Date(timeIntervalSince1970: 1_793_440_800))
    }
}

final class HeimClientSyncTests: XCTestCase {
    private let zeile = #"{"id":"a1","eltern":"","name":"x.txt","ordner":false,"groesse":3,"geaendert":"2026-10-31T10:00:00.000Z","fassung":"1-3"}"#

    private func client(_ h: @escaping FakeNetz.Handler) -> HeimClient {
        let (sitzung, basis) = FakeNetz.neu(h)
        return HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
    }

    func testAenderungenMitAnkerUndKurz() async throws {
        let c = client { r, _ in
            XCTAssertEqual(r.httpMethod, "GET")
            XCTAssertEqual(r.url?.path, "/v1/dateien/aenderungen")
            XCTAssertEqual(r.url?.query, "anker=ab.1&kurz=1")
            return .json(#"{"anker":"ab.2","voll":false,"eintraege":[],"weg":["z"]}"#)
        }
        let a = try await c.syncAenderungen(anker: "ab.1", nurAnker: true)
        XCTAssertEqual(a, SyncAenderungen(anker: "ab.2", voll: false, eintraege: [], weg: ["z"]))
    }

    func testAlterAnkerIst410() async {
        let c = client { _, _ in .json("{}", status: 410) }
        do {
            _ = try await c.syncAenderungen(anker: "alt")
            XCTFail("410 erwartet")
        } catch {
            XCTAssertEqual(SyncRegeln.fehlerArt(error), .syncAnchorExpired)
        }
    }

    func testKinderEintragOrdnerUmbenennenPapierkorb() async throws {
        let c = client { r, b in
            switch r.url?.path {
            case "/v1/dateien/kinder": XCTAssertEqual(r.url?.query, "id=p"); return .json("[\(self.zeile)]")
            case "/v1/dateien/eintrag": return .json(self.zeile)
            case "/v1/dateien/ordner":
                XCTAssertEqual(r.httpMethod, "POST")
                XCTAssertEqual(try? JSONDecoder().decode([String: String].self, from: b), ["eltern": "", "name": "N"])
                return .json(self.zeile)
            case "/v1/dateien/umbenennen":
                XCTAssertEqual(try? JSONDecoder().decode([String: String].self, from: b), ["id": "a1", "name": "y.txt"])
                return .json(self.zeile)
            case "/v1/dateien/papierkorb":
                XCTAssertEqual(try? JSONDecoder().decode([String: String].self, from: b), ["id": "a1", "fassung": "1-3"])
                return .json("{}")
            default: return .json("{}", status: 404)
            }
        }
        let kinder = try await c.syncKinder(id: "p")
        XCTAssertEqual(kinder.map(\.id), ["a1"])
        _ = try await c.syncEintrag(id: "a1")
        _ = try await c.syncOrdner(eltern: "", name: "N")
        _ = try await c.syncUmbenennen(id: "a1", eltern: nil, name: "y.txt")
        try await c.syncPapierkorb(id: "a1", fassung: "1-3")
    }

    func testErsetzenKonfliktUndErfolg() async throws {
        let ordner = try tempOrdner()
        let datei = ordner.appendingPathComponent("q.txt")
        try Data("neu".utf8).write(to: datei)
        let konflikt = client { r, _ in
            XCTAssertEqual(r.httpMethod, "PUT")
            XCTAssertEqual(r.url?.query, "id=a1&fassung=alt")
            return .json(self.zeile, status: 409)
        }
        let e1 = try await konflikt.syncErsetzen(id: "a1", fassung: "alt", von: datei)
        guard case .konflikt(let aktuell) = e1 else { return XCTFail("Konflikt erwartet") }
        XCTAssertEqual(aktuell?.fassung, "1-3")
        let gut = client { _, _ in .json(self.zeile) }
        let e2 = try await gut.syncErsetzen(id: "a1", fassung: "1-3", von: datei)
        guard case .ersetzt(let neu) = e2 else { return XCTFail("ersetzt erwartet") }
        XCTAssertEqual(neu.id, "a1")
    }
}
