import Synchronization
import XCTest
@testable import Heimherz

/// Merkt die Anfragen an die Leck-Attrappe.
final class LeckAufzeichnung: Sendable {
    private let liste = Mutex<[URLRequest]>([])
    func merke(_ r: URLRequest) { liste.withLock { $0.append(r) } }
    var anfragen: [URLRequest] { liste.withLock { $0 } }
}

/// Alle Passwörter hier sind erfunden. Die Hashes sind mit `printf 'wort' | sha1sum` gerechnet.
enum LeckTestDaten {
    static let pwA = "erfunden"            // 75F68 | 160BC0C4782531DA9195E00007C243C44C9
    static let suffixA = "160BC0C4782531DA9195E00007C243C44C9"
    static let pwB = "zweitesGeheimnis"    // BF981 | 85C0385798BC5BCAD952183DEF7B402B9C8
    static let suffixB = "85C0385798BC5BCAD952183DEF7B402B9C8"
    static let stempel = "2026-10-01T10:00:00.000Z"

    static func eintrag(_ id: String, _ pw: String, geaendert: String = stempel) -> Eintrag {
        Eintrag(id: id, name: id, benutzer: "mia", passwort: pw, urls: ["https://\(id).example.org"], geaendert: geaendert)
    }

    /// Eine Attrappe von Pwned Passwords: A steht im Leck (Anzahl 5), B nur als Füllzeile mit Anzahl 0. Dazu Füllzeilen wie mit `Add-Padding`.
    static func attrappe(_ aufzeichnung: LeckAufzeichnung, status: Int = 200, fehler: URLError.Code? = nil) -> LeckAbfrage {
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            aufzeichnung.merke(r)
            if let fehler { return .fehler(fehler) }
            let vorwahl = r.url?.lastPathComponent ?? ""
            var zeilen = ["0000000000000000000000000000000AAAA:0", "1111111111111111111111111111111BBBB:0"]
            if vorwahl == "75F68" { zeilen.append("\(suffixA):5") }
            if vorwahl == "BF981" { zeilen.append("\(suffixB):0") }
            return FakeNetz.Antwort(status: status, koerper: Data(zeilen.joined(separator: "\r\n").utf8))
        }
        return LeckAbfrage(sitzung: sitzung, basis: basis)
    }
}

final class LeckPruefungTests: XCTestCase {
    func testSha1MitBekanntenWerten() {
        XCTAssertEqual(LeckPruefung.sha1("password"), "5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8")
        XCTAssertEqual(LeckPruefung.sha1(LeckTestDaten.pwA), "75F68" + LeckTestDaten.suffixA)
        XCTAssertEqual(LeckPruefung.sha1(LeckTestDaten.pwB), "BF981" + LeckTestDaten.suffixB)
    }

    func testAntwortZeilenMitFuellungUndZeilenenden() {
        let text = "AAA:0\r\nbbb:3\r\nCCC:12\nDDD:x\n:5\nEEE\n"
        XCTAssertEqual(LeckAbfrage.lese(text), ["BBB", "CCC"], "Anzahl 0 ist Füllung, kaputte Zeilen zählen nicht, Suffixe werden groß")
    }

    func testNurFuenfZeichenGehenRausUndVerglichenWirdHier() async {
        let auf = LeckAufzeichnung()
        let lauf = await LeckPruefung.pruefe([(id: "a", passwort: LeckTestDaten.pwA), (id: "b", passwort: LeckTestDaten.pwB)], abfrage: LeckTestDaten.attrappe(auf))
        XCTAssertEqual(lauf.ergebnisse, ["a": true, "b": false], "b steht nur als Füllzeile (Anzahl 0) da und zählt nicht")
        XCTAssertTrue(lauf.vollstaendig)
        let anfragen = auf.anfragen
        XCTAssertEqual(anfragen.count, 2)
        for r in anfragen {
            let url = r.url?.absoluteString ?? ""
            XCTAssertEqual(r.url?.lastPathComponent.count, 5, "genau 5 Zeichen")
            XCTAssertEqual(r.url?.deletingLastPathComponent().lastPathComponent, "range")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Add-Padding"), "true")
            XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"), "nie ein Token mitschicken")
            XCTAssertEqual(r.httpMethod, "GET")
            XCTAssertNil(r.httpBody)
            for geheim in [LeckTestDaten.suffixA, LeckTestDaten.suffixB, LeckTestDaten.pwA, LeckTestDaten.pwB] {
                XCTAssertFalse(url.localizedCaseInsensitiveContains(geheim), "weder Passwort noch Rest des Hashes in der Adresse")
            }
        }
    }

    func testGleicherAnfangEineAnfrage() async {
        let auf = LeckAufzeichnung()
        let lauf = await LeckPruefung.pruefe([(id: "a", passwort: LeckTestDaten.pwA), (id: "c", passwort: LeckTestDaten.pwA)], abfrage: LeckTestDaten.attrappe(auf))
        XCTAssertEqual(lauf.ergebnisse, ["a": true, "c": true])
        XCTAssertEqual(auf.anfragen.count, 1)
    }

    func testKeinNetzGibtNichtsZurueckUndIstUnvollstaendig() async {
        let auf = LeckAufzeichnung()
        let lauf = await LeckPruefung.pruefe([(id: "a", passwort: LeckTestDaten.pwA), (id: "b", passwort: LeckTestDaten.pwB)],
                                             abfrage: LeckTestDaten.attrappe(auf, fehler: .notConnectedToInternet))
        XCTAssertEqual(lauf, LeckPruefung.Lauf(ergebnisse: [:], vollstaendig: false))
        XCTAssertEqual(auf.anfragen.count, 1, "beim ersten Fehler ist Schluss")
    }

    func testFehlerStatusSchreibtNichts() async {
        let lauf = await LeckPruefung.pruefe([(id: "a", passwort: LeckTestDaten.pwA)], abfrage: LeckTestDaten.attrappe(LeckAufzeichnung(), status: 503))
        XCTAssertEqual(lauf, LeckPruefung.Lauf(ergebnisse: [:], vollstaendig: false))
    }

    func testFaelligKeinStandNeuUndGeaendertesUndNachEinemTag() {
        let jetzt = Date(timeIntervalSince1970: 1_792_886_400)
        let a = LeckTestDaten.eintrag("a", "pw1"), b = LeckTestDaten.eintrag("b", "pw2")
        let notiz = Eintrag(id: "n", art: Eintrag.artNotiz, name: "N", passwort: "x")
        var weg = LeckTestDaten.eintrag("w", "pw3"); weg.geloescht = true
        let leer = LeckTestDaten.eintrag("l", "")
        let alle = [a, b, notiz, weg, leer]
        let aktuell = ["a": LeckStand(geaendert: a.geaendert, gefunden: false), "b": LeckStand(geaendert: b.geaendert, gefunden: true)]

        var f = LeckPruefung.faellig(alle, staende: aktuell, letzterLauf: jetzt.addingTimeInterval(-3_600), jetzt: jetzt)
        XCTAssertEqual(f.eintraege.map(\.id), [], "alles geprüft und weniger als ein Tag her")
        XCTAssertFalse(f.alle)

        var b2 = b
        b2.geaendert = "2026-10-02T10:00:00.000Z"
        f = LeckPruefung.faellig([a, b2], staende: aktuell, letzterLauf: jetzt.addingTimeInterval(-3_600), jetzt: jetzt)
        XCTAssertEqual(f.eintraege.map(\.id), ["b"], "geänderter Eintrag wird neu geprüft")

        f = LeckPruefung.faellig(alle, staende: [:], letzterLauf: jetzt.addingTimeInterval(-3_600), jetzt: jetzt)
        XCTAssertEqual(f.eintraege.map(\.id), ["a", "b"], "nur lebendige Logins mit Passwort")

        f = LeckPruefung.faellig(alle, staende: aktuell, letzterLauf: jetzt.addingTimeInterval(-86_401), jetzt: jetzt)
        XCTAssertEqual(f.eintraege.map(\.id), ["a", "b"], "nach einem Tag wieder alle")
        XCTAssertTrue(f.alle)

        f = LeckPruefung.faellig(alle, staende: aktuell, letzterLauf: nil, jetzt: jetzt)
        XCTAssertTrue(f.alle, "noch nie geprüft")
    }

    func testTrefferZaehlenNurMitPassendemStandUndLebendig() {
        let a = LeckTestDaten.eintrag("a", "x"), b = LeckTestDaten.eintrag("b", "y")
        var c = LeckTestDaten.eintrag("c", "z"); c.geloescht = true
        var b2 = b
        b2.geaendert = "2026-10-05T10:00:00.000Z"
        let staende = ["a": LeckStand(geaendert: a.geaendert, gefunden: true), "b": LeckStand(geaendert: b.geaendert, gefunden: true), "c": LeckStand(geaendert: c.geaendert, gefunden: true)]
        XCTAssertEqual(LeckPruefung.lecks([a, b, c], staende: staende), ["a", "b"])
        XCTAssertEqual(LeckPruefung.lecks([a, b2, c], staende: staende), ["a"], "Passwort geändert: altes Ergebnis gilt nicht mehr")
    }

    func testSpeicherHaeltNurIdStempelUndErgebnis() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)"))
        let speicher = LeckSpeicher(speicher: suite)
        speicher.staende = ["a": LeckStand(geaendert: LeckTestDaten.stempel, gefunden: true)]
        speicher.letzterLauf = Date(timeIntervalSince1970: 1_000)
        let roh = String(decoding: try XCTUnwrap(suite.data(forKey: "leck.staende")), as: UTF8.self)
        XCTAssertFalse(roh.contains(LeckTestDaten.pwA))
        XCTAssertFalse(roh.contains("75F68"))
        XCTAssertEqual(speicher.staende["a"]?.gefunden, true)
        XCTAssertEqual(speicher.letzterLauf, Date(timeIntervalSince1970: 1_000))
        speicher.vergiss()
        XCTAssertEqual(speicher.staende, [:])
        XCTAssertNil(speicher.letzterLauf)
    }

    func testSicherheitNimmLecksMitUndStelltSieVorn() {
        let a = LeckTestDaten.eintrag("a", "Zr7!kQpL92xw-lang"), b = LeckTestDaten.eintrag("b", "123456")
        let h = PasswortSicherheit.pruefe([a, b], lecks: ["a", "b"])
        XCTAssertEqual(h.map(\.eintragId), ["a", "b"])
        XCTAssertEqual(h[0].gruende, [.datenleck])
        XCTAssertEqual(h[0].text, "In einem Datenleck gefunden")
        XCTAssertEqual(h[1].gruende, [.datenleck, .schwach])
        XCTAssertEqual(PasswortSicherheit.pruefe([a, b]).map(\.eintragId), ["b"], "ohne Lecks wie bisher")
    }

    func testKachelZaehltLecksMitUndGenauSoVieleZeilen() {
        let t = Tresor(eintraege: [LeckTestDaten.eintrag("a", "Zr7!kQpL92xw-lang"), LeckTestDaten.eintrag("b", "Qm8#vLpa27zx-anders")])
        let jetzt = Date(timeIntervalSince1970: 1_792_886_400)
        XCTAssertEqual(PasswoerterLogik.zaehler(in: t, jetzt: jetzt)[.sicherheit], 0)
        XCTAssertEqual(PasswoerterLogik.zaehler(in: t, jetzt: jetzt, lecks: ["a"])[.sicherheit], 1)
        XCTAssertEqual(PasswoerterLogik.eintraege(.sicherheit, in: t, jetzt: jetzt, lecks: ["a"]).map(\.id), ["a"])
    }
}

@MainActor
final class LeckStoreTests: XCTestCase {
    private let k = TestSchluessel.schluessel
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400 + 3_600)

    private struct Aufbau {
        let store: TresorStore
        let suite: UserDefaults
        let einstellungen: GeteilteEinstellungen
        let speicher: LeckSpeicher
        let spotlight: IdentitaetenMerker
        let pc: PCAttrappe
    }

    private func aufbau(eintraege: [Eintrag], abfrage: LeckAbfrage?, an: Bool = true) throws -> Aufbau {
        let pc = PCAttrappe()
        let (sitzung, basis) = FakeNetz.neu { r, b in pc.handle(r, b) }
        let bund = Schluesselbund(speicher: MemorySpeicher())
        try bund.speichereSchluessel(k)
        try bund.speichereGeraet(Geraet(url: basis, token: TestSchluessel.token))
        let ablage = TresorAblage(ordner: try tempOrdner())
        pc.setze(try Umschlag.verschliesse(Tresor(eintraege: eintraege), schluessel: k, rev: 5))
        let umgebung = AppUmgebung(bund: bund, ablage: ablage, sitzung: sitzung, sperreAktiv: false)
        let suite = try XCTUnwrap(UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)"))
        let einstellungen = GeteilteEinstellungen(speicher: suite)
        einstellungen.leckPruefung = an
        let speicher = LeckSpeicher(speicher: suite)
        let spotlight = IdentitaetenMerker()
        let uhr = Uhr(jetzt)
        let store = TresorStore(umgebung: umgebung, identitaeten: { _ in }, spotlight: { spotlight.merke($0) }, einstellungen: einstellungen,
                                leckSpeicher: speicher, leckAbfrage: abfrage, jetzt: { uhr.jetzt }, merker: suite)
        return Aufbau(store: store, suite: suite, einstellungen: einstellungen, speicher: speicher, spotlight: spotlight, pc: pc)
    }

    private func warteAufLecks(_ s: TresorStore) async {
        await s.warteAufLeckPruefung()
        await s.warteAufLeckPruefung()
    }

    func testTrefferErscheinenInLeckIdsUndZaehler() async throws {
        let auf = LeckAufzeichnung()
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA), LeckTestDaten.eintrag("b", LeckTestDaten.pwB)], abfrage: LeckTestDaten.attrappe(auf))
        await a.store.oeffnen()
        await warteAufLecks(a.store)
        XCTAssertEqual(a.store.leckIds, ["a"])
        XCTAssertEqual(a.store.zaehler[.sicherheit], 1, "die Kachel zählt Datenlecks mit")
        XCTAssertEqual(a.speicher.staende["a"]?.gefunden, true)
        XCTAssertEqual(a.speicher.staende["b"]?.gefunden, false)
        XCTAssertNotNil(a.speicher.letzterLauf)
        let roh = String(decoding: a.suite.data(forKey: "leck.staende") ?? Data(), as: UTF8.self)
        XCTAssertFalse(roh.contains(LeckTestDaten.pwA) || roh.contains("75F68"), "weder Passwort noch Hash gespeichert")
        let vorher = auf.anfragen.count
        await a.store.abgleichen()
        await warteAufLecks(a.store)
        XCTAssertEqual(auf.anfragen.count, vorher, "innerhalb eines Tages fragt niemand noch einmal")
    }

    func testEinstellungAusKeineAbfrageKeinTreffer() async throws {
        let auf = LeckAufzeichnung()
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA)], abfrage: LeckTestDaten.attrappe(auf), an: false)
        a.speicher.staende = ["a": LeckStand(geaendert: LeckTestDaten.stempel, gefunden: true)]
        await a.store.oeffnen()
        await warteAufLecks(a.store)
        XCTAssertEqual(auf.anfragen.count, 0)
        XCTAssertEqual(a.store.leckIds, [], "aus: nichts anzeigen, nichts zählen")
        XCTAssertEqual(a.store.zaehler[.sicherheit], 0)
    }

    func testOhneNetzBleibtAllesBeimAlten() async throws {
        let auf = LeckAufzeichnung()
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA)], abfrage: LeckTestDaten.attrappe(auf, fehler: .notConnectedToInternet))
        let alt = ["a": LeckStand(geaendert: LeckTestDaten.stempel, gefunden: true)]
        a.speicher.staende = alt
        a.speicher.letzterLauf = jetzt.addingTimeInterval(-2 * 86_400)
        await a.store.oeffnen()
        await warteAufLecks(a.store)
        XCTAssertGreaterThan(auf.anfragen.count, 0, "nach zwei Tagen wird neu gefragt")
        XCTAssertEqual(a.store.leckIds, ["a"], "das alte Ergebnis bleibt stehen")
        XCTAssertEqual(a.speicher.staende, alt)
        XCTAssertEqual(a.speicher.letzterLauf, jetzt.addingTimeInterval(-2 * 86_400), "der Tagesstempel rückt nicht vor")
    }

    func testGeaenderterEintragWirdSofortNeuGeprueftDerRestNicht() async throws {
        let auf = LeckAufzeichnung()
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA), LeckTestDaten.eintrag("b", LeckTestDaten.pwB)], abfrage: LeckTestDaten.attrappe(auf))
        a.speicher.staende = [
            "a": LeckStand(geaendert: LeckTestDaten.stempel, gefunden: true),
            "b": LeckStand(geaendert: LeckTestDaten.stempel, gefunden: false)
        ]
        a.speicher.letzterLauf = jetzt.addingTimeInterval(-3_600)
        await a.store.oeffnen()
        await warteAufLecks(a.store)
        XCTAssertEqual(auf.anfragen.count, 0, "alles geprüft, weniger als ein Tag")
        XCTAssertEqual(a.store.leckIds, ["a"])
        var neu = try XCTUnwrap(a.store.eintrag("b"))
        neu.passwort = LeckTestDaten.pwA
        await a.store.speichere(neu)
        await warteAufLecks(a.store)
        XCTAssertEqual(auf.anfragen.count, 1, "nur der geänderte Eintrag")
        XCTAssertEqual(a.store.leckIds, ["a", "b"])
    }

    func testSperrenLeertDieAnzeigeNichtDenSpeicherUndSpotlightBleibt() async throws {
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA)], abfrage: LeckTestDaten.attrappe(LeckAufzeichnung()))
        await a.store.oeffnen()
        await warteAufLecks(a.store)
        await a.store.warteAufSpotlight()
        let staende = a.spotlight.staende_.count
        XCTAssertGreaterThan(staende, 0, "nach dem Abgleich wurde der Index gesetzt")
        XCTAssertEqual(a.spotlight.staende_.last?.lebendige.map(\.id), ["a"])
        a.store.sperren()
        XCTAssertEqual(a.store.leckIds, [])
        XCTAssertEqual(a.spotlight.staende_.count, staende, "Sperren fasst den Index nicht an")
        XCTAssertEqual(a.speicher.staende["a"]?.gefunden, true)
        await a.store.oeffnen()
        XCTAssertEqual(a.store.leckIds, ["a"], "beim Öffnen sofort aus dem Speicher, ohne Netz")
    }

    func testSpotlightWirdNachJederAenderungNeuGesetzt() async throws {
        let a = try aufbau(eintraege: [LeckTestDaten.eintrag("a", LeckTestDaten.pwA)], abfrage: nil)
        await a.store.oeffnen()
        await a.store.warteAufSpotlight()
        let vorher = a.spotlight.staende_.count
        await a.store.speichere(LeckTestDaten.eintrag("neu", "egal"))
        await a.store.warteAufSpotlight()
        XCTAssertGreaterThan(a.spotlight.staende_.count, vorher)
        XCTAssertEqual(Set(a.spotlight.staende_.last?.lebendige.map(\.id) ?? []), ["a", "neu"])
    }
}
