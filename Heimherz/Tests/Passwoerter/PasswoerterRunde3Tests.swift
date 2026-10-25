import XCTest
@testable import Heimherz

private func login(_ id: String, name: String? = nil, benutzer: String = "mia", urls: [String], pw: String = "Zr7!kQpL92xw-lang", geaendert: String = "2026-10-01T10:00:00.000Z") -> Eintrag {
    Eintrag(id: id, name: name ?? id, benutzer: benutzer, passwort: pw, urls: urls, geaendert: geaendert)
}

/// W-021: doppelte Konten.
final class DoppelteKontenTests: XCTestCase {
    func testGleicherHostOhneWwwUndBenutzerOhneGrossschreibung() {
        let g = DoppelteKonten.finde([
            login("a", name: "Streaming", benutzer: "Mia", urls: ["https://streaming.example.org"]),
            login("b", name: "Streaming alt", benutzer: "mia ", urls: ["https://www.Streaming.example.org/login"]),
            login("c", benutzer: "mia", urls: ["https://anders.example.org"])
        ])
        XCTAssertEqual(g.map(\.ids), [["a", "b"]])
    }

    func testAndererBenutzerLeererBenutzerNotizenUndGrabsteineZaehlenNicht() {
        var weg = login("w", urls: ["https://x.example.org"])
        weg.geloescht = true
        let g = DoppelteKonten.finde([
            login("a", benutzer: "mia", urls: ["https://x.example.org"]),
            login("b", benutzer: "tom", urls: ["https://x.example.org"]),
            login("c", benutzer: "", urls: ["https://y.example.org"]),
            login("d", benutzer: "", urls: ["https://y.example.org"]),
            weg,
            Eintrag(id: "n", art: Eintrag.artNotiz, name: "N", benutzer: "mia", urls: ["https://x.example.org"])
        ])
        XCTAssertEqual(g, [])
    }

    func testEintragMitZweiHostsErzeugtNureineGruppe() {
        let g = DoppelteKonten.finde([
            login("a", name: "A", urls: ["https://x.example.org", "https://y.example.org"]),
            login("b", name: "B", urls: ["https://y.example.org", "https://x.example.org"]),
            login("c", name: "C", urls: ["https://y.example.org"])
        ])
        XCTAssertEqual(g.map(\.ids), [["a", "b", "c"]], "a und b teilen zwei Hosts, c einen: alles eine Gruppe, nichts doppelt")
    }

    func testGruppenSindNachNameSortiert() {
        let g = DoppelteKonten.finde([
            login("z1", name: "Zeitung", urls: ["https://z.example.org"]), login("z2", name: "Zeitung 2", urls: ["https://z.example.org"]),
            login("a1", name: "Amt", urls: ["https://a.example.org"]), login("a2", name: "Amt 2", urls: ["https://a.example.org"])
        ])
        XCTAssertEqual(g.map(\.ids), [["a1", "a2"], ["z1", "z2"]])
    }
}

/// W-014, W-015, W-017, W-020: reine Logik.
final class PasswoerterRunde3LogikTests: XCTestCase {
    private let totp = "JBSWY3DPEHPK3PXP"   // 30 Sekunden, 6 Stellen

    private func datum(sekundeInPeriode s: Int, periode: Int = 0) -> Date {
        Date(timeIntervalSince1970: Double(1_792_886_400 + periode * 30 + s))   // 1_792_886_400 ist durch 30 teilbar
    }

    func testNaechsterCodeNurInDenLetztenFuenfSekunden() throws {
        XCTAssertEqual(1_792_886_400 % 30, 0)
        XCTAssertNil(PasswoerterLogik.naechsterCode(totp, datum: datum(sekundeInPeriode: 0)), "30 Sekunden Rest")
        XCTAssertNil(PasswoerterLogik.naechsterCode(totp, datum: datum(sekundeInPeriode: 24)), "6 Sekunden Rest")
        let bei25 = try XCTUnwrap(PasswoerterLogik.naechsterCode(totp, datum: datum(sekundeInPeriode: 25)), "5 Sekunden Rest")
        let bei29 = try XCTUnwrap(PasswoerterLogik.naechsterCode(totp, datum: datum(sekundeInPeriode: 29)))
        XCTAssertEqual(bei25, bei29, "ganze letzte Periode zeigt denselben nächsten Code")
        XCTAssertEqual(bei25, TOTPAnzeige.zustand(totp, datum: datum(sekundeInPeriode: 0, periode: 1))?.code, "genau der Code der nächsten Periode")
        XCTAssertNotEqual(bei25, TOTPAnzeige.zustand(totp, datum: datum(sekundeInPeriode: 25))?.code)
        XCTAssertNil(PasswoerterLogik.naechsterCode("kein base32 !", datum: datum(sekundeInPeriode: 27)))
    }

    func testKopierterCodeIstInDenLetztenSekundenDerNaechste() throws {
        let frueh = try XCTUnwrap(PasswoerterLogik.codeZumKopieren(totp, datum: datum(sekundeInPeriode: 10)))
        XCTAssertFalse(frueh.istNaechster)
        XCTAssertEqual(frueh.code, TOTPAnzeige.zustand(totp, datum: datum(sekundeInPeriode: 10))?.code)
        let spaet = try XCTUnwrap(PasswoerterLogik.codeZumKopieren(totp, datum: datum(sekundeInPeriode: 27)))
        XCTAssertTrue(spaet.istNaechster)
        XCTAssertEqual(spaet.code, TOTPAnzeige.zustand(totp, datum: datum(sekundeInPeriode: 0, periode: 1))?.code)
        XCTAssertNil(PasswoerterLogik.codeZumKopieren("", datum: datum(sekundeInPeriode: 27)))
    }

    func testPasswortAendernAdresse() {
        XCTAssertEqual(PasswoerterLogik.passwortAendernURL(von: login("a", urls: ["https://github.com/login"]))?.absoluteString, "https://github.com/.well-known/change-password")
        XCTAssertEqual(PasswoerterLogik.passwortAendernURL(von: login("a", urls: ["Konto.Example.org/anmelden?x=1"]))?.absoluteString, "https://konto.example.org/.well-known/change-password", "ohne Schema, Host klein")
        XCTAssertNil(PasswoerterLogik.passwortAendernURL(von: login("a", urls: [])))
        var weg = login("a", urls: ["https://x.example.org"])
        weg.geloescht = true
        XCTAssertNil(PasswoerterLogik.passwortAendernURL(von: weg))
        XCTAssertNil(PasswoerterLogik.passwortAendernURL(von: Eintrag(id: "n", art: Eintrag.artNotiz, name: "N", urls: ["https://x.example.org"])))
    }

    func testFruehereAusHeimUndBitwardenNeuesteZuerstOhneDoppelteUndOhneAktuelles() {
        var e = login("a", urls: ["https://x.example.org"], pw: "jetzt-gueltig")
        e.unbekannt["passwortVerlauf"] = .liste([
            .objekt(["passwort": .text("alt-zwei"), "bis": .text("2026-08-01T10:00:00.000Z")]),
            .objekt(["passwort": .text("alt-eins"), "bis": .text("2026-05-01T10:00:00.000Z")]),
            .objekt(["passwort": .text(""), "bis": .text("2026-04-01T10:00:00.000Z")])
        ])
        e.unbekannt["bitwardenVerlauf"] = .liste([
            .objekt(["password": .text("alt-eins"), "lastUsedDate": .text("2026-05-01T10:00:00.000Z")]),
            .objekt(["password": .text("bw-neu"), "lastUsedDate": .text("2026-09-01T10:00:00.000Z")]),
            .objekt(["password": .text("jetzt-gueltig"), "lastUsedDate": .text("2026-10-01T10:00:00.000Z")]),
            .objekt(["password": .text("ohne-datum")])
        ])
        let z = PasswoerterLogik.fruehere(von: e)
        XCTAssertEqual(z.map(\.passwort), ["bw-neu", "alt-zwei", "alt-eins", "ohne-datum"])
        XCTAssertEqual(z.last?.bis, "")
    }

    func testFruehereLeerOhneVerlauf() {
        XCTAssertEqual(PasswoerterLogik.fruehere(von: login("a", urls: [])), [])
    }

    func testZuletztBenutztNeuesteZuerstNieBenutzteNachName() {
        let a = login("a", name: "Anna", urls: []), b = login("b", name: "Bert", urls: []), c = login("c", name: "Cora", urls: []), d = login("d", name: "Dirk", urls: [])
        let benutzt = ["c": Date(timeIntervalSince1970: 200), "b": Date(timeIntervalSince1970: 100)]
        let abschnitte = PasswoerterLogik.abschnitte([a, b, c, d], sortierung: .zuletztBenutzt, benutzt: benutzt)
        XCTAssertEqual(abschnitte.count, 1)
        XCTAssertEqual(abschnitte[0].eintraege.map(\.id), ["c", "b", "a", "d"])
        XCTAssertEqual(PasswoerterLogik.abschnitte([], sortierung: .zuletztBenutzt), [])
        XCTAssertEqual(PasswoerterLogik.abschnitte([a, b], sortierung: .name).map(\.kennung), ["A", "B"], "bisherige Sortierung bleibt")
    }

    func testNutzungMerkeUndSortierenZusammen() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "heimherz-test-\(UUID().uuidString)"))
        let n = Nutzung(speicher: suite)
        n.merke(id: "b", jetzt: Date(timeIntervalSince1970: 100))
        n.merke(id: "a", jetzt: Date(timeIntervalSince1970: 300))
        let a = login("a", name: "Anna", urls: []), b = login("b", name: "Bert", urls: [])
        XCTAssertEqual(PasswoerterLogik.abschnitte([b, a], sortierung: .zuletztBenutzt, benutzt: n.zuletzt)[0].eintraege.map(\.id), ["a", "b"])
    }
}

/// W-012: Spotlight.
@MainActor
final class SpotlightTests: XCTestCase {
    func testIndexEnthaeltNurTitelUndHostVonLogins() {
        let t = Tresor(eintraege: [
            Eintrag(id: "a", name: "GitHub", benutzer: "mia-geheim", passwort: "pw-geheim", urls: ["https://www.github.com/login"], totp: "JBSWY3DPEHPK3PXP", notiz: "notiz-geheim"),
            Eintrag(id: "n", art: Eintrag.artNotiz, name: "WLAN", notiz: "x"),
            Eintrag(id: "g", name: "Weg", urls: ["https://weg.example.org"], geloescht: true),
            Eintrag(id: "o", name: "", urls: ["https://nur-host.example.org"]),
            Eintrag(id: "leer", name: " ", urls: [])
        ])
        let e = SpotlightIndex.eintraege(aus: t)
        XCTAssertEqual(e, [SpotlightEintrag(id: "a", titel: "GitHub", host: "www.github.com"), SpotlightEintrag(id: "o", titel: "nur-host.example.org", host: "nur-host.example.org")])
        let text = String(describing: e)
        for geheim in ["mia-geheim", "pw-geheim", "notiz-geheim", "JBSWY3DPEHPK3PXP"] { XCTAssertFalse(text.contains(geheim)) }
    }

    func testPostfachGibtDieIdEinmalHeraus() async {
        let store = TresorStore(umgebung: AppUmgebung.vorschau())
        await store.oeffnen()   // Demo: erfundene Einträge, kein Netz
        let p = SpotlightPostfach()
        p.empfange(id: "demo-1")
        XCTAssertEqual(p.nimm(in: store), "demo-1")
        XCTAssertNil(p.nimm(in: store), "nur einmal")
    }

    func testPostfachVerwirftUnbekanntesUndAltes() async {
        let store = TresorStore(umgebung: AppUmgebung.vorschau())
        await store.oeffnen()
        let p = SpotlightPostfach()
        let t0 = Date(timeIntervalSince1970: 1_000)
        p.empfange(id: "gibt-es-nicht", jetzt: t0)
        XCTAssertNil(p.nimm(in: store, jetzt: t0))
        p.empfange(id: "demo-1", jetzt: t0)
        XCTAssertNil(p.nimm(in: store, jetzt: t0.addingTimeInterval(SpotlightPostfach.wartezeit + 1)), "zu lange her")
        XCTAssertNil(p.angefragt)
    }
}
