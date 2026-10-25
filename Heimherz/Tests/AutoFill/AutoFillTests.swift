import AuthenticationServices
import CryptoKit
import Synchronization
import XCTest
@testable import Heimherz

final class PasswortSpeichernTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)

    private func tresor() -> Tresor {
        Tresor(eintraege: [
            Eintrag(id: "1", name: "Beispiel", benutzer: "Mia", passwort: "alt", urls: ["https://example.org"]),
            Eintrag(id: "2", name: "Notiz", benutzer: "mia", passwort: "x", urls: ["https://example.org"], geloescht: true),
            Eintrag(id: "3", name: "Meine App", benutzer: "mia", passwort: "app", urls: [])
        ])
    }

    func testNeuesKontoBekommtHostAlsUrlUndNamen() {
        guard case .neu(let e) = PasswortSpeichern.plane(in: tresor(), host: "shop.example.com", name: "", benutzer: "tom", passwort: "pw", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.name, "shop.example.com")
        XCTAssertEqual(e.urls, ["https://shop.example.com"])
        XCTAssertEqual(e.benutzer, "tom")
        XCTAssertEqual(e.passwort, "pw")
        XCTAssertEqual(e.geaendert, Zeit.iso(jetzt))
        XCTAssertFalse(e.id.isEmpty)
    }

    func testGleichesPasswortIstSchonDa() {
        XCTAssertEqual(PasswortSpeichern.plane(in: tresor(), host: "example.org", name: "x", benutzer: "mia", passwort: "alt", jetzt: jetzt), .vorhanden,
                       "Benutzer ohne Groß/Klein, Host gleich")
    }

    func testAnderesPasswortAktualisiertDasBestehendeKonto() {
        guard case .aktualisieren(let e) = PasswortSpeichern.plane(in: tresor(), host: "login.example.org", name: "x", benutzer: "MIA", passwort: "neu", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.id, "1")
        XCTAssertEqual(e.passwort, "neu")
        XCTAssertEqual(e.name, "Beispiel", "Name bleibt")
        XCTAssertEqual(e.geaendert, Zeit.iso(jetzt))
    }

    func testGeloeschtesKontoZaehltNichtUndAndereHostsAuch() {
        guard case .neu = PasswortSpeichern.plane(in: tresor(), host: "evilexample.org", name: "x", benutzer: "mia", passwort: "pw", jetzt: jetzt) else { return XCTFail("anderer Host") }
        let nurGrabstein = Tresor(eintraege: [Eintrag(id: "g", name: "", benutzer: "mia", urls: ["https://neu.org"], geloescht: true)])
        guard case .neu = PasswortSpeichern.plane(in: nurGrabstein, host: "neu.org", name: "x", benutzer: "mia", passwort: "pw", jetzt: jetzt) else { return XCTFail("Grabstein") }
    }

    func testAppOhneHostZaehltDerName() {
        XCTAssertEqual(PasswortSpeichern.plane(in: tresor(), host: nil, name: "Meine App", benutzer: "mia", passwort: "app", jetzt: jetzt), .vorhanden)
        guard case .neu(let e) = PasswortSpeichern.plane(in: tresor(), host: nil, name: "Andere App", benutzer: "mia", passwort: "pw", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.urls, [])
        XCTAssertEqual(e.name, "Andere App")
    }

    func testAnwendenBehaeltRestUndErsetztNurDasKonto() {
        let t = tresor()
        let neu = Eintrag(id: "9", name: "N")
        XCTAssertEqual(PasswortSpeichern.anwenden(.neu(neu), auf: t).eintraege.count, 4)
        XCTAssertEqual(PasswortSpeichern.anwenden(.vorhanden, auf: t), t)
        var geaendert = t.eintraege[0]
        geaendert.passwort = "neu"
        XCTAssertEqual(PasswortSpeichern.anwenden(.neu(neu), auf: PasswortSpeichern.anwenden(.neu(neu), auf: t)).eintraege.count, 4, "zweimal anwenden = kein Doppelter")
        let r = PasswortSpeichern.anwenden(.aktualisieren(geaendert), auf: t)
        XCTAssertEqual(r.eintraege.count, 3)
        XCTAssertEqual(r.eintraege[0].passwort, "neu")
        XCTAssertEqual(r.eintraege[2], t.eintraege[2])
    }
}

final class PasswortVerlaufTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)

    func testGenauerHostGehtVorUnterdomain() {
        // Der Unterdomain-Eintrag steht vorn in der Liste, trotzdem soll der mit genau dem Host aktualisiert werden.
        let t = Tresor(eintraege: [
            Eintrag(id: "sub", name: "Sub", benutzer: "mia", passwort: "a", urls: ["https://m.example.org"]),
            Eintrag(id: "genau", name: "Genau", benutzer: "mia", passwort: "b", urls: ["https://example.org"])
        ])
        guard case .aktualisieren(let e) = PasswortSpeichern.plane(in: t, host: "example.org", name: "x", benutzer: "mia", passwort: "neu", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.id, "genau")
        guard case .aktualisieren(let f) = PasswortSpeichern.plane(in: t, host: "m.example.org", name: "x", benutzer: "mia", passwort: "neu", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(f.id, "sub")
    }

    func testAltesPasswortWandertInDenVerlauf() {
        let t = Tresor(eintraege: [Eintrag(id: "1", name: "B", benutzer: "mia", passwort: "p0", urls: ["https://example.org"])])
        guard case .aktualisieren(let e) = PasswortSpeichern.plane(in: t, host: "example.org", name: "x", benutzer: "mia", passwort: "p1", jetzt: jetzt) else { return XCTFail() }
        XCTAssertEqual(e.passwort, "p1")
        XCTAssertEqual(e.unbekannt["passwortVerlauf"], .liste([.objekt(["passwort": .text("p0"), "bis": .text(Zeit.iso(jetzt))])]))
    }

    func testVerlaufHaeltHoechstensFuenfNeuesteVorn() {
        var t = Tresor(eintraege: [Eintrag(id: "1", name: "B", benutzer: "mia", passwort: "p0", urls: ["https://example.org"])])
        for i in 1...7 {
            guard case .aktualisieren(let e) = PasswortSpeichern.plane(in: t, host: "example.org", name: "x", benutzer: "mia", passwort: "p\(i)", jetzt: jetzt.addingTimeInterval(Double(i))) else { return XCTFail("\(i)") }
            t = PasswortSpeichern.anwenden(.aktualisieren(e), auf: t)
        }
        let liste = t.eintraege[0].unbekannt["passwortVerlauf"]?.alsListe ?? []
        XCTAssertEqual(liste.count, PasswortSpeichern.verlaufMax)
        guard case .objekt(let neuester)? = liste.first else { return XCTFail() }
        XCTAssertEqual(neuester["passwort"], .text("p6"), "p7 ist das jetzige Passwort, p6 das zuletzt ersetzte")
        XCTAssertEqual(t.eintraege[0].passwort, "p7")
    }

    func testVerlaufUeberlebtVerschluesselnUndLesen() throws {
        let t = Tresor(eintraege: [Eintrag(id: "1", name: "B", benutzer: "mia", passwort: "p0", urls: ["https://example.org"])])
        guard case .aktualisieren(let e) = PasswortSpeichern.plane(in: t, host: "example.org", name: "x", benutzer: "mia", passwort: "p1", jetzt: jetzt) else { return XCTFail() }
        let neu = PasswortSpeichern.anwenden(.aktualisieren(e), auf: t)
        let zurueck = try Umschlag.verschliesse(neu, schluessel: TestSchluessel.schluessel).oeffne(schluessel: TestSchluessel.schluessel)
        XCTAssertEqual(zurueck.eintraege[0].unbekannt["passwortVerlauf"], e.unbekannt["passwortVerlauf"])
    }

    func testHostHinweisNurBeiUnterdomain() {
        let e = Eintrag(id: "1", name: "B", urls: ["https://example.org"])
        XCTAssertNil(PasswortSpeichern.hostHinweis(fuer: e, anfrageHost: "example.org"))
        XCTAssertNil(PasswortSpeichern.hostHinweis(fuer: e, anfrageHost: nil))
        XCTAssertEqual(PasswortSpeichern.hostHinweis(fuer: e, anfrageHost: "login.example.org"), "Das Konto gehört zu example.org, du bist auf login.example.org.")
    }
}

final class PasswortVorschlaegeTests: XCTestCase {
    func testLaengenGrenzenAusApplesRegeln() {
        let a = PasswortVorschlaege.laengenGrenzen(aus: "required: lower; required: upper; minlength: 10; maxlength: 24; allowed: [-_.]")
        XCTAssertEqual(a.min, 10)
        XCTAssertEqual(a.max, 24)
        let b = PasswortVorschlaege.laengenGrenzen(aus: nil)
        XCTAssertNil(b.min)
        XCTAssertNil(b.max)
        XCTAssertNil(PasswortVorschlaege.laengenGrenzen(aus: "minlength: abc; unsinn").min)
    }

    func testDreiVorschlaegeOhneRegeln() {
        var z = FesterZufall(11)
        let v = PasswortVorschlaege.erzeuge(regeln: [nil, nil], mit: &z)
        XCTAssertEqual(v.map(\.art), [.stark, .alphanumerisch, .wortgruppe])
        XCTAssertEqual(v[0].wert.count, 20)
        XCTAssertTrue(v[1].wert.allSatisfy { $0.isLetter || $0.isNumber })
        XCTAssertTrue(v[2].wert.contains("-"))
    }

    func testLaengeFolgtMinUndMax() {
        var z = FesterZufall(12)
        XCTAssertEqual(PasswortVorschlaege.erzeuge(regeln: ["minlength: 30"], mit: &z)[0].wert.count, 30)
        let kurz = PasswortVorschlaege.erzeuge(regeln: ["maxlength: 12"], mit: &z)
        XCTAssertEqual(kurz[0].wert.count, 12)
        XCTAssertFalse(kurz.contains { $0.art == .wortgruppe }, "die Wortgruppe wäre länger als 12")
        XCTAssertEqual(PasswortVorschlaege.erzeuge(regeln: ["maxlength: 5"], mit: &z), [], "unter 8 Zeichen kann der Generator nichts liefern")
        XCTAssertEqual(PasswortVorschlaege.erzeuge(regeln: [nil, "minlength: 100"], mit: &z)[0].wert.count, 64, "Obergrenze des Generators")
    }
}

/// Schlüsselbund, dessen Schlüssel-Abfrage der Nutzer abbricht (Face ID abgelehnt).
private struct AbbruchSpeicher: KeychainSpeicher {
    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? {
        if konto == Schluesselbund.kontoSchluessel { throw SchluesselbundFehler.entsperrenAbgebrochen }
        return Data("x".utf8)
    }
    func schreiben(_ konto: String, daten: Data, schutz: KeychainSchutz) throws {}
    func loeschen(_ konto: String) throws {}
}

@MainActor
final class AutoFillSitzungTests: XCTestCase {
    private let k = TestSchluessel.schluessel

    private struct Aufbau {
        let sitzung: AutoFillSitzung
        let ablage: TresorAblage
        let pc: PCAttrappe
        let identitaeten: IdentitaetenMerker
    }

    private func aufbau(tresor: Tresor? = nil, mitPC: Bool = false, gekoppelt: Bool = true, mitSchluessel: Bool = true) throws -> Aufbau {
        let pc = PCAttrappe()
        let (sitzungNetz, basis) = FakeNetz.neu { [pc] r, b in pc.handle(r, b) }
        let bund = Schluesselbund(speicher: MemorySpeicher())
        if mitSchluessel { try bund.speichereSchluessel(k) }
        if gekoppelt { try bund.speichereGeraet(Geraet(url: basis, token: TestSchluessel.token)) }
        let ablage = TresorAblage(ordner: try tempOrdner())
        if let t = tresor { try ablage.speichere(Umschlag.verschliesse(t, schluessel: k, rev: 5)) }
        let merker = IdentitaetenMerker()
        let s = AutoFillSitzung(bund: bund, ablage: ablage, client: mitPC ? HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzungNetz) : nil,
                                identitaeten: { merker.merke($0) })
        return Aufbau(sitzung: s, ablage: ablage, pc: pc, identitaeten: merker)
    }

    func testEntsperrenOeffnetDenLokalenStandEinmal() async throws {
        let a = try aufbau(tresor: Tresor(eintraege: [testEintrag("a")]))
        XCTAssertFalse(a.sitzung.istEntsperrt)
        try await a.sitzung.entsperren()
        XCTAssertEqual(a.sitzung.tresor?.lebendige.map(\.id), ["a"])
        try await a.sitzung.entsperren()
        XCTAssertTrue(a.sitzung.istEntsperrt)
    }

    func testNichtGekoppeltOderOhneSchluessel() async throws {
        for (gekoppelt, schluessel) in [(false, true), (true, false)] {
            let a = try aufbau(gekoppelt: gekoppelt, mitSchluessel: schluessel)
            do { try await a.sitzung.entsperren(); XCTFail("sollte werfen") } catch { XCTAssertEqual(error as? AutoFillFehler, .nichtGekoppelt) }
            XCTAssertNil(a.sitzung.tresor)
        }
    }

    func testLeerePlatteErgibtLeerenTresor() async throws {
        let a = try aufbau()
        try await a.sitzung.entsperren()
        XCTAssertEqual(a.sitzung.tresor, Tresor())
    }

    func testSpeichernOhnePCBleibtLokalUndSetztIdentitaeten() async throws {
        let a = try aufbau(tresor: Tresor(eintraege: [testEintrag("a")]))
        try await a.sitzung.entsperren()
        let neu = Eintrag(id: "n", name: "Neu", benutzer: "mia", passwort: "pw", urls: ["https://neu.org"])
        try await a.sitzung.speichere(.neu(neu))
        XCTAssertEqual(Set(a.sitzung.tresor?.lebendige.map(\.id) ?? []), ["a", "n"])
        let gelesen = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(Set(gelesen?.lebendige.map(\.id) ?? []), ["a", "n"])
        XCTAssertEqual(Set(a.identitaeten.staende_.last?.lebendige.map(\.id) ?? []), ["a", "n"])
    }

    func testSpeichernMischtDieDateiEinDieDieAppInzwischenGeaendertHat() async throws {
        let a = try aufbau(tresor: Tresor(eintraege: [testEintrag("a")]))
        try await a.sitzung.entsperren()
        // Die App legt "app" in die Datei, während die Erweiterung offen ist.
        try await TresorDienst(ablage: a.ablage, client: nil).speichereLokal(Tresor(eintraege: [testEintrag("a"), testEintrag("app")]), schluessel: k)
        try await a.sitzung.speichere(.neu(Eintrag(id: "n", name: "Neu", urls: ["https://neu.org"])))
        let gelesen = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(Set(gelesen?.lebendige.map(\.id) ?? []), ["a", "app", "n"], "nichts von der App überschrieben")
        XCTAssertEqual(Set(a.sitzung.tresor?.lebendige.map(\.id) ?? []), ["a", "app", "n"])
    }

    func testSpeichernMitErreichbaremPCGehtSofortHoch() async throws {
        let a = try aufbau(tresor: Tresor(eintraege: [testEintrag("a")]), mitPC: true)
        a.pc.setze(try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a")]), schluessel: k, rev: 5))
        try await a.sitzung.entsperren()
        try await a.sitzung.speichere(.neu(Eintrag(id: "n", name: "Neu", urls: ["https://neu.org"])))
        let amPC = try a.pc.umschlag?.oeffne(schluessel: k)
        XCTAssertEqual(Set(amPC?.lebendige.map(\.id) ?? []), ["a", "n"])
    }

    func testSpeichernMitAusgeschaltetemPCDauertNichtLangeUndVerliertNichts() async throws {
        let a = try aufbau(mitPC: true)
        a.pc.erreichbar(false)
        try await a.sitzung.entsperren()
        try await a.sitzung.speichere(.neu(Eintrag(id: "n", name: "Neu", urls: ["https://neu.org"])), abgleichSekunden: 2)
        let gelesen = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(gelesen?.lebendige.map(\.id), ["n"])
    }

    func testSpeichernVorDemEntsperrenIstVerboten() async throws {
        let a = try aufbau()
        do { try await a.sitzung.speichere(.neu(Eintrag(id: "n", name: "Neu"))); XCTFail() } catch { XCTAssertEqual(error as? AutoFillFehler, .nichtGekoppelt) }
    }

    func testLiveOhneAppGruppeWirftKeinenSpeicher() {
        // Im ungesignierten Testlauf gibt es keinen App-Group-Ordner (wie bei Bahnherz).
        if Kennungen.gruppenOrdner() == nil {
            XCTAssertThrowsError(try AutoFillSitzung.live()) { XCTAssertEqual($0 as? AutoFillFehler, .keinSpeicher) }
        }
    }

    // MARK: Modell

    private func modell(_ auftrag: AutoFillAuftrag, tresor: Tresor?, sitzung: AutoFillSitzung? = nil, einstellungen: GeteilteEinstellungen? = nil,
                        nutzung: Nutzung? = nil, ergebnis: @escaping (AutoFillErgebnis) -> Void) throws -> (AutoFillModell, Aufbau) {
        let a = try aufbau(tresor: tresor)
        let m = AutoFillModell(auftrag: auftrag, sitzung: sitzung ?? a.sitzung, jetzt: { Date(timeIntervalSince1970: 59) },
                               einstellungen: einstellungen ?? Self.frischeEinstellungen(), nutzung: nutzung ?? Nutzung(speicher: Self.frischerSpeicher()),
                               warten: { _ in })
        m.abschluss = ergebnis
        m.zwischenablage = { _ in }
        return (m, a)
    }

    private nonisolated static func frischerSpeicher() -> UserDefaults {
        UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)") ?? .standard
    }

    private nonisolated static func frischeEinstellungen() -> GeteilteEinstellungen { GeteilteEinstellungen(speicher: frischerSpeicher()) }

    /// Fest einmal gebaut: `Eintrag` stempelt `geaendert` mit der Uhr, zwei Aufrufe wären nie gleich.
    private let beispiel: Tresor = {
        Tresor(eintraege: [
            Eintrag(id: "1", name: "Zebra", benutzer: "mia", passwort: "pw1", urls: ["https://example.com"], totp: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            Eintrag(id: "2", name: "Anker", benutzer: "tom", passwort: "pw2", urls: ["https://m.example.com"]),
            Eintrag(id: "3", name: "Fremd", benutzer: "x", passwort: "pw3", urls: ["https://andere.org"], totp: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            Eintrag(id: "4", art: Eintrag.artNotiz, name: "Notiz", notiz: "n")
        ])
    }()

    func testListeZeigtPassendeZuerstUndFiltertNachSuche() async throws {
        let (m, _) = try modell(.liste(hosts: ["example.com"], codes: false), tresor: beispiel) { _ in }
        await m.starte()
        XCTAssertEqual(m.phase, .liste)
        XCTAssertEqual(m.gruppen.passend.map(\.id), ["1", "2"], "genau example.com vor m.example.com")
        XCTAssertEqual(m.gruppen.uebrige.map(\.id), ["3"])
        m.suche = "andere"
        XCTAssertEqual(m.gruppen.passend.count, 0)
        XCTAssertEqual(m.gruppen.uebrige.map(\.id), ["3"])
    }

    func testListeImCodeModusNurKontenMitEinmalcode() async throws {
        let (m, _) = try modell(.liste(hosts: ["example.com"], codes: true), tresor: beispiel) { _ in }
        await m.starte()
        XCTAssertEqual(m.gruppen.passend.map(\.id), ["1"])
        XCTAssertEqual(m.gruppen.uebrige.map(\.id), ["3"])
    }

    func testWaehleLiefertPasswortOderCode() async throws {
        var ergebnisse: [AutoFillErgebnis] = []
        let (m, _) = try modell(.liste(hosts: [], codes: false), tresor: beispiel) { ergebnisse.append($0) }
        await m.starte()
        m.waehle(beispiel.eintraege[0])
        m.waehle(beispiel.eintraege[1])
        XCTAssertEqual(ergebnisse, [.passwort(benutzer: "mia", passwort: "pw1")], "nur das erste Ergebnis zählt")
        var codes: [AutoFillErgebnis] = []
        let (c, _) = try modell(.liste(hosts: [], codes: true), tresor: beispiel) { codes.append($0) }
        await c.starte()
        c.waehle(beispiel.eintraege[0])
        XCTAssertEqual(codes, [.code("287082")], "RFC 6238 SHA1 bei t=59: 94287082, sechsstellig 287082")
    }

    func testAnfrageLiefertDasKontoOhneListe() async throws {
        var e: [AutoFillErgebnis] = []
        let (m, _) = try modell(.anfrage(id: "2", codes: false), tresor: beispiel) { e.append($0) }
        await m.starte()
        XCTAssertEqual(e, [.passwort(benutzer: "tom", passwort: "pw2")])
    }

    func testAnfrageNichtGefundenOderOhneCode() async throws {
        var e: [AutoFillErgebnis] = []
        let (m, _) = try modell(.anfrage(id: "weg", codes: false), tresor: beispiel) { e.append($0) }
        await m.starte()
        let (n, _) = try modell(.anfrage(id: "2", codes: true), tresor: beispiel) { e.append($0) }
        await n.starte()
        let (o, _) = try modell(.anfrage(id: "4", codes: false), tresor: beispiel) { e.append($0) }
        await o.starte()
        XCTAssertEqual(e, [.nichtGefunden, .nichtGefunden, .nichtGefunden], "unbekannt, Konto ohne TOTP, Notiz")
    }

    func testSpeichernSofortLegtNeuesKontoAn() async throws {
        var e: [AutoFillErgebnis] = []
        let anfrage = SpeicherAnfrage(host: "neu.org", name: "Neu", benutzer: "mia", passwort: "pw", sofort: true)
        let (m, a) = try modell(.speichern(anfrage), tresor: beispiel) { e.append($0) }
        await m.starte()
        XCTAssertEqual(e, [.gespeichert])
        let t = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(t?.lebendige.count, 5)
        XCTAssertTrue(t?.lebendige.contains { $0.name == "Neu" && $0.urls == ["https://neu.org"] } == true)
    }

    func testSpeichernOhneSofortFragtErstNach() async throws {
        var e: [AutoFillErgebnis] = []
        let anfrage = SpeicherAnfrage(host: "neu.org", name: "Neu", benutzer: "mia", passwort: "pw", sofort: false)
        let (m, a) = try modell(.speichern(anfrage), tresor: beispiel) { e.append($0) }
        await m.starte()
        guard case .bestaetigen(.neu) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(e, [])
        let vorher = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(vorher?.lebendige.count, 4, "noch nichts gespeichert")
        await m.bestaetigeSpeichern()
        XCTAssertEqual(e, [.gespeichert])
    }

    func testAbbrechenSpeichertNichts() async throws {
        var e: [AutoFillErgebnis] = []
        let anfrage = SpeicherAnfrage(host: "neu.org", name: "Neu", benutzer: "mia", passwort: "pw", sofort: false)
        let (m, a) = try modell(.speichern(anfrage), tresor: beispiel) { e.append($0) }
        await m.starte()
        m.abbrechen()
        await m.bestaetigeSpeichern()
        XCTAssertEqual(e, [.abgebrochen])
        let t = try await TresorDienst(ablage: a.ablage, client: nil).lokal(schluessel: k)
        XCTAssertEqual(t?.lebendige.count, 4)
    }

    func testSpeichernMitAnderemPasswortFragtImmerNachAuchBeiSofort() async throws {
        let anfrage = SpeicherAnfrage(host: "example.com", name: "x", benutzer: "mia", passwort: "anders", sofort: true)
        let (m, _) = try modell(.speichern(anfrage), tresor: beispiel) { _ in }
        await m.starte()
        guard case .bestaetigen(.aktualisieren(let neu)) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(neu.id, "1")
    }

    func testSpeichernBereitsVorhandenOderLeeresPasswort() async throws {
        var e: [AutoFillErgebnis] = []
        let (m, _) = try modell(.speichern(SpeicherAnfrage(host: "example.com", name: "x", benutzer: "mia", passwort: "pw1", sofort: false)), tresor: beispiel) { e.append($0) }
        await m.starte()
        let (n, _) = try modell(.speichern(SpeicherAnfrage(host: "x.org", name: "x", benutzer: "mia", passwort: "", sofort: true)), tresor: beispiel) { e.append($0) }
        await n.starte()
        XCTAssertEqual(e, [.gespeichert, .fehlgeschlagen])
    }

    func testFaceIdAbgebrochenZeigtEntsperrenOhneFehlertext() async throws {
        let bund = Schluesselbund(speicher: AbbruchSpeicher())
        let s = AutoFillSitzung(bund: bund, ablage: TresorAblage(ordner: try tempOrdner()), client: nil, identitaeten: { _ in })
        let m = AutoFillModell(auftrag: .liste(hosts: [], codes: false), sitzung: s)
        await m.starte()
        XCTAssertEqual(m.phase, .entsperren(fehler: nil))
    }

    func testOhneSitzungZeigtDenGrund() async {
        let m = AutoFillModell(auftrag: .liste(hosts: [], codes: false), sitzung: nil, startFehler: AutoFillFehler.keinSpeicher.nutzerText)
        await m.starte()
        XCTAssertEqual(m.phase, .entsperren(fehler: AutoFillFehler.keinSpeicher.nutzerText))
    }

    func testNichtGekoppeltZeigtVerstaendlichenText() async throws {
        let a = try aufbau(gekoppelt: false)
        let m = AutoFillModell(auftrag: .liste(hosts: [], codes: false), sitzung: a.sitzung)
        await m.starte()
        XCTAssertEqual(m.phase, .entsperren(fehler: AutoFillFehler.nichtGekoppelt.nutzerText))
    }

    func testKonfigurationBrauchtKeinenSchluessel() async {
        var e: [AutoFillErgebnis] = []
        let m = AutoFillModell(auftrag: .konfiguration, sitzung: nil)
        m.abschluss = { e.append($0) }
        await m.starte()
        XCTAssertEqual(m.phase, .konfiguration)
        m.fertigKonfiguration()
        XCTAssertEqual(e, [.konfigurationFertig])
    }

    // MARK: Schneller (W-010): -25308, Start erst bei sichtbarer Ansicht

    /// Schlüsselbund, der K zuerst mit -25308 verweigert (Erweiterung noch nicht aktiv) und danach herausgibt.
    private final class ZuFrueh: KeychainSpeicher, @unchecked Sendable {
        let innen = MemorySpeicher()
        private let uebrig: Mutex<Int>
        init(fehlversuche: Int) { uebrig = Mutex(fehlversuche) }
        func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? {
            if konto == Schluesselbund.kontoSchluessel {
                let werfen = uebrig.withLock { n -> Bool in
                    guard n > 0 else { return false }
                    n -= 1
                    return true
                }
                if werfen { throw SchluesselbundFehler.abfrageNochNichtMoeglich }
            }
            return try innen.lesen(konto, kontext: kontext)
        }
        func schreiben(_ konto: String, daten: Data, schutz: KeychainSchutz) throws { try innen.schreiben(konto, daten: daten, schutz: schutz) }
        func loeschen(_ konto: String) throws { try innen.loeschen(konto) }
    }

    private func zuFruehModell(fehlversuche: Int) throws -> AutoFillModell {
        let speicher = ZuFrueh(fehlversuche: fehlversuche)
        let bund = Schluesselbund(speicher: speicher, dauer: { .aus })
        try bund.speichereSchluessel(k)
        try bund.speichereGeraet(Geraet(url: URL(string: "https://pc.ts.net") ?? URL(fileURLWithPath: "/"), token: TestSchluessel.token))
        let ablage = TresorAblage(ordner: try tempOrdner())
        try ablage.speichere(Umschlag.verschliesse(beispiel, schluessel: k, rev: 1))
        let s = AutoFillSitzung(bund: bund, ablage: ablage, client: nil, identitaeten: { _ in })
        let m = AutoFillModell(auftrag: .anfrage(id: "2", codes: false), sitzung: s, einstellungen: Self.frischeEinstellungen(),
                               nutzung: Nutzung(speicher: Self.frischerSpeicher()), warten: { _ in })
        m.zwischenablage = { _ in }
        return m
    }

    func testFehler25308WirdStillNachgeholtUndNieGezeigt() async throws {
        var e: [AutoFillErgebnis] = []
        let m = try zuFruehModell(fehlversuche: 2)
        m.abschluss = { e.append($0) }
        await m.ansichtIstAktiv()
        XCTAssertEqual(e, [.passwort(benutzer: "tom", passwort: "pw2")])
    }

    func testBleibt25308ZeigtDieOberflaecheDenKnopfOhneFehlertext() async throws {
        let m = try zuFruehModell(fehlversuche: 99)
        await m.ansichtIstAktiv()
        XCTAssertEqual(m.phase, .entsperren(fehler: nil), "weder die Nummer noch ein Satz")
        XCTAssertFalse(SchluesselbundFehler.abfrageNochNichtMoeglich.nutzerText.contains("25308"))
    }

    func testAnsichtIstAktivStartetNurEinmal() async throws {
        var e: [AutoFillErgebnis] = []
        let (m, _) = try modell(.anfrage(id: "2", codes: false), tresor: beispiel) { e.append($0) }
        XCTAssertEqual(m.phase, .start, "vor der sichtbaren Ansicht passiert nichts")
        await m.ansichtIstAktiv()
        await m.ansichtIstAktiv()
        XCTAssertEqual(e.count, 1)
    }

    // MARK: Fenster (W-009): Ausfüllen ohne Blatt

    private func fensterModell(host: String?, id: String = "1", codes: Bool = false, fensterOffen: Bool = true,
                               einstellungen: GeteilteEinstellungen? = nil, nutzung: Nutzung? = nil,
                               ergebnis: @escaping (AutoFillErgebnis) -> Void, kopiert: @escaping (String) -> Void = { _ in }) throws -> AutoFillModell {
        let bund = Schluesselbund(speicher: MemorySpeicher(), dauer: { .fuenfMinuten })
        try bund.speichereSchluessel(k)
        try bund.speichereGeraet(Geraet(url: URL(string: "https://pc.ts.net") ?? URL(fileURLWithPath: "/"), token: TestSchluessel.token))
        if fensterOffen { bund.oeffneFenster(k) }
        let ablage = TresorAblage(ordner: try tempOrdner())
        try ablage.speichere(Umschlag.verschliesse(beispiel, schluessel: k, rev: 1))
        let s = AutoFillSitzung(bund: bund, ablage: ablage, client: nil, identitaeten: { _ in })
        let m = AutoFillModell(auftrag: .anfrage(id: id, codes: codes, host: host), sitzung: s, jetzt: { Date(timeIntervalSince1970: 59) },
                               einstellungen: einstellungen ?? Self.frischeEinstellungen(), nutzung: nutzung ?? Nutzung(speicher: Self.frischerSpeicher()), warten: { _ in })
        m.abschluss = ergebnis
        m.zwischenablage = { kopiert($0) }
        return m
    }

    func testOhneBlattMitOffenemFensterLiefertPasswortUndCode() async throws {
        var e: [AutoFillErgebnis] = []
        let p = try fensterModell(host: "example.com") { e.append($0) }
        await p.starteOhneAbfrage()
        let c = try fensterModell(host: "example.com", codes: true) { e.append($0) }
        await c.starteOhneAbfrage()
        XCTAssertEqual(e, [.passwort(benutzer: "mia", passwort: "pw1"), .code("287082")])
    }

    func testOhneBlattBeiGeschlossenemFensterVerlangtDasBlatt() async throws {
        var e: [AutoFillErgebnis] = []
        let m = try fensterModell(host: "example.com", fensterOffen: false) { e.append($0) }
        await m.starteOhneAbfrage()
        XCTAssertEqual(e, [.abfrageNoetig])
    }

    func testOhneBlattNurBeiPassendemHostSonstBlatt() async throws {
        // Eintrag 1 gehört zu example.com. Nahe Verwandte und Fälschungen dürfen ohne Blatt nie durch.
        var e: [AutoFillErgebnis] = []
        for host in ["example.com.evil.com", "evilexample.com", "example-com.com", "example.org", "com", ""] {
            let m = try fensterModell(host: host) { e.append($0) }
            await m.starteOhneAbfrage()
        }
        let ohneHost = try fensterModell(host: nil) { e.append($0) }   // `.app`-Bezeichner ohne Host
        await ohneHost.starteOhneAbfrage()
        XCTAssertEqual(e, Array(repeating: .abfrageNoetig, count: 7))
    }

    func testOhneBlattGrabsteinUndNotizBleibenDraussen() async throws {
        var e: [AutoFillErgebnis] = []
        let m = try fensterModell(host: "example.com", id: "4") { e.append($0) }   // Notiz
        await m.starteOhneAbfrage()
        XCTAssertEqual(e, [.nichtGefunden])
        var t = beispiel
        t.eintraege[0].geloescht = true
        let bund = Schluesselbund(speicher: MemorySpeicher(), dauer: { .fuenfMinuten })
        try bund.speichereSchluessel(k)
        bund.oeffneFenster(k)
        let ablage = TresorAblage(ordner: try tempOrdner())
        try ablage.speichere(Umschlag.verschliesse(t, schluessel: k, rev: 1))
        let s = AutoFillSitzung(bund: bund, ablage: ablage, client: nil, identitaeten: { _ in })
        let g = AutoFillModell(auftrag: .anfrage(id: "1", codes: false, host: "example.com"), sitzung: s, einstellungen: Self.frischeEinstellungen(),
                               nutzung: Nutzung(speicher: Self.frischerSpeicher()), warten: { _ in })
        g.abschluss = { e.append($0) }
        await g.starteOhneAbfrage()
        XCTAssertEqual(e, [.nichtGefunden, .nichtGefunden], "ein Grabstein wird nie geliefert")
    }

    func testUnterdomainDesEintragsDarfOhneBlattAberKeineFremdeDomain() async throws {
        var e: [AutoFillErgebnis] = []
        let m = try fensterModell(host: "login.example.com") { e.append($0) }
        await m.starteOhneAbfrage()
        XCTAssertEqual(e, [.passwort(benutzer: "mia", passwort: "pw1")])
    }

    // MARK: Phishing-Schutz in der Liste

    func testSparkasseGegenFaelschungen() {
        let e = Eintrag(id: "s", name: "Sparkasse", benutzer: "x", passwort: "p", urls: ["https://sparkasse.de"])
        for fremd in ["sparkasse.de.evil.com", "evilsparkasse.de", "sparkasse-de.com", "sparkasse.com", "de"] {
            XCTAssertEqual(AutoFillModell.passung(e, hosts: [fremd]), .fremd(seite: fremd), fremd)
        }
        XCTAssertEqual(AutoFillModell.passung(e, hosts: ["sparkasse.de"]), .passt)
        XCTAssertEqual(AutoFillModell.passung(e, hosts: ["www.sparkasse.de"]), .passt)
        XCTAssertEqual(AutoFillModell.passung(e, hosts: []), .unbekannt)
        XCTAssertEqual(AutoFillModell.passung(Eintrag(id: "o", name: "o", urls: []), hosts: ["sparkasse.de"]), .fremd(seite: "sparkasse.de"), "Konto ohne Host passt zu keiner Seite")
    }

    func testFremdesKontoInDerListeFragtErstNachUndFuelltNurNachBestaetigung() async throws {
        var e: [AutoFillErgebnis] = []
        var kopiert: [String] = []
        let (m, _) = try modell(.liste(hosts: ["evil-example.com"], codes: false), tresor: beispiel) { e.append($0) }
        m.zwischenablage = { kopiert.append($0) }
        await m.starte()
        m.waehle(beispiel.eintraege[0])
        XCTAssertEqual(m.phase, .fremdesKonto(beispiel.eintraege[0], seite: "evil-example.com"))
        XCTAssertTrue(e.isEmpty, "nichts wurde geliefert")
        m.lehneFremdesAb()
        XCTAssertEqual(m.phase, .liste)
        XCTAssertTrue(e.isEmpty)
        m.waehle(beispiel.eintraege[0])
        m.bestaetigeFremdes()
        XCTAssertEqual(e, [.passwort(benutzer: "mia", passwort: "pw1")])
        XCTAssertTrue(kopiert.isEmpty, "bei einem fremden Konto nie ein Code in die Zwischenablage")
    }

    func testPassendesKontoInDerListeFuelltOhneRueckfrage() async throws {
        var e: [AutoFillErgebnis] = []
        let (m, _) = try modell(.liste(hosts: ["example.com"], codes: false), tresor: beispiel) { e.append($0) }
        await m.starte()
        m.waehle(beispiel.eintraege[0])
        XCTAssertEqual(e, [.passwort(benutzer: "mia", passwort: "pw1")])
    }

    func testFremdeAnfrageMitBlattFragtNach() async throws {
        let (m, _) = try modell(.anfrage(id: "1", codes: false, host: "fremd.org"), tresor: beispiel) { _ in }
        await m.starte()
        XCTAssertEqual(m.phase, .fremdesKonto(beispiel.eintraege[0], seite: "fremd.org"))
    }

    // MARK: Code in die Zwischenablage (W-011) und Nutzung (W-020)

    func testCodeLiegtNachDemPasswortInDerAblageNurAufPassendemHost() async throws {
        var kopiert: [String] = []
        var e: [AutoFillErgebnis] = []
        let m = try fensterModell(host: "example.com") { e.append($0) } kopiert: { kopiert.append($0) }
        await m.starteOhneAbfrage()
        XCTAssertEqual(kopiert, ["287082"])
        // Eintrag 2 hat kein TOTP: nichts kopieren. Den Code selbst zu liefern kopiert auch nichts.
        var k2: [String] = []
        let ohneTotp = try fensterModell(host: "m.example.com", id: "2") { _ in } kopiert: { k2.append($0) }
        await ohneTotp.starteOhneAbfrage()
        let code = try fensterModell(host: "example.com", codes: true) { _ in } kopiert: { k2.append($0) }
        await code.starteOhneAbfrage()
        XCTAssertTrue(k2.isEmpty)
    }

    func testCodeKopierenAusKopiertNichts() async throws {
        let einst = Self.frischeEinstellungen()
        einst.codeKopieren = false
        var kopiert: [String] = []
        let m = try fensterModell(host: "example.com", einstellungen: einst) { _ in } kopiert: { kopiert.append($0) }
        await m.starteOhneAbfrage()
        XCTAssertTrue(kopiert.isEmpty)
    }

    func testAusfuellenMerktDieNutzungBeiPasswortUndCode() async throws {
        let n = Nutzung(speicher: Self.frischerSpeicher())
        let p = try fensterModell(host: "example.com", nutzung: n) { _ in }
        await p.starteOhneAbfrage()
        XCTAssertEqual(Array(n.zuletzt.keys), ["1"])
        let n2 = Nutzung(speicher: Self.frischerSpeicher())
        let c = try fensterModell(host: "example.com", codes: true, nutzung: n2) { _ in }
        await c.starteOhneAbfrage()
        XCTAssertEqual(Array(n2.zuletzt.keys), ["1"])
        let n3 = Nutzung(speicher: Self.frischerSpeicher())
        let (l, _) = try modell(.liste(hosts: [], codes: false), tresor: beispiel, nutzung: n3) { _ in }
        await l.starte()
        l.waehle(beispiel.eintraege[1])
        XCTAssertEqual(Array(n3.zuletzt.keys), ["2"])
    }

    @MainActor
    func testCodeAblageIstLokalMitAblaufNach60Sekunden() {
        let jetzt = Date(timeIntervalSince1970: 1000)
        let o = CodeAblage.optionen(jetzt: jetzt)
        XCTAssertEqual(o[.localOnly] as? Bool, true)
        XCTAssertEqual(o[.expirationDate] as? Date, jetzt.addingTimeInterval(60))
    }

    // MARK: Einmalcode-Identitäten (W-011)

    func testEintragMitTotpUndZweiHostsHatCodeIdentitaetFuerJedenHost() {
        let e = Eintrag(id: "a", name: "Arbeitsagentur", benutzer: "mia", passwort: "GEHEIM", urls: ["https://sso.arbeitsagentur.de", "https://web.arbeitsagentur.de"],
                        totp: "JBSWY3DPEHPK3PXP")
        let codes = AutoFillIdentitaeten.baue(aus: Tresor(eintraege: [e])).compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
        XCTAssertEqual(codes.map(\.serviceIdentifier.identifier).sorted(), ["sso.arbeitsagentur.de", "web.arbeitsagentur.de"])
        XCTAssertEqual(Set(codes.compactMap(\.recordIdentifier)), ["a"])
    }
}
