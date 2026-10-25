import CryptoKit
import Synchronization
import XCTest
@testable import Heimherz

/// Ein Server im Speicher: eine rev, ein Umschlag, `If-Match`-Prüfung wie der PC-Dienst. `vorPut` darf den Zustand ändern (zweites Gerät).
private final class FakeServer: Sendable {
    private struct Zustand {
        var umschlag: Umschlag?
        var puts = 0
        var vorPut: (@Sendable (FakeServer) -> Void)?
    }

    private let zustand = Mutex<Zustand>(Zustand())

    var umschlag: Umschlag? { zustand.withLock { $0.umschlag } }
    var puts: Int { zustand.withLock { $0.puts } }
    func setze(_ u: Umschlag?) { zustand.withLock { $0.umschlag = u } }
    func vorPut(_ f: (@Sendable (FakeServer) -> Void)?) { zustand.withLock { $0.vorPut = f } }

    private func json(_ u: Umschlag) -> String {
        String(decoding: (try? JSONEncoder().encode(u)) ?? Data(), as: UTF8.self)
    }

    func handle(_ r: URLRequest, _ body: Data) -> FakeNetz.Antwort {
        if r.httpMethod == "GET" {
            if let u = umschlag { return .json(json(u)) }
            return .init(status: 404)
        }
        let hook = zustand.withLock { z -> (@Sendable (FakeServer) -> Void)? in
            z.puts += 1
            return z.vorPut
        }
        hook?(self)
        let stand = umschlag?.rev ?? 0
        guard let m = r.value(forHTTPHeaderField: "If-Match"), let rev = Int(m), let neu = try? JSONDecoder().decode(Umschlag.self, from: body) else {
            return .init(status: 428)
        }
        if rev != stand {
            if let u = umschlag { return .json(json(u), status: 409) }
            return .init(status: 409)
        }
        let gespeichert = Umschlag(v: 1, rev: stand + 1, nonce: neu.nonce, daten: neu.daten)
        setze(gespeichert)
        return .json(json(gespeichert))
    }
}

final class TresorDienstTests: XCTestCase {
    private let k = TestSchluessel.schluessel
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)

    private func aufbau(_ server: FakeServer, ablage: TresorAblage) -> TresorDienst {
        let (sitzung, basis) = FakeNetz.neu { r, b in server.handle(r, b) }
        return TresorDienst(ablage: ablage, client: HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung), jetzt: { [jetzt] in jetzt })
    }

    private func serverTresor(_ server: FakeServer) throws -> Tresor? {
        try server.umschlag?.oeffne(schluessel: k)
    }

    func testErsterAbgleichLaedtLokalenStandHoch() async throws {
        let server = FakeServer()
        let ablage = TresorAblage(ordner: try tempOrdner())
        let dienst = aufbau(server, ablage: ablage)
        let lokal = Tresor(eintraege: [testEintrag("a")])
        let e = try await dienst.abgleichen(lokal: lokal, schluessel: k)
        XCTAssertEqual(e, .abgeglichen(lokal, rev: 1))
        XCTAssertEqual(try serverTresor(server), lokal)
        let lokalGelesen = try await dienst.lokal(schluessel: k)
        XCTAssertEqual(lokalGelesen, lokal)
        XCTAssertEqual(try ablage.lade()?.rev, 1)
    }

    func testFuehrtServerUndLokalZusammen() async throws {
        let server = FakeServer()
        server.setze(try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("server")]), schluessel: k, rev: 5))
        let dienst = aufbau(server, ablage: TresorAblage(ordner: try tempOrdner()))
        let e = try await dienst.abgleichen(lokal: Tresor(eintraege: [testEintrag("lokal")]), schluessel: k)
        guard case .abgeglichen(let t, let rev) = e else { return XCTFail("\(e)") }
        XCTAssertEqual(t.eintraege.map(\.id), ["lokal", "server"])
        XCTAssertEqual(rev, 6)
        XCTAssertEqual(try serverTresor(server), t)
    }

    func testNichtsNeuesSchreibtKeineNeueFassung() async throws {
        let server = FakeServer()
        let t = Tresor(eintraege: [testEintrag("a")])
        server.setze(try Umschlag.verschliesse(t, schluessel: k, rev: 5))
        let dienst = aufbau(server, ablage: TresorAblage(ordner: try tempOrdner()))
        let e = try await dienst.abgleichen(lokal: t, schluessel: k)
        XCTAssertEqual(e, .abgeglichen(t, rev: 5))
        XCTAssertEqual(server.puts, 0)
    }

    func testKonfliktZweiMalDannKlappt() async throws {
        let server = FakeServer()
        server.setze(try Umschlag.verschliesse(Tresor(), schluessel: k, rev: 1))
        let schluessel = k
        // Ein zweites Gerät schreibt bei den ersten beiden PUTs dazwischen
        server.vorPut { s in
            let aktuell = s.umschlag
            let alt = (try? aktuell?.oeffne(schluessel: schluessel)) ?? Tresor()
            let neu = Tresor(eintraege: alt.eintraege + [testEintrag("fremd\(alt.eintraege.count)")])
            if s.puts <= 2, let u = try? Umschlag.verschliesse(neu, schluessel: schluessel, rev: (aktuell?.rev ?? 0) + 1) { s.setze(u) }
        }
        let dienst = aufbau(server, ablage: TresorAblage(ordner: try tempOrdner()))
        let e = try await dienst.abgleichen(lokal: Tresor(eintraege: [testEintrag("meins")]), schluessel: k)
        guard case .abgeglichen(let t, _) = e else { return XCTFail("\(e)") }
        XCTAssertEqual(Set(t.eintraege.map(\.id)), ["meins", "fremd0", "fremd1"])
        XCTAssertEqual(server.puts, 3)
        XCTAssertEqual(try serverTresor(server), t)
    }

    func testNachDreiKonfliktenGibtEsAuf() async throws {
        let server = FakeServer()
        server.setze(try Umschlag.verschliesse(Tresor(), schluessel: k, rev: 1))
        let schluessel = k
        server.vorPut { s in
            let aktuell = s.umschlag
            let alt = (try? aktuell?.oeffne(schluessel: schluessel)) ?? Tresor()
            let neu = Tresor(eintraege: alt.eintraege + [testEintrag("fremd\(s.puts)")])
            if let u = try? Umschlag.verschliesse(neu, schluessel: schluessel, rev: (aktuell?.rev ?? 0) + 1) { s.setze(u) }
        }
        let dienst = aufbau(server, ablage: TresorAblage(ordner: try tempOrdner()))
        do {
            _ = try await dienst.abgleichen(lokal: Tresor(eintraege: [testEintrag("meins")]), schluessel: k)
            XCTFail("sollte nach 3 Versuchen aufgeben")
        } catch {
            XCTAssertEqual(error as? HeimFehler, .zuVieleKonflikte)
        }
        XCTAssertEqual(server.puts, 3)
    }

    func testOhneNetzBleibtLokalUndGehtSpaeterHoch() async throws {
        let ablage = TresorAblage(ordner: try tempOrdner())
        let (sitzungAus, basisAus) = FakeNetz.neu { _, _ in .fehler(.notConnectedToInternet) }
        let aus = TresorDienst(ablage: ablage, client: HeimClient(basis: basisAus, token: "t", sitzung: sitzungAus), jetzt: { [jetzt] in jetzt })
        let lokal = Tresor(eintraege: [testEintrag("offline")])
        let e = try await aus.abgleichen(lokal: lokal, schluessel: k)
        XCTAssertEqual(e, .nurLokal(lokal, grund: .nichtErreichbar))
        let gelesen = try await aus.lokal(schluessel: k)
        XCTAssertEqual(gelesen, lokal)
        // Neuer Start, PC wieder da: der lokale Stand geht hoch
        let server = FakeServer()
        let an = aufbau(server, ablage: ablage)
        let start = try await an.lokal(schluessel: k) ?? Tresor()
        let e2 = try await an.abgleichen(lokal: start, schluessel: k)
        XCTAssertEqual(e2, .abgeglichen(lokal, rev: 1))
    }

    func testNichtGekoppeltArbeitetNurLokal() async throws {
        let dienst = TresorDienst(ablage: TresorAblage(ordner: try tempOrdner()), client: nil)
        let t = Tresor(eintraege: [testEintrag("a")])
        let e = try await dienst.abgleichen(lokal: t, schluessel: k)
        XCTAssertEqual(e, .nurLokal(t, grund: .nichtGekoppelt))
    }

    func testFalscherSchluesselUeberschreibtNie() async throws {
        let server = FakeServer()
        let echt = try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a")]), schluessel: k, rev: 2)
        server.setze(echt)
        let dienst = aufbau(server, ablage: TresorAblage(ordner: try tempOrdner()))
        do {
            _ = try await dienst.abgleichen(lokal: Tresor(), schluessel: SymmetricKey(data: Data(repeating: 7, count: 32)))
            XCTFail("falscher Schlüssel")
        } catch {
            XCTAssertEqual(error as? TresorFehler, .entschluesselungFehlgeschlagen)
        }
        XCTAssertEqual(server.umschlag, echt)
        XCTAssertEqual(server.puts, 0)
    }

    func testNichtBerechtigtWirdNichtVerschluckt() async throws {
        let (sitzung, basis) = FakeNetz.neu { _, _ in .init(status: 401) }
        let dienst = TresorDienst(ablage: TresorAblage(ordner: try tempOrdner()), client: HeimClient(basis: basis, token: "t", sitzung: sitzung))
        do { _ = try await dienst.abgleichen(lokal: Tresor(), schluessel: k); XCTFail("401") } catch { XCTAssertEqual(error as? HeimFehler, .nichtBerechtigt) }
    }
}

final class TresorAblageTests: XCTestCase {
    func testSpeichernUndLadenUndLoeschen() throws {
        let ablage = TresorAblage(ordner: try tempOrdner().appendingPathComponent("neu"))
        XCTAssertNil(try ablage.lade())
        let u = try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a")]), schluessel: TestSchluessel.schluessel, rev: 3)
        try ablage.speichere(u)
        XCTAssertEqual(try ablage.lade(), u)
        let u2 = try Umschlag.verschliesse(Tresor(), schluessel: TestSchluessel.schluessel, rev: 4)
        try ablage.speichere(u2)
        XCTAssertEqual(try ablage.lade(), u2)
        try ablage.loesche()
        XCTAssertNil(try ablage.lade())
    }

    func testAufPlattenDateiStehtKeinKlartext() throws {
        let ablage = TresorAblage(ordner: try tempOrdner())
        try ablage.speichere(Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a", name: "GeheimerName", passwort: "GeheimesPasswort")]), schluessel: TestSchluessel.schluessel))
        let text = String(decoding: try Data(contentsOf: ablage.datei), as: UTF8.self)
        XCTAssertFalse(text.contains("GeheimerName"))
        XCTAssertFalse(text.contains("GeheimesPasswort"))
    }

    func testAppGruppeIstImTestlaufNil() {
        // Ohne Signierung gibt es den Gruppenordner nicht; Tests nehmen darum einen Temp-Ordner.
        XCTAssertNil(TresorAblage.appGruppe())
    }
}

/// M4: App und Erweiterung schreiben dieselbe Datei und dürfen sich nie überschreiben.
final class TresorDienstMischenTests: XCTestCase {
    private let k = TestSchluessel.schluessel
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)

    private func dienst(_ ablage: TresorAblage) -> TresorDienst {
        TresorDienst(ablage: ablage, client: nil, jetzt: { [jetzt] in jetzt })
    }

    func testSpeichereLokalMischtDieDateiEin() async throws {
        let ablage = TresorAblage(ordner: try tempOrdner())
        // Die Erweiterung hat "ext" gespeichert, die App kennt nur "app" und weiß nichts davon.
        try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("ext")]), schluessel: k)
        let stand = try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("app")]), schluessel: k)
        XCTAssertEqual(stand.eintraege.map(\.id), ["app", "ext"])
        let gelesen = try await dienst(ablage).lokal(schluessel: k)
        XCTAssertEqual(gelesen, stand)
    }

    func testNeuereAenderungDesAufrufersGewinntTrotzMischen() async throws {
        let ablage = TresorAblage(ordner: try tempOrdner())
        try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("a", passwort: "alt", geaendert: "2026-10-01T10:00:00.000Z")]), schluessel: k)
        let stand = try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("a", passwort: "neu", geaendert: "2026-10-02T10:00:00.000Z")]), schluessel: k)
        XCTAssertEqual(stand.eintraege.first?.passwort, "neu")
    }

    func testRevBleibtUndFalscherSchluesselUeberschreibtNichts() async throws {
        let ablage = TresorAblage(ordner: try tempOrdner())
        let vorher = try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a")]), schluessel: k, rev: 7)
        try ablage.speichere(vorher)
        let fremd = SymmetricKey(data: Data(repeating: 9, count: 32))
        do {
            try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("b")]), schluessel: fremd)
            XCTFail("falscher Schlüssel")
        } catch {
            XCTAssertEqual(error as? TresorFehler, .entschluesselungFehlgeschlagen)
        }
        XCTAssertEqual(try ablage.lade(), vorher)
        try await dienst(ablage).speichereLokal(Tresor(eintraege: [testEintrag("b")]), schluessel: k)
        XCTAssertEqual(try ablage.lade()?.rev, 7)
    }

    func testAbgleichUeberschreibtNichtWasDieErweiterungWaehrenddessenSchrieb() async throws {
        let server = FakeServer()
        let ablage = TresorAblage(ordner: try tempOrdner())
        let (sitzung, basis) = FakeNetz.neu { r, b in server.handle(r, b) }
        let dienst = TresorDienst(ablage: ablage, client: HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung), jetzt: { [jetzt] in jetzt })
        let schluessel = k
        // Während des PUT legt die Erweiterung "ext" in die Datei (hier gleichzeitig und darum von Hand, ohne Zufall).
        server.vorPut { _ in
            let vorhanden = (try? ablage.lade()?.oeffne(schluessel: schluessel)) ?? Tresor()
            let neu = Tresor(eintraege: vorhanden.eintraege + [testEintrag("ext")])
            if let u = try? Umschlag.verschliesse(neu, schluessel: schluessel, rev: 0) { try? ablage.speichere(u) }
        }
        let e = try await dienst.abgleichen(lokal: Tresor(eintraege: [testEintrag("app")]), schluessel: k)
        guard case .abgeglichen(let t, _) = e else { return XCTFail("\(e)") }
        XCTAssertEqual(Set(t.eintraege.map(\.id)), ["app", "ext"], "der Aufrufer bekommt den Stand, der in der Datei liegt")
        let ids = try await self.dienst(ablage).lokal(schluessel: k)?.eintraege.map(\.id)
        XCTAssertEqual(ids?.contains("app"), true)
        XCTAssertEqual(ids?.contains("ext"), true, "der Eintrag der Erweiterung darf nicht fehlen")
    }

    func testUngesendeteZaehltEintraegeNachDemLetztenAbgleich() async throws {
        let server = FakeServer()
        let ablage = TresorAblage(ordner: try tempOrdner())
        let (sitzung, basis) = FakeNetz.neu { r, b in server.handle(r, b) }
        let dienst = TresorDienst(ablage: ablage, client: HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung), jetzt: { [jetzt] in jetzt })
        let alt = testEintrag("alt", geaendert: Zeit.iso(jetzt.addingTimeInterval(-3_600)))
        XCTAssertEqual(ablage.ungesendet(in: Tresor(eintraege: [alt])), 1, "ohne Merker gilt alles als ungesendet")
        _ = try await dienst.abgleichen(lokal: Tresor(eintraege: [alt]), schluessel: k)
        XCTAssertEqual(ablage.ungesendet(in: Tresor(eintraege: [alt])), 0)
        let neu = testEintrag("neu", geaendert: Zeit.iso(jetzt.addingTimeInterval(60)))
        let grab = testEintrag("grab", geaendert: Zeit.iso(jetzt.addingTimeInterval(90)), geloescht: true)
        XCTAssertEqual(ablage.ungesendet(in: Tresor(eintraege: [alt, neu, grab])), 2, "auch Löschungen zählen")
        try ablage.loesche()
        XCTAssertEqual(ablage.ungesendet(in: Tresor(eintraege: [alt])), 1, "der Merker geht mit dem Cache")
    }
}
