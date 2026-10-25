import CryptoKit
import XCTest
@testable import Heimherz

private struct UmschlagFixture: Decodable {
    let schluessel: String
    let tresor: Tresor
    let umschlag: Umschlag
}

final class UmschlagTests: XCTestCase {
    func testFixtureAusTSLiesstSichInSwift() throws {
        let f = try Fixture.lade(UmschlagFixture.self, "tresor", "umschlag-1.json")
        XCTAssertEqual(Data(base64Encoded: f.schluessel), TestSchluessel.roh)
        let tresor = try f.umschlag.oeffne(schluessel: TestSchluessel.schluessel)
        XCTAssertEqual(tresor, f.tresor)
        XCTAssertEqual(tresor.eintraege.first?.passwort, "Grüne-Wiese-42!")
    }

    func testKlartextIstByteGleichZuJSONStringifyAusTS() throws {
        let f = try Fixture.lade(UmschlagFixture.self, "tresor", "umschlag-1.json")
        let nonce = try AES.GCM.Nonce(data: XCTUnwrap(Data(base64Encoded: f.umschlag.nonce)))
        let d = try XCTUnwrap(Data(base64Encoded: f.umschlag.daten))
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: d.dropLast(16), tag: d.suffix(16))
        let klar = try AES.GCM.open(box, using: TestSchluessel.schluessel, authenticating: Umschlag.aad)
        XCTAssertEqual(String(decoding: klar, as: UTF8.self), f.tresor.json())
    }

    func testMitFesterNonceByteGleichZurTSFixture() throws {
        let f = try Fixture.lade(UmschlagFixture.self, "tresor", "umschlag-1.json")
        let nonce = try AES.GCM.Nonce(data: XCTUnwrap(Data(base64Encoded: f.umschlag.nonce)))
        let neu = try Umschlag.verschliesse(f.tresor, schluessel: TestSchluessel.schluessel, rev: f.umschlag.rev, nonce: nonce)
        XCTAssertEqual(neu, f.umschlag)
    }

    func testRundeMitZufallsNonceUndUnbekanntenFeldern() throws {
        var e = testEintrag("a")
        e.unbekannt = ["farbe": .text("gruen"), "zahl": .zahl(1), "tief": .objekt(["b": .liste([.zahl(1), .null, .bool(true)]), "a": .text("x")])]
        let tresor = Tresor(eintraege: [e], unbekannt: ["spaeter": .objekt(["a": .zahl(1)])])
        let u1 = try Umschlag.verschliesse(tresor, schluessel: TestSchluessel.schluessel)
        let u2 = try Umschlag.verschliesse(tresor, schluessel: TestSchluessel.schluessel)
        XCTAssertNotEqual(u1.nonce, u2.nonce)
        XCTAssertTrue(u1.istGueltigeForm)
        XCTAssertEqual(try u1.oeffne(schluessel: TestSchluessel.schluessel), tresor)
    }

    func testFalscherSchluesselScheitert() throws {
        let u = try Umschlag.verschliesse(Tresor(), schluessel: TestSchluessel.schluessel)
        let falsch = SymmetricKey(data: Data(repeating: 9, count: 32))
        XCTAssertThrowsError(try u.oeffne(schluessel: falsch)) { XCTAssertEqual($0 as? TresorFehler, .entschluesselungFehlgeschlagen) }
    }

    func testVeraenderteDatenScheitern() throws {
        var u = try Umschlag.verschliesse(Tresor(eintraege: [testEintrag("a")]), schluessel: TestSchluessel.schluessel)
        var d = try XCTUnwrap(Data(base64Encoded: u.daten))
        d[0] ^= 0xFF
        u.daten = d.base64EncodedString()
        XCTAssertThrowsError(try u.oeffne(schluessel: TestSchluessel.schluessel)) { XCTAssertEqual($0 as? TresorFehler, .entschluesselungFehlgeschlagen) }
    }

    func testFormPruefung() throws {
        let gut = try Umschlag.verschliesse(Tresor(), schluessel: TestSchluessel.schluessel)
        XCTAssertTrue(gut.istGueltigeForm)
        var v2 = gut; v2.v = 2
        var kurzeNonce = gut; kurzeNonce.nonce = Data(count: 8).base64EncodedString()
        var kurzeDaten = gut; kurzeDaten.daten = Data(count: 8).base64EncodedString()
        var negativ = gut; negativ.rev = -1
        for u in [v2, kurzeNonce, kurzeDaten, negativ] {
            XCTAssertFalse(u.istGueltigeForm)
            XCTAssertThrowsError(try u.oeffne(schluessel: TestSchluessel.schluessel)) { XCTAssertEqual($0 as? TresorFehler, .umschlagUngueltig) }
        }
    }

    func testSchluesselMussZweiUndDreissigByteHaben() {
        XCTAssertThrowsError(try TresorSchluessel.aus(Data(count: 31))) { XCTAssertEqual($0 as? TresorFehler, .schluesselLaenge) }
        XCTAssertNoThrow(try TresorSchluessel.aus(Data(count: 32)))
    }
}

final class TresorModellTests: XCTestCase {
    func testJSONTextWieJSONStringifyUndUnbekanntesBleibt() throws {
        let roh = #"{"format":1,"eintraege":[{"id":"i","art":"login","name":"a\"b\\c\n\t\u001f/ü€😀","benutzer":"","passwort":"","urls":["https://x.org/a"],"totp":"","notiz":"","favorit":true,"geaendert":"2026-10-25T01:40:00.000Z","geloescht":false,"farbe":"gruen","zahl":1,"tief":{"b":[1,null,true],"a":"x"}}],"spaeter":{"a":1}}"#
        let tresor = try Tresor.aus(daten: Data(roh.utf8))
        XCTAssertEqual(tresor.eintraege[0].unbekannt["zahl"], .zahl(1))
        XCTAssertEqual(tresor.unbekannt["spaeter"], .objekt(["a": .zahl(1)]))
        // Bekannte Felder in SPEC-Reihenfolge wie in TS; unbekannte Schlüssel stehen danach nach Bytes sortiert (TS behält die Eingabe-Reihenfolge).
        let erwartet = #"{"format":1,"eintraege":[{"id":"i","art":"login","name":"a\"b\\c\n\t\u001f/ü€😀","benutzer":"","passwort":"","urls":["https://x.org/a"],"totp":"","notiz":"","favorit":true,"geaendert":"2026-10-25T01:40:00.000Z","geloescht":false,"farbe":"gruen","tief":{"a":"x","b":[1,null,true]},"zahl":1}],"spaeter":{"a":1}}"#
        XCTAssertEqual(tresor.json(), erwartet)
        XCTAssertEqual(try Tresor.aus(daten: Data(tresor.json().utf8)), tresor)
    }

    func testCodableUndJSONTextSindDieselbeSache() throws {
        let tresor = Tresor(eintraege: [testEintrag("a")], unbekannt: ["x": .bool(false)])
        let ueberCodable = try JSONDecoder().decode(Tresor.self, from: JSONEncoder().encode(tresor))
        XCTAssertEqual(ueberCodable, tresor)
    }

    func testNeueresFormatWirdNichtGelesen() {
        XCTAssertThrowsError(try Tresor.aus(daten: Data(#"{"format":2,"eintraege":[]}"#.utf8))) { XCTAssertEqual($0 as? TresorFehler, .formatUnbekannt(2)) }
    }

    func testKaputterInhaltUndEintragOhneId() {
        XCTAssertThrowsError(try Tresor.aus(daten: Data("kein json".utf8))) { XCTAssertEqual($0 as? TresorFehler, .inhaltUngueltig) }
        XCTAssertThrowsError(try Tresor.aus(daten: Data(#"{"format":1,"eintraege":[{"name":"x"}]}"#.utf8))) { XCTAssertEqual($0 as? TresorFehler, .inhaltUngueltig) }
    }

    func testGrabsteinLeertDieInhalte() {
        let g = testEintrag("a").alsGrabstein(geaendert: "2026-10-02T00:00:00.000Z")
        XCTAssertTrue(g.geloescht)
        XCTAssertEqual([g.name, g.benutzer, g.passwort, g.totp, g.notiz], ["", "", "", "", ""])
        XCTAssertEqual(g.urls, [])
        XCTAssertEqual(g.geaendert, "2026-10-02T00:00:00.000Z")
    }

    func testLebendigeOhneGrabsteine() {
        let t = Tresor(eintraege: [testEintrag("a"), testEintrag("b", geloescht: true)])
        XCTAssertEqual(t.lebendige.map(\.id), ["a"])
    }
}

final class ZeitTests: XCTestCase {
    func testBekannteWerte() {
        XCTAssertEqual(Zeit.millis(iso: "2026-10-25T00:00:00.000Z"), 1_792_886_400_000)
        XCTAssertEqual(Zeit.millis(iso: "2000-02-29T23:59:59.999Z"), 951_868_799_999)
        XCTAssertEqual(Zeit.millis(iso: "1969-12-31T23:59:59.001Z"), -999)
        XCTAssertEqual(Zeit.millis(iso: "2026-10-25T00:00:00Z"), 1_792_886_400_000)
        XCTAssertEqual(Zeit.millis(iso: "2026-10-25T00:00:00.5Z"), 1_792_886_400_500)
    }

    func testRundeHinUndZurueck() {
        for text in ["2026-10-25T01:40:00.000Z", "1970-01-01T00:00:00.000Z", "2000-02-29T23:59:59.999Z", "1969-12-31T23:59:59.001Z", "2100-03-01T12:00:00.123Z"] {
            XCTAssertEqual(Zeit.millis(iso: text).map { Zeit.iso(millis: $0) }, text)
        }
        XCTAssertEqual(Zeit.iso(Date(timeIntervalSince1970: 1_792_886_400.5)), "2026-10-25T00:00:00.500Z")
    }

    func testUngueltigeFormen() {
        for text in ["", "heute", "2026-10-25", "2026-10-25T00:00:00", "2026-13-25T00:00:00.000Z", "2026-10-25 00:00:00.000Z", "2026-10-25T25:00:00.000Z", "2026-10-25T00:00:00.Z"] {
            XCTAssertNil(Zeit.millis(iso: text), text)
        }
    }
}

private struct MergeFixture: Decodable {
    let beschreibung: String
    let jetzt: String
    let a: Tresor
    let b: Tresor
    let erwartet: Tresor
}

final class ZusammenfuehrenTests: XCTestCase {
    func testAlleFixturesInBeideRichtungen() throws {
        let dateien = try Fixture.dateien("merge")
        XCTAssertGreaterThanOrEqual(dateien.count, 8, "Fixtures nicht gefunden")
        for datei in dateien {
            let f = try Fixture.lade(MergeFixture.self, "merge", datei)
            let ms = try XCTUnwrap(Zeit.millis(iso: f.jetzt))
            let jetzt = Date(timeIntervalSince1970: Double(ms) / 1000)
            XCTAssertEqual(Zusammenfuehren.zusammenfuehren(f.a, f.b, jetzt: jetzt), f.erwartet, f.beschreibung)
            // Reihenfolge egal: beide Geräte kommen auf dieselben Einträge
            XCTAssertEqual(Zusammenfuehren.zusammenfuehren(f.b, f.a, jetzt: jetzt).eintraege, f.erwartet.eintraege, f.beschreibung)
        }
    }

    func testGleichstandNimmtGroessereBytesNichtSwiftStringVergleich() {
        // "Äpfel" (UTF-8 C3 84 ...) ist in Bytes größer als "zebra" (7A ...), im Swift-Stringvergleich wäre es andersherum.
        let a = testEintrag("x", passwort: "Äpfel")
        let b = testEintrag("x", passwort: "zebra")
        XCTAssertTrue(Zusammenfuehren.gewinnt(a, b))
        XCTAssertFalse(Zusammenfuehren.gewinnt(b, a))
    }

    func testKanonischGleicheIdsBleibenGetrennt() {
        // "é" einmal zusammengesetzt, einmal als e + Akzent: Swift hält sie für gleich, TS und Server nicht.
        let t = Zusammenfuehren.zusammenfuehren(Tresor(eintraege: [testEintrag("\u{E9}")]), Tresor(eintraege: [testEintrag("e\u{301}")]))
        XCTAssertEqual(t.eintraege.count, 2)
    }

    func testGrabsteinGrenzeNeunzigTage() {
        let jetzt = Date(timeIntervalSince1970: 1_792_886_400)   // 2026-10-25
        let knapp = testEintrag("knapp", geaendert: "2026-07-27T00:00:00.000Z", geloescht: true)    // genau 90 Tage
        let alt = testEintrag("alt", geaendert: "2026-07-26T23:59:59.999Z", geloescht: true)
        let lebend = testEintrag("lebend", geaendert: "2020-01-01T00:00:00.000Z")
        let t = Zusammenfuehren.zusammenfuehren(Tresor(eintraege: [knapp, alt, lebend]), Tresor(), jetzt: jetzt)
        XCTAssertEqual(t.eintraege.map(\.id), ["knapp", "lebend"])
    }
}
