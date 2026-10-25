import CryptoKit
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
    func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws {}
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

    private func modell(_ auftrag: AutoFillAuftrag, tresor: Tresor?, sitzung: AutoFillSitzung? = nil, ergebnis: @escaping (AutoFillErgebnis) -> Void) throws -> (AutoFillModell, Aufbau) {
        let a = try aufbau(tresor: tresor)
        let m = AutoFillModell(auftrag: auftrag, sitzung: sitzung ?? a.sitzung, jetzt: { Date(timeIntervalSince1970: 59) })
        m.abschluss = ergebnis
        return (m, a)
    }

    private var beispiel: Tresor {
        Tresor(eintraege: [
            Eintrag(id: "1", name: "Zebra", benutzer: "mia", passwort: "pw1", urls: ["https://example.com"], totp: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            Eintrag(id: "2", name: "Anker", benutzer: "tom", passwort: "pw2", urls: ["https://m.example.com"]),
            Eintrag(id: "3", name: "Fremd", benutzer: "x", passwort: "pw3", urls: ["https://andere.org"], totp: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            Eintrag(id: "4", art: Eintrag.artNotiz, name: "Notiz", notiz: "n")
        ])
    }

    func testListeZeigtPassendeZuerstUndFiltertNachSuche() async throws {
        let (m, _) = try modell(.liste(hosts: ["example.com"], codes: false), tresor: beispiel) { _ in }
        await m.starte()
        XCTAssertEqual(m.phase, .liste)
        XCTAssertEqual(m.gruppen.passend.map(\.id), ["2", "1"])
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
}
