import CryptoKit
import Synchronization
import XCTest
@testable import Heimherz

/// Ein Server im Speicher wie der PC-Dienst: eine rev, `If-Match`-Prüfung. `erreichbar = false` simuliert den ausgeschalteten PC.
final class PCAttrappe: Sendable {
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

/// Eine Uhr, die der Test vorrücken kann.
final class Uhr: Sendable {
    private let zeit: Mutex<Date>
    init(_ start: Date) { zeit = Mutex(start) }
    var jetzt: Date { zeit.withLock { $0 } }
    func vor(sekunden: Double) { zeit.withLock { $0 = $0.addingTimeInterval(sekunden) } }
}

/// Merkt, welche Tresore als Identitäten ans System gegangen wären (das echte System gibt es im Test nicht).
final class IdentitaetenMerker: Sendable {
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
        /// Die Uhr des Stores; vorrücken, damit zwei Änderungen nacheinander verschiedene Zeitstempel bekommen (gleicher Stempel: der Grabstein gewinnt).
        let uhr: Uhr
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
        let uhr = Uhr(jetzt)
        let store = TresorStore(umgebung: umgebung, identitaeten: { merker.merke($0) }, jetzt: { uhr.jetzt }, merker: suite)
        return Aufbau(store: store, pc: pc, ablage: ablage, identitaeten: merker, umgebung: umgebung, uhr: uhr)
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
        XCTAssertEqual(stein.passwort, "geheim", "Löschen heißt jetzt Papierkorb: die Felder bleiben, bis endgültig gelöscht wird")
        XCTAssertEqual(stein.name, "Konto")
        await a.store.warteAufIdentitaeten()
        XCTAssertEqual(a.identitaeten.staende_.last?.lebendige.map(\.id), ["b"], "AutoFill bekommt nichts aus dem Papierkorb")
    }

    func testWiederherstellenUndEndgueltigLoeschenGehenAmPCAn() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a"), testEintrag("b"), testEintrag("c")]))
        await a.store.oeffnen()
        let puts = a.pc.puts
        await a.store.loesche(ids: ["a", "b", "c"])
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.pc.puts, puts + 1, "drei Einträge, ein Speichern und ein Abgleich")
        XCTAssertEqual(a.store.eintraege, [])
        XCTAssertEqual(Set(a.store.geloeschte.map(\.id)), ["a", "b", "c"])
        a.uhr.vor(sekunden: 60)
        await a.store.stelleWiederHer(ids: ["a"])
        await a.store.warteAufAbgleich()
        a.uhr.vor(sekunden: 60)
        await a.store.loescheEndgueltig(ids: ["b"])
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.store.eintraege.map(\.id), ["a"])
        XCTAssertEqual(a.store.eintrag("a")?.passwort, "geheim")
        XCTAssertEqual(a.store.eintrag("a")?.geaendert, Zeit.iso(jetzt.addingTimeInterval(60)))
        XCTAssertEqual(a.store.geloeschte.map(\.id), ["c"], "endgültig Gelöschtes erscheint nirgends mehr")
        let amPC = try XCTUnwrap(try a.pc.umschlag?.oeffne(schluessel: k))
        XCTAssertFalse(try XCTUnwrap(amPC.eintraege.first { $0.id == "a" }).geloescht)
        let b = try XCTUnwrap(amPC.eintraege.first { $0.id == "b" })
        XCTAssertTrue(b.geloescht)
        XCTAssertEqual([b.name, b.passwort, b.benutzer], ["", "", ""])
        await a.store.warteAufIdentitaeten()
        XCTAssertEqual(a.identitaeten.staende_.last?.lebendige.map(\.id), ["a"])
    }

    func testCodesBleibenBisZumSperrenGesperrt() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a")]))
        await a.store.oeffnen()
        XCTAssertFalse(a.store.codesFreigegeben)
        a.store.gebeCodesFrei()
        XCTAssertTrue(a.store.codesFreigegeben)
        a.store.sperren()
        XCTAssertFalse(a.store.codesFreigegeben)
    }

    func testOeffnenLeertAlteGrabsteine() async throws {
        let alt = Eintrag(id: "alt", name: "Alt", passwort: "pw", geaendert: Zeit.iso(jetzt.addingTimeInterval(-31 * 86_400)), geloescht: true)
        let a = try aufbau(serverTresor: Tresor(eintraege: [alt, testEintrag("b")]))
        await a.store.oeffnen()
        await a.store.warteAufAbgleich()
        XCTAssertEqual(a.store.geloeschte, [])
        let amPC = try XCTUnwrap(try a.pc.umschlag?.oeffne(schluessel: k))
        XCTAssertEqual(amPC.eintraege.first { $0.id == "alt" }?.passwort, "")
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

    func testEintragAusDerErweiterungGehtBeimSpeichernNichtVerloren() async throws {
        let a = try aufbau(serverTresor: Tresor(eintraege: [testEintrag("a")]))
        await a.store.oeffnen()
        // Die AutoFill-Erweiterung speichert ein neues Passwort im Cache, während die App offen im Speicher liegt
        let dienst = a.umgebung.tresorDienst()
        let imCache = try await dienst.lokal(schluessel: k) ?? Tresor()
        try await dienst.speichereLokal(Tresor(eintraege: imCache.eintraege + [testEintrag("aus-safari")]), schluessel: k)
        a.pc.erreichbar(false)
        await a.store.speichere(testEintrag("b"))
        await a.store.warteAufAbgleich()
        XCTAssertEqual(Set(a.store.eintraege.map(\.id)), ["a", "b", "aus-safari"])
        let lokal = try await dienst.lokal(schluessel: k)
        XCTAssertEqual(Set(lokal?.lebendige.map(\.id) ?? []), ["a", "b", "aus-safari"])
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
