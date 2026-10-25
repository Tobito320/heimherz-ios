import CryptoKit
import Synchronization
import XCTest
@testable import Heimherz

/// Ein Server im Speicher wie der PC-Dienst: eine rev, `If-Match`-Prüfung. `erreichbar = false` simuliert den ausgeschalteten PC.
private final class PCAttrappe: Sendable {
    private struct Zustand {
        var umschlag: Umschlag?
        var erreichbar = true
        var puts = 0
        var status = 0   // 0 = normal, sonst dieser HTTP-Status für alles
    }

    private let zustand = Mutex<Zustand>(Zustand())

    var umschlag: Umschlag? { zustand.withLock { $0.umschlag } }
    var puts: Int { zustand.withLock { $0.puts } }
    func setze(_ u: Umschlag?) { zustand.withLock { $0.umschlag = u } }
    func erreichbar(_ wert: Bool) { zustand.withLock { $0.erreichbar = wert } }
    func immerStatus(_ s: Int) { zustand.withLock { $0.status = s } }

    private func json(_ u: Umschlag) -> String {
        String(decoding: (try? JSONEncoder().encode(u)) ?? Data(), as: UTF8.self)
    }

    func handle(_ r: URLRequest, _ body: Data) -> FakeNetz.Antwort {
        let z = zustand.withLock { $0 }
        if !z.erreichbar { return .fehler(.notConnectedToInternet) }
        if z.status != 0 { return .init(status: z.status) }
        if r.httpMethod == "GET" {
            if let u = z.umschlag { return .json(json(u)) }
            return .init(status: 404)
        }
        zustand.withLock { $0.puts += 1 }
        let stand = z.umschlag?.rev ?? 0
        guard let m = r.value(forHTTPHeaderField: "If-Match"), let rev = Int(m), let neu = try? JSONDecoder().decode(Umschlag.self, from: body) else { return .init(status: 428) }
        if rev != stand {
            if let u = z.umschlag { return .json(json(u), status: 409) }
            return .init(status: 409)
        }
        let gespeichert = Umschlag(v: 1, rev: stand + 1, nonce: neu.nonce, daten: neu.daten)
        setze(gespeichert)
        return .json(json(gespeichert))
    }
}

/// Merkt, welche Tresore als Identitäten ans System gegangen wären (das echte System gibt es im Test nicht).
private final class IdentitaetenMerker: Sendable {
    private let staende = Mutex<[Tresor]>([])
    var staende_: [Tresor] { staende.withLock { $0 } }
    func merke(_ t: Tresor) { staende.withLock { $0.append(t) } }
}

@MainActor
final class TresorStoreTests: XCTestCase {
    private let k = TestSchluessel.schluessel
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400 + 3_600)

    private struct Aufbau {
        let store: TresorStore
        let pc: PCAttrappe
        let ablage: TresorAblage
        let identitaeten: IdentitaetenMerker
        let umgebung: AppUmgebung
    }

    private func aufbau(gekoppelt: Bool = true, mitSchluessel: Bool = true, serverTresor: Tresor? = nil, lokalTresor: Tresor? = nil) throws -> Aufbau {
        let pc = PCAttrappe()
        let (sitzung, basis) = FakeNetz.neu { [pc] r, b in pc.handle(r, b) }
        let bund = Schluesselbund(speicher: MemorySpeicher())
        if mitSchluessel { try bund.speichereSchluessel(k) }
        if gekoppelt { try bund.speichereGeraet(Geraet(url: basis, token: TestSchluessel.token)) }
        let ablage = TresorAblage(ordner: try tempOrdner())
        if let s = serverTresor { pc.setze(try Umschlag.verschliesse(s, schluessel: k, rev: 5)) }
        if let l = lokalTresor { try ablage.speichere(Umschlag.verschliesse(l, schluessel: k, rev: 5)) }
        let umgebung = AppUmgebung(bund: bund, ablage: ablage, sitzung: sitzung, sperreAktiv: false)
        let merker = IdentitaetenMerker()
        let suite = UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)") ?? .standard
        let store = TresorStore(umgebung: umgebung, identitaeten: { merker.merke($0) }, jetzt: { [jetzt] in jetzt }, merker: suite)
        return Aufbau(store: store, pc: pc, ablage: ablage, identitaeten: merker, umgebung: umgebung)
    }

    func testOeffnenZeigtLokalenStandUndGleichtMitPCAb() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("server")]), lokalTresor: Tresor(eintraege: [testEintrag("lokal")]))
        await a.store.oeffnen()
        XCTAssertEqual(a.store.zustand, .bereit)
        XCTAssertEqual(Set(a.store.eintraege.map(\.id)), ["server", "lokal"])
        XCTAssertEqual(a.store.zuletzt, jetzt)
        XCTAssertNil(a.store.offlineText)
        XCTAssertNil(a.store.abgleichFehler)
        XCTAssertEqual(a.pc.umschlag?.rev, 6)
        await a.store.warteAufIdentitaeten()
        XCTAssertEqual(Set(a.identitaeten.staende_.last?.lebendige.map(\.id) ?? []), ["server", "lokal"])
    }

    func testPCAusLokalerStandBleibtOfflineHinweisOhneFehler() async throws {
        let a = try aufbau(lokalTresor: Tresor(eintraege: [testEintrag("lokal")]))
        a.pc.erreichbar(false)
        await a.store.oeffnen()
        XCTAssertEqual(a.store.zustand, .bereit)
        XCTAssertEqual(a.store.eintraege.map(\.id), ["lokal"])
        XCTAssertNotNil(a.store.offlineText)
        XCTAssertNil(a.store.abgleichFehler, "offline ist kein Fehler")
        XCTAssertNil(a.store.zuletzt)
    }

    func testNeuerEintragGehtLokalSofortUndDannZumPC() async throws {
        let a = try aufbau()
        await a.store.oeffnen()
        a.pc.erreichbar(false)
        await a.store.speichere(Eintrag(id: "neu", name: "Neu", benutzer: "mia", passwort: "pw", urls: ["https://x.org"]))
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.store.eintrag("neu")?.geaendert, Zeit.iso(jetzt))
        let lokal = try await a.umgebung.tresorDienst().lokal(schluessel: k)
        XCTAssertEqual(lokal?.lebendige.map(\.id), ["neu"], "offline gespeichert, nichts verloren")
        XCTAssertNotNil(a.store.offlineText)
        a.pc.erreichbar(true)
        await a.store.abgleichen()
        XCTAssertNil(a.store.offlineText)
        let amPC = try a.pc.umschlag?.oeffne(schluessel: k)
        XCTAssertEqual(amPC?.lebendige.map(\.id), ["neu"])
    }

    func testLoeschenMachtGrabsteinUndEntferntAusDerAnzeige() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a"), testEintrag("b")]))
        await a.store.oeffnen()
        await a.store.loesche(id: "a")
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.store.eintraege.map(\.id), ["b"])
        let amPC = try XCTUnwrap(try a.pc.umschlag?.oeffne(schluessel: k))
        let stein = try XCTUnwrap(amPC.eintraege.first { $0.id == "a" })
        XCTAssertTrue(stein.geloescht)
        XCTAssertEqual(stein.passwort, "")
        XCTAssertEqual(stein.name, "")
    }

    func testBearbeitenBehaeltUnbekannteFelder() async throws {
        var e = testEintrag("a")
        e.unbekannt = ["zukunft": .text("bleibt")]
        let a = try aufbau(serverTresor: Tresor(eintraege: [e]))
        await a.store.oeffnen()
        var neu = try XCTUnwrap(a.store.eintrag("a"))
        neu.name = "Umbenannt"
        await a.store.speichere(neu)
        await a.store.warteAufAbgleich()
        let amPC = try XCTUnwrap(try a.pc.umschlag?.oeffne(schluessel: k))
        XCTAssertEqual(amPC.eintraege.first?.name, "Umbenannt")
        XCTAssertEqual(amPC.eintraege.first?.unbekannt["zukunft"], .text("bleibt"))
    }

    func testFavoritSetzen() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a")]))
        await a.store.oeffnen()
        await a.store.setzeFavorit(id: "a", true)
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.store.eintrag("a")?.favorit, true)
    }

    func testSperrenLeertKlartextUndSchluessel() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a")]))
        await a.store.oeffnen()
        XCTAssertEqual(a.store.eintraege.count, 1)
        a.store.sperren()
        XCTAssertEqual(a.store.zustand, .leer)
        XCTAssertNil(a.store.tresor)
        XCTAssertEqual(a.store.eintraege.count, 0)
        // Ohne Schlüssel im Speicher passiert bei Änderungen nichts mehr (kein Schreiben ohne Face ID)
        await a.store.speichere(testEintrag("heimlich"))
        XCTAssertNil(a.store.tresor)
        XCTAssertEqual(a.pc.umschlag?.rev, 5)
        // Wieder öffnen holt alles neu
        await a.store.oeffnen()
        XCTAssertEqual(a.store.eintraege.map(\.id), ["a"])
    }

    func testOhneKopplungOeffnetNichts() async throws {
        let a = try aufbau(gekoppelt: false)
        await a.store.oeffnen()
        XCTAssertEqual(a.store.zustand, .leer)
    }

    func testOhneSchluesselZeigtVerstaendlichenFehler() async throws {
        let a = try aufbau(mitSchluessel: false)
        await a.store.oeffnen()
        guard case .fehler(let text) = a.store.zustand else { return XCTFail("\(a.store.zustand)") }
        XCTAssertTrue(text.contains("koppeln"))
    }

    func testPCKenntHandyNichtMehrIstSichtbarerFehlerAberLokalGeht() async throws {
        let a = try aufbau(lokalTresor: Tresor(eintraege: [testEintrag("lokal")]))
        a.pc.immerStatus(401)
        await a.store.oeffnen()
        XCTAssertEqual(a.store.eintraege.map(\.id), ["lokal"])
        XCTAssertEqual(a.store.abgleichFehler, HeimFehler.nichtBerechtigt.nutzerText)
    }

    func testZuletztUeberlebtNeustart() async throws {
        let suite = "heimherz-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let a = try aufbau()
        let s1 = TresorStore(umgebung: a.umgebung, identitaeten: { _ in }, jetzt: { [jetzt] in jetzt }, merker: defaults)
        await s1.oeffnen()
        XCTAssertEqual(s1.zuletzt, jetzt)
        let s2 = TresorStore(umgebung: a.umgebung, identitaeten: { _ in }, jetzt: { Date() }, merker: defaults)
        XCTAssertEqual(try XCTUnwrap(s2.zuletzt).timeIntervalSince1970, jetzt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTextFuerFehler() {
        XCTAssertEqual(TresorStore.text(HeimFehler.nichtErreichbar), HeimFehler.nichtErreichbar.nutzerText)
        XCTAssertEqual(TresorStore.text(TresorFehler.inhaltUngueltig), TresorFehler.inhaltUngueltig.nutzerText)
        XCTAssertEqual(TresorStore.text(SchluesselbundFehler.entsperrenAbgebrochen), "Entsperren abgebrochen.")
    }
}
