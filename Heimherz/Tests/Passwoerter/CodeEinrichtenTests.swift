import AuthenticationServices
import XCTest
@testable import Heimherz

/// Das Feld `totp` eines Verlaufseintrags `{totp, bis}`.
private func totpVon(_ wert: JSONWert?) -> String? {
    if case .objekt(let d)? = wert { return d["totp"]?.alsText }
    return nil
}

/// W-028: Parser für `otpauth://`-Links (Key URI Format), Zuordnung zu Einträgen, Verlauf beim Ersetzen, Postfach und Speichern über den Store.
/// Alle Geheimnisse sind erfunden oder stammen aus den RFC-Beispielen.
final class OtpAuthTests: XCTestCase {
    private let rfcSHA1 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    private let rfcSHA256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"

    func testGoogleBeispiel() throws {
        let k = try OtpAuth.lese("otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
        XCTAssertEqual(k.issuer, "Example")
        XCTAssertEqual(k.konto, "alice@google.com")
        XCTAssertEqual(k.einstellung.algorithmus, .sha1)
        XCTAssertEqual(k.einstellung.stellen, 6)
        XCTAssertEqual(k.einstellung.periode, 30)
        XCTAssertEqual(k.einstellung.geheim, Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testRFCVektorenMitSHA256UndAchtStellen() throws {
        let k1 = try OtpAuth.lese("otpauth://totp/RFC:t?secret=\(rfcSHA1)&digits=8")
        XCTAssertEqual(TOTP.code(k1.einstellung, zeit: 59), "94287082")
        let k2 = try OtpAuth.lese("otpauth://totp/RFC:t?secret=\(rfcSHA256)&digits=8&algorithm=sha256")
        XCTAssertEqual(k2.einstellung.algorithmus, .sha256)
        XCTAssertEqual(TOTP.code(k2.einstellung, zeit: 59), "46119246")
    }

    func testIssuerParameterGewinntGegenLabelUndLabelOhnePrefixGeht() throws {
        XCTAssertEqual(try OtpAuth.lese("otpauth://totp/Alt:mia?secret=\(rfcSHA1)&issuer=Neu").issuer, "Neu")
        let ohne = try OtpAuth.lese("otpauth://totp/mia?secret=\(rfcSHA1)")
        XCTAssertEqual(ohne.issuer, "")
        XCTAssertEqual(ohne.konto, "mia")
        let nurLabel = try OtpAuth.lese("otpauth://totp/GitHub:%20mia?secret=\(rfcSHA1)")
        XCTAssertEqual(nurLabel.issuer, "GitHub")
        XCTAssertEqual(nurLabel.konto, "mia", "Leerzeichen nach dem Doppelpunkt fallen weg")
    }

    func testProzentKodierungUmlauteUndKodierterDoppelpunkt() throws {
        let k = try OtpAuth.lese("otpauth://totp/B%C3%A4ckerei%20M%C3%BCller%3Amia%40example.org?secret=\(rfcSHA1)")
        XCTAssertEqual(k.issuer, "Bäckerei Müller")
        XCTAssertEqual(k.konto, "mia@example.org")
    }

    func testGeheimnisMitKleinschreibungLeerzeichenUndFuellzeichen() throws {
        let k = try OtpAuth.lese("otpauth://totp/x?secret=jbsw%20y3dp-ehpk%203pxp====")
        XCTAssertEqual(k.einstellung.geheim, try OtpAuth.lese("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP").einstellung.geheim)
    }

    func testSchemaUndTypGrossgeschrieben() throws {
        XCTAssertNoThrow(try OtpAuth.lese("  OTPAUTH://TOTP/x?secret=\(rfcSHA1)\n"))
    }

    func testUngueltigesWirdAbgelehnt() {
        func fehler(_ text: String) -> OtpFehler? {
            do { _ = try OtpAuth.lese(text); return nil } catch { return error as? OtpFehler }
        }
        XCTAssertEqual(fehler("https://example.org"), .keinLink)
        XCTAssertEqual(fehler("JBSWY3DPEHPK3PXP"), .keinLink, "ein rohes Geheimnis ist kein Link")
        XCTAssertEqual(fehler(""), .keinLink)
        XCTAssertEqual(fehler("otpauth://hotp/x?secret=\(rfcSHA1)&counter=1"), .hotp)
        XCTAssertEqual(fehler("otpauth://steam/x?secret=\(rfcSHA1)"), .unbekannterTyp)
        XCTAssertEqual(fehler("otpauth-migration://offline?data=AAAA"), .migration)
        XCTAssertEqual(fehler("otpauth://totp/x"), .geheimnisFehlt)
        XCTAssertEqual(fehler("otpauth://totp/x?secret="), .geheimnisFehlt)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=ABC189"), .geheimnisUngueltig, "0, 1, 8 und 9 gibt es in Base32 nicht")
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&algorithm=MD5"), .algorithmus)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&digits=7"), .stellen)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&digits=abc"), .stellen)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&period=0"), .periode)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&period=-5"), .periode)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&period=zehn"), .periode)
        XCTAssertEqual(fehler("otpauth://totp/x?secret=\(rfcSHA1)&" + String(repeating: "a", count: OtpAuth.maxLaenge)), .zuLang)
    }

    func testFehlertexteVerratenNieDasGeheimnis() {
        let alle: [OtpFehler] = [.keinLink, .zuLang, .hotp, .migration, .unbekannterTyp, .geheimnisFehlt, .geheimnisUngueltig, .algorithmus, .stellen, .periode]
        for f in alle {
            XCTAssertFalse(f.nutzerText.isEmpty)
            XCTAssertFalse(f.nutzerText.contains(rfcSHA1))
            XCTAssertFalse(f.nutzerText.contains("secret="))
        }
    }

    func testBase32RundeUndGespeicherteFormLiestTOTPGleich() throws {
        for roh in [Data(), Data([0xFF]), Data(1...5), Data(1...10), Data(1...31)] where !roh.isEmpty {
            XCTAssertEqual(TOTP.base32(OtpAuth.base32(roh)), roh)
        }
        for text in ["otpauth://totp/Ex%20ample:mia%2Bx%40e.org?secret=\(rfcSHA256)&issuer=Ex%20ample&algorithm=SHA256&digits=8&period=45",
                     "otpauth://totp/mia?secret=\(rfcSHA1)",
                     "otpauth://totp/B%C3%A4cker:%C3%9Cber?secret=JBSWY3DPEHPK3PXP&issuer=B%C3%A4cker&algorithm=SHA512"] {
            let k = try OtpAuth.lese(text)
            XCTAssertEqual(try OtpAuth.lese(k.uri), k, "feste Form liest wieder denselben Code")
            // Was im Tresor steht, liest auch die nachsichtige Fassung für AutoFill und die Anzeige genau so.
            XCTAssertEqual(TOTP.einstellung(aus: k.uri), k.einstellung)
        }
    }

    func testFesteFormOhneIssuerHatKeinenPrefix() throws {
        let k = try OtpAuth.lese("otpauth://totp/mia?secret=\(rfcSHA1)")
        XCTAssertTrue(k.uri.hasPrefix("otpauth://totp/mia?secret="))
        XCTAssertFalse(k.uri.contains("issuer="))
    }
}

final class CodeZuordnungTests: XCTestCase {
    private func login(_ id: String, _ name: String, benutzer: String = "", urls: [String] = [], totp: String = "") -> Eintrag {
        Eintrag(id: id, name: name, benutzer: benutzer, passwort: "pw", urls: urls, totp: totp)
    }

    private func konto(_ issuer: String, _ name: String) -> OtpKonto {
        OtpKonto(issuer: issuer, konto: name, einstellung: TOTPEinstellung(geheim: Data([1, 2, 3, 4, 5])))
    }

    private func ids(_ k: OtpKonto, _ e: [Eintrag]) -> [String] { CodeZuordnung.vorschlaege(fuer: k, in: e).map(\.id) }

    func testGleicherNameOhneGrossKleinUndSonderzeichen() {
        let e = [login("a", "Online-Bank", benutzer: "mia"), login("b", "Kino")]
        XCTAssertEqual(ids(konto("online bank", "x"), e), ["a"])
        XCTAssertEqual(ids(konto("ONLINE-BANK", "x"), e), ["a"])
    }

    func testHostLabelPasstAufAnbieter() {
        let e = [login("a", "Mein Code-Konto", urls: ["https://github.com/login"]), login("b", "Anderes", urls: ["https://example.org"])]
        XCTAssertEqual(ids(konto("GitHub", "mia"), e), ["a"])
    }

    func testAnbieterAlsDomainPasstUeberHostUndUnterdomain() {
        let e = [login("a", "Konto", urls: ["https://login.example.org"]), login("b", "Konto 2", urls: ["https://evilexample.org"])]
        XCTAssertEqual(ids(konto("example.org", "mia"), e), ["a"])
    }

    func testBenutzerSortiertNachObenRetttetAberKeinenFremdenAnbieter() {
        let e = [login("a", "GitHub", benutzer: "alt"), login("b", "GitHub", benutzer: "mia"), login("c", "Kino", benutzer: "mia")]
        XCTAssertEqual(ids(konto("GitHub", "Mia"), e), ["b", "a"], "gleicher Benutzer zuerst, anderer Anbieter nie")
    }

    func testOhneAnbieterReichtDerBenutzer() {
        let e = [login("a", "GitHub", benutzer: "mia"), login("b", "Kino", benutzer: "tom")]
        XCTAssertEqual(ids(konto("", "mia"), e), ["a"])
        XCTAssertEqual(ids(konto("", ""), e), [], "ohne Anbieter und Konto gibt es nichts zu raten")
    }

    func testTeilweiserNameNurAbDreiZeichenUndEintraegeMitCodeBleiben() {
        let e = [login("a", "Microsoft Konto", totp: "JBSWY3DPEHPK3PXP"), login("b", "Ox")]
        XCTAssertEqual(ids(konto("Microsoft", "mia"), e), ["a"])
        XCTAssertEqual(ids(konto("O", "mia"), e), [], "ein Zeichen ist kein Anbieter")
    }

    func testNotizenGrabsteineUndKeinTrefferGebenLeere() {
        var geloescht = login("g", "GitHub")
        geloescht.geloescht = true
        let notiz = Eintrag(id: "n", art: Eintrag.artNotiz, name: "GitHub")
        XCTAssertEqual(ids(konto("GitHub", "mia"), [geloescht, notiz]), [])
        XCTAssertEqual(ids(konto("Unbekannt", "mia"), [login("a", "GitHub")]), [])
    }
}

final class CodeEintragTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)
    private let neu = OtpKonto(issuer: "GitHub", konto: "mia", einstellung: TOTPEinstellung(geheim: Data(1...10), algorithmus: .sha256, stellen: 8, periode: 30))

    func testErsetzenSchiebtDenAltenSchluesselInDenVerlauf() {
        let e = Eintrag(id: "a", name: "GitHub", benutzer: "mia", passwort: "pw", totp: "JBSWY3DPEHPK3PXP", unbekannt: ["fremd": .text("bleibt")])
        let r = CodeEintrag.mitCode(e, konto: neu, jetzt: jetzt)
        XCTAssertEqual(r.totp, neu.uri)
        XCTAssertEqual(r.unbekannt["totpVerlauf"], .liste([.objekt(["totp": .text("JBSWY3DPEHPK3PXP"), "bis": .text(Zeit.iso(jetzt))])]))
        XCTAssertEqual(r.unbekannt["fremd"], .text("bleibt"))
        XCTAssertEqual(r.passwort, "pw")
        XCTAssertEqual(r.geaendert, Zeit.iso(jetzt))
    }

    func testOhneAltenCodeKeinVerlaufUndGleicherCodeKeinDoppelter() {
        let leer = CodeEintrag.mitCode(Eintrag(id: "a", name: "x"), konto: neu, jetzt: jetzt)
        XCTAssertNil(leer.unbekannt["totpVerlauf"])
        let nochmal = CodeEintrag.mitCode(leer, konto: neu, jetzt: jetzt.addingTimeInterval(60))
        XCTAssertNil(nochmal.unbekannt["totpVerlauf"], "derselbe Schlüssel gehört nicht in den Verlauf")
    }

    func testVerlaufHaeltHoechstensFuenfNeuesteVorn() {
        var e = Eintrag(id: "a", name: "x", totp: "AAAAAAAAAAAAAAAA")
        for i in 0..<7 {
            let k = OtpKonto(issuer: "", konto: "", einstellung: TOTPEinstellung(geheim: Data([UInt8(i + 1)] + Array(repeating: 9, count: 9))))
            e = CodeEintrag.mitCode(e, konto: k, jetzt: jetzt.addingTimeInterval(Double(i)))
        }
        let liste = e.unbekannt["totpVerlauf"]?.alsListe ?? []
        XCTAssertEqual(liste.count, CodeEintrag.verlaufMax)
        XCTAssertNotEqual(totpVon(liste.first), "AAAAAAAAAAAAAAAA")
    }

    func testNeuerEintragNimmtAnbieterAlsNamenUndKontoAlsBenutzer() {
        let e = CodeEintrag.neu(konto: neu, jetzt: jetzt)
        XCTAssertEqual(e.name, "GitHub")
        XCTAssertEqual(e.benutzer, "mia")
        XCTAssertEqual(e.totp, neu.uri)
        XCTAssertEqual(e.art, Eintrag.artLogin)
        XCTAssertTrue(e.passwort.isEmpty)
        let ohneAnbieter = OtpKonto(issuer: "", konto: "tom", einstellung: neu.einstellung)
        XCTAssertEqual(CodeEintrag.neu(konto: ohneAnbieter, jetzt: jetzt).name, "tom")
        let leer = OtpKonto(issuer: "", konto: "", einstellung: neu.einstellung)
        XCTAssertEqual(CodeEintrag.neu(konto: leer, jetzt: jetzt).name, "Neuer Code")
    }

    func testFormularErsetztCodeAuchMitVerlauf() {
        let e = Eintrag(id: "a", name: "x", totp: "JBSWY3DPEHPK3PXP")
        var entwurf = Entwurf(eintrag: e)
        entwurf.totp = neu.uri
        let r = entwurf.anwenden(auf: e)
        XCTAssertEqual(r.totp, neu.uri)
        XCTAssertEqual(r.unbekannt["totpVerlauf"]?.alsListe?.count, 1)
        // Unverändert gespeichert: kein neuer Verlaufseintrag.
        XCTAssertNil(Entwurf(eintrag: e).anwenden(auf: e).unbekannt["totpVerlauf"])
    }
}

@MainActor
final class CodePostfachTests: XCTestCase {
    private let gut = "otpauth://totp/GitHub:mia?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"

    func testNurOtpauthLinksGehenDenPostfachAn() throws {
        XCTAssertTrue(CodePostfach.istCodeLink(try XCTUnwrap(URL(string: gut))))
        XCTAssertTrue(CodePostfach.istCodeLink(try XCTUnwrap(URL(string: "OTPAUTH://totp/x?secret=AAAA"))))
        XCTAssertFalse(CodePostfach.istCodeLink(try XCTUnwrap(URL(string: "heimherz://koppeln?url=x"))))
        XCTAssertFalse(CodePostfach.istCodeLink(try XCTUnwrap(URL(string: "https://example.org"))))
    }

    func testCodeWirdGenauEinmalHerausgegeben() {
        let p = CodePostfach()
        p.empfange(text: gut)
        XCTAssertTrue(p.wartet)
        XCTAssertEqual(p.nimm()?.issuer, "GitHub")
        XCTAssertNil(p.nimm())
        XCTAssertFalse(p.wartet)
    }

    func testUngueltigerLinkSetztFehlerOhneGeheimnis() {
        let p = CodePostfach()
        p.empfange(text: "otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1")
        XCTAssertNil(p.konto)
        XCTAssertTrue(p.wartet)
        XCTAssertEqual(p.fehler, OtpFehler.hotp.nutzerText)
        XCTAssertFalse(p.fehler?.contains("JBSWY3DPEHPK3PXP") ?? true)
        p.schliesseFehler()
        XCTAssertFalse(p.wartet)
    }

    func testEinGuterLinkLoeschtEinenAltenFehlerUndUmgekehrt() {
        let p = CodePostfach()
        p.empfange(text: "kaputt")
        p.empfange(text: gut)
        XCTAssertNil(p.fehler)
        p.empfange(text: "kaputt")
        XCTAssertNil(p.konto, "ein neuer, kaputter Link ersetzt den alten Code")
    }

    func testNachDerWartezeitIstDerCodeWeg() {
        let p = CodePostfach()
        let start = Date(timeIntervalSince1970: 1_792_886_400)
        p.empfange(text: gut, jetzt: start)
        XCTAssertNil(p.nimm(jetzt: start.addingTimeInterval(CodePostfach.wartezeit + 1)))
        XCTAssertNotNil(p.fehler)
        p.empfange(text: gut, jetzt: start)
        XCTAssertNotNil(p.nimm(jetzt: start.addingTimeInterval(CodePostfach.wartezeit)))
    }
}

/// Speichern über den echten `TresorStore`: lokal verschlüsselt, Abgleich mit dem (nachgebauten) PC, AutoFill-Identitäten neu.
@MainActor
final class CodeEinrichtenStoreTests: XCTestCase {
    private let k = TestSchluessel.schluessel
    /// Älter als `jetzt`, sonst gewinnt beim Abgleich der Stand des PCs.
    private let alt = "2026-10-01T10:00:00.000Z"
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400 + 3_600)
    private let neu = OtpKonto(issuer: "GitHub", konto: "mia", einstellung: TOTPEinstellung(geheim: Data(1...10), algorithmus: .sha256, stellen: 8, periode: 30))

    private func aufbau(_ eintraege: [Eintrag]) throws -> (store: TresorStore, pc: PCAttrappe, identitaeten: IdentitaetenMerker, umgebung: AppUmgebung) {
        let pc = PCAttrappe()
        let (sitzung, basis) = FakeNetz.neu { [pc] r, b in pc.handle(r, b) }
        let bund = Schluesselbund(speicher: MemorySpeicher())
        try bund.speichereSchluessel(k)
        try bund.speichereGeraet(Geraet(url: basis, token: TestSchluessel.token))
        let ablage = TresorAblage(ordner: try tempOrdner())
        pc.setze(try Umschlag.verschliesse(Tresor(eintraege: eintraege), schluessel: k, rev: 5))
        let umgebung = AppUmgebung(bund: bund, ablage: ablage, sitzung: sitzung, sperreAktiv: false)
        let merker = IdentitaetenMerker()
        let suite = UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)") ?? .standard
        let store = TresorStore(umgebung: umgebung, identitaeten: { merker.merke($0) }, jetzt: { [jetzt] in jetzt }, merker: suite)
        return (store, pc, merker, umgebung)
    }

    private func modell(_ store: TresorStore) -> CodeEinrichten {
        CodeEinrichten(konto: neu, store: store, jetzt: { [jetzt] in jetzt })
    }

    func testHinzufuegenSchreibtDenCodeSpeichertLokalGleichtAbUndSetztIdentitaeten() async throws {
        let a = try aufbau([Eintrag(id: "a", name: "GitHub", benutzer: "mia", passwort: "pw", urls: ["https://github.com"], geaendert: alt)])
        await a.store.oeffnen()
        let m = modell(a.store)
        XCTAssertEqual(m.vorschlaege.map(\.id), ["a"])
        await m.waehle(try XCTUnwrap(a.store.eintrag("a")))
        XCTAssertEqual(m.fertig, CodeEinrichten.Fertig(name: "GitHub", uri: neu.uri))
        XCTAssertNil(m.rueckfrage)
        XCTAssertEqual(a.store.eintrag("a")?.totp, neu.uri)
        await a.store.warteAufAbgleich()
        let amPC = try a.pc.umschlag?.oeffne(schluessel: k)
        XCTAssertEqual(amPC?.lebendige.first?.totp, neu.uri, "angekommen am PC")
        let lokal = try await a.umgebung.tresorDienst().lokal(schluessel: k)
        XCTAssertEqual(lokal?.lebendige.first?.totp, neu.uri, "lokal verschlüsselt gespeichert")
        await a.store.warteAufIdentitaeten()
        let identitaeten = AutoFillIdentitaeten.baue(aus: try XCTUnwrap(a.identitaeten.staende_.last))
        XCTAssertTrue(identitaeten.contains { $0 is ASOneTimeCodeCredentialIdentity }, "Einmalcode-Identität neu gesetzt")
    }

    func testEintragMitCodeFragtErstUndErsetztDannMitVerlauf() async throws {
        let a = try aufbau([Eintrag(id: "a", name: "GitHub", benutzer: "mia", passwort: "pw", urls: ["https://github.com"], totp: "JBSWY3DPEHPK3PXP", geaendert: alt)])
        await a.store.oeffnen()
        let m = modell(a.store)
        await m.waehle(try XCTUnwrap(a.store.eintrag("a")))
        XCTAssertEqual(m.rueckfrage?.id, "a")
        XCTAssertNil(m.fertig)
        XCTAssertEqual(a.store.eintrag("a")?.totp, "JBSWY3DPEHPK3PXP", "vor der Antwort ändert sich nichts")
        await m.ersetze()
        XCTAssertNil(m.rueckfrage)
        XCTAssertEqual(m.fertig?.uri, neu.uri)
        let e = try XCTUnwrap(a.store.eintrag("a"))
        XCTAssertEqual(e.totp, neu.uri)
        XCTAssertEqual(totpVon(e.unbekannt["totpVerlauf"]?.alsListe?.first), "JBSWY3DPEHPK3PXP")
    }

    func testAbbrechenInDerRueckfrageLaesstAllesWieEsWar() async throws {
        let a = try aufbau([Eintrag(id: "a", name: "GitHub", totp: "JBSWY3DPEHPK3PXP", geaendert: alt)])
        await a.store.oeffnen()
        let m = modell(a.store)
        await m.waehle(try XCTUnwrap(a.store.eintrag("a")))
        m.rueckfrage = nil
        XCTAssertNil(m.fertig)
        XCTAssertEqual(a.store.eintrag("a")?.totp, "JBSWY3DPEHPK3PXP")
        XCTAssertNil(a.store.eintrag("a")?.unbekannt["totpVerlauf"])
    }

    func testNeuerEintragWirdAngelegt() async throws {
        let a = try aufbau([])
        await a.store.oeffnen()
        let m = modell(a.store)
        XCTAssertTrue(m.vorschlaege.isEmpty)
        await m.legeNeuAn()
        XCTAssertEqual(m.fertig?.name, "GitHub")
        XCTAssertEqual(a.store.eintraege.count, 1)
        XCTAssertEqual(a.store.eintraege.first?.benutzer, "mia")
        XCTAssertEqual(a.store.eintraege.first?.totp, neu.uri)
    }

    func testWurdeInzwischenGesperrtMeldetDasBlattKeinenErfolg() async throws {
        let a = try aufbau([Eintrag(id: "a", name: "GitHub", geaendert: alt)])
        await a.store.oeffnen()
        let m = modell(a.store)
        let e = try XCTUnwrap(a.store.eintrag("a"))
        a.store.sperren()
        await m.waehle(e)
        XCTAssertNil(m.fertig, "nichts gespeichert, also kein Erfolg und kein Code")
        XCTAssertNotNil(m.fehler)
    }

    func testDerAngezeigteCodeStimmtMitDemGespeichertenSchluesselUeberein() async throws {
        let a = try aufbau([])
        await a.store.oeffnen()
        let m = modell(a.store)
        await m.legeNeuAn()
        let uri = try XCTUnwrap(m.fertig?.uri)
        let z = try XCTUnwrap(TOTPAnzeige.zustand(uri, datum: Date(timeIntervalSince1970: 59)))
        XCTAssertEqual(z.code, TOTP.code(neu.einstellung, zeit: 59))
        XCTAssertEqual(z.code.count, 8)
    }
}
