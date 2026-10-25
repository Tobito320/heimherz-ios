import CryptoKit
import XCTest
@testable import Heimherz

final class KoppelLinkTests: XCTestCase {
    private func link(url: String = "https%3A%2F%2Fpc.example.ts.net", token: String = TestSchluessel.token, schluessel: String = TestSchluessel.schluesselB64url) -> String {
        "heimherz://koppeln?url=\(url)&token=\(token)&schluessel=\(schluessel)"
    }

    func testGueltigerLink() throws {
        let d = try KoppelLink.lese(link())
        XCTAssertEqual(d.url.absoluteString, "https://pc.example.ts.net")
        XCTAssertEqual(d.token, TestSchluessel.token)
        XCTAssertEqual(d.schluessel, TestSchluessel.roh)
    }

    func testTailnetHostEgalWelcheSchreibweise() throws {
        XCTAssertEqual(try KoppelLink.lese(link(url: "https%3A%2F%2FPC.Beispiel.TS.NET")).url.host?.lowercased(), "pc.beispiel.ts.net")
        XCTAssertEqual(KoppelFehler.keinTailnet.nutzerText, "Die Adresse muss ein Tailscale-Name sein (endet auf .ts.net).")
    }

    func testMitLeerraumDrumherum() throws {
        XCTAssertNoThrow(try KoppelLink.lese("  \n" + link() + "\n"))
    }

    func testFehler() {
        let falsch: [(String, KoppelFehler)] = [
            ("https://example.org/", .keinKoppelLink),
            ("heimherz://anders?url=x", .keinKoppelLink),
            ("kein link", .keinKoppelLink),
            ("heimherz://koppeln?token=\(TestSchluessel.token)", .adresseFehlt),
            (link(url: "http%3A%2F%2Fpc.example.ts.net"), .nurHttps),
            (link(url: "pc.example.ts.net"), .nurHttps),
            (link(url: "https%3A%2F%2Fexample.org"), .keinTailnet),
            (link(url: "https%3A%2F%2Fpc.ts.net.evil.example"), .keinTailnet),
            (link(url: "https%3A%2F%2Fpc.ts.net%40evil.example"), .keinTailnet),
            (link(url: "https%3A%2F%2Fevilts.net"), .keinTailnet),
            (link(token: "kurz"), .tokenUngueltig),
            (link(token: TestSchluessel.token + "AA"), .tokenUngueltig),
            (link(schluessel: "AQID"), .schluesselUngueltig),
            (link(schluessel: TestSchluessel.schluesselB64url + "="), .schluesselUngueltig),
            (link(schluessel: "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHy+"), .schluesselUngueltig)
        ]
        for (text, erwartet) in falsch {
            XCTAssertThrowsError(try KoppelLink.lese(text), text) { XCTAssertEqual($0 as? KoppelFehler, erwartet, text) }
        }
    }

    func testKoppelnSpeichertErstNachErfolgreicherTestanfrage() async throws {
        let speicher = MemorySpeicher()
        let bund = Schluesselbund(speicher: speicher)
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            r.value(forHTTPHeaderField: "Authorization") == "Bearer \(TestSchluessel.token)" && r.url?.path == "/v1/status"
                ? .json(#"{"version":"0.1.0","rev":7,"fotos":3,"belegt":10,"frei":20}"#) : Antwort401.antwort
        }
        let text = link(url: HeimClient.kodiere(basis.absoluteString))
        let status = try await Koppeln.koppeln(link: text, bund: bund, sitzung: sitzung)
        XCTAssertEqual(status.rev, 7)
        XCTAssertEqual(try bund.ladeGeraet(), Geraet(url: basis, token: TestSchluessel.token))
        XCTAssertEqual(try speicher.lesen(Schluesselbund.kontoSchluessel, kontext: nil), TestSchluessel.roh)
        XCTAssertEqual(speicher.mitAbfrage(Schluesselbund.kontoSchluessel), true, "K nur mit Face ID oder Code")
        XCTAssertEqual(speicher.mitAbfrage(Schluesselbund.kontoToken), false)
        XCTAssertEqual(speicher.mitAbfrage(Schluesselbund.kontoURL), false)
    }

    func testKoppelnOhneErfolgSpeichertNichts() async throws {
        let speicher = MemorySpeicher()
        let bund = Schluesselbund(speicher: speicher)
        let (sitzung, basis) = FakeNetz.neu { _, _ in Antwort401.antwort }
        let text = link(url: HeimClient.kodiere(basis.absoluteString))
        do {
            _ = try await Koppeln.koppeln(link: text, bund: bund, sitzung: sitzung)
            XCTFail("401 muss scheitern")
        } catch {
            XCTAssertEqual(error as? HeimFehler, .nichtBerechtigt)
        }
        XCTAssertNil(try bund.ladeGeraet())
        XCTAssertNil(try speicher.lesen(Schluesselbund.kontoSchluessel, kontext: nil))
    }

    func testEntkoppelnLoeschtAlles() throws {
        let bund = Schluesselbund(speicher: MemorySpeicher())
        try bund.speichereSchluessel(TestSchluessel.schluessel)
        try bund.speichereGeraet(Geraet(url: URL(string: "https://x.example") ?? URL(fileURLWithPath: "/"), token: "t"))
        try bund.vergiss()
        XCTAssertNil(try bund.ladeGeraet())
    }

    func testVergissVersuchtAllesAuchWennEinEintragKlemmt() throws {
        final class Klemmt: KeychainSpeicher, @unchecked Sendable {
            let innen = MemorySpeicher()
            func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? { try innen.lesen(konto, kontext: kontext) }
            func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws { try innen.schreiben(konto, daten: daten, mitAbfrage: mitAbfrage) }
            func loeschen(_ konto: String) throws {
                if konto == Schluesselbund.kontoSchluessel { throw SchluesselbundFehler.loeschen(-1) }
                try innen.loeschen(konto)
            }
        }
        let speicher = Klemmt()
        let bund = Schluesselbund(speicher: speicher)
        try bund.speichereSchluessel(TestSchluessel.schluessel)
        try bund.speichereGeraet(Geraet(url: URL(string: "https://x.ts.net") ?? URL(fileURLWithPath: "/"), token: "t"))
        XCTAssertThrowsError(try bund.vergiss()) { XCTAssertEqual($0 as? SchluesselbundFehler, .loeschen(-1)) }
        XCTAssertNil(try bund.ladeGeraet(), "Token und URL sind trotzdem weg")
    }

    func testSchluesselLaedt() async throws {
        let bund = Schluesselbund(speicher: MemorySpeicher())
        let leer = try await bund.ladeSchluessel()
        XCTAssertNil(leer)
        try bund.speichereSchluessel(TestSchluessel.schluessel)
        let k = try await bund.ladeSchluessel(kontext: EntsperrKontext())
        XCTAssertEqual(k.map { $0.withUnsafeBytes { Data($0) } }, TestSchluessel.roh)
    }
}

enum Antwort401 {
    static let antwort = FakeNetz.Antwort(status: 401)
}
