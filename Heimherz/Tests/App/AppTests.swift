import XCTest
@testable import Heimherz

final class BuildAblaufTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400 + 3_600)   // 2026-10-25 01:00 UTC

    func testVerbleibendeTage() {
        XCTAssertEqual(BuildAblauf.verbleibendeTage(buildDatum: "2026-10-25", jetzt: jetzt), 90)
        XCTAssertEqual(BuildAblauf.verbleibendeTage(buildDatum: "2026-08-11", jetzt: jetzt), 15)
        XCTAssertEqual(BuildAblauf.verbleibendeTage(buildDatum: "2026-07-27", jetzt: jetzt), 0)
        XCTAssertEqual(BuildAblauf.verbleibendeTage(buildDatum: "2026-07-26", jetzt: jetzt), -1)
    }

    func testKeinHinweisVorTag75() {
        XCTAssertNil(BuildAblauf.hinweis(buildDatum: "2026-10-25", jetzt: jetzt))
        XCTAssertNil(BuildAblauf.hinweis(buildDatum: "2026-08-12", jetzt: jetzt), "Tag 74")
    }

    func testHinweisAbTag75() {
        XCTAssertEqual(BuildAblauf.hinweis(buildDatum: "2026-08-11", jetzt: jetzt), .init(text: "Build läuft in 15 Tagen ab", abgelaufen: false))
        XCTAssertEqual(BuildAblauf.hinweis(buildDatum: "2026-07-28", jetzt: jetzt)?.text, "Build läuft in 1 Tag ab")
        XCTAssertEqual(BuildAblauf.hinweis(buildDatum: "2026-07-27", jetzt: jetzt)?.text, "Build läuft heute ab")
        XCTAssertEqual(BuildAblauf.hinweis(buildDatum: "2026-07-26", jetzt: jetzt)?.abgelaufen, true)
    }

    func testOhneGueltigesDatumKeinHinweis() {
        for text in [nil, "", "heute", "2026-13-01", "26-10-25"] {
            XCTAssertNil(BuildAblauf.hinweis(buildDatum: text, jetzt: jetzt), text ?? "nil")
        }
    }
}

@MainActor
final class SperreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_886_400)

    func testLogik() {
        XCTAssertFalse(SperrLogik.sollSperren(hintergrundSeit: nil, jetzt: t0))
        XCTAssertFalse(SperrLogik.sollSperren(hintergrundSeit: t0, jetzt: t0.addingTimeInterval(299)))
        XCTAssertTrue(SperrLogik.sollSperren(hintergrundSeit: t0, jetzt: t0.addingTimeInterval(300)))
    }

    func testSperrtErstNachFuenfMinutenImHintergrund() {
        let s = AppSperre(gesperrt: false, aktiv: true)
        s.szene(.background, jetzt: t0)
        s.szene(.inactive, jetzt: t0.addingTimeInterval(10))
        s.szene(.active, jetzt: t0.addingTimeInterval(299))
        XCTAssertFalse(s.gesperrt)
        s.szene(.background, jetzt: t0.addingTimeInterval(400))
        s.szene(.active, jetzt: t0.addingTimeInterval(400 + 301))
        XCTAssertTrue(s.gesperrt)
    }

    func testKaltstartGekoppeltIstGesperrtUngekoppeltNicht() {
        XCTAssertTrue(AppSperre(gesperrt: true, aktiv: true).gesperrt)
        XCTAssertFalse(AppSperre(gesperrt: false, aktiv: true).gesperrt)
    }

    func testVerdecktSofortBeiInaktivUndHintergrundUnabhaengigVonDerSperrzeit() {
        let s = AppSperre(gesperrt: false, aktiv: true)
        XCTAssertFalse(s.verdeckt)
        s.szene(.inactive, jetzt: t0)
        XCTAssertTrue(s.verdeckt)
        s.szene(.active, jetzt: t0.addingTimeInterval(1))
        XCTAssertFalse(s.verdeckt)
        XCTAssertFalse(s.gesperrt, "nach einer Sekunde keine Sperre, nur die Deckfläche war kurz da")
        s.szene(.background, jetzt: t0.addingTimeInterval(10))
        XCTAssertTrue(s.verdeckt)
        s.szene(.inactive, jetzt: t0.addingTimeInterval(11))
        XCTAssertTrue(s.verdeckt)
        s.szene(.active, jetzt: t0.addingTimeInterval(12))
        XCTAssertFalse(s.verdeckt)
        XCTAssertFalse(s.gesperrt)
    }

    func testNeuerKontextBeiJederSperre() {
        let s = AppSperre(gesperrt: false, aktiv: true)
        let erster = s.kontext.kontext
        s.szene(.background, jetzt: t0)
        s.szene(.active, jetzt: t0.addingTimeInterval(10))
        XCTAssertTrue(s.kontext.kontext === erster, "ohne Sperre bleibt der Kontext")
        s.szene(.background, jetzt: t0.addingTimeInterval(20))
        s.szene(.active, jetzt: t0.addingTimeInterval(400))
        XCTAssertTrue(s.gesperrt)
        XCTAssertFalse(s.kontext.kontext === erster, "nach dem Sperren ein frischer Kontext")
    }

    func testInaktivSperrtNie() {
        let s = AppSperre(gesperrt: true, aktiv: false)
        s.szene(.inactive, jetzt: t0)
        XCTAssertFalse(s.verdeckt, "in Demo und Test-Host nie")
        s.szene(.background, jetzt: t0)
        s.szene(.active, jetzt: t0.addingTimeInterval(9_999))
        XCTAssertFalse(s.gesperrt)
    }
}

@MainActor
final class AppUmgebungTests: XCTestCase {
    private func umgebung(_ sitzung: URLSession = .shared) throws -> (AppUmgebung, SpeicherImRAM) {
        let speicher = SpeicherImRAM()
        let u = AppUmgebung(bund: Schluesselbund(speicher: speicher), ablage: TresorAblage(ordner: try tempOrdner()), sitzung: sitzung, sperreAktiv: false)
        return (u, speicher)
    }

    func testUngekoppeltHatKeinenClient() throws {
        let (u, _) = try umgebung()
        XCTAssertFalse(u.istGekoppelt)
        XCTAssertThrowsError(try u.client()) { XCTAssertEqual($0 as? HeimFehler, .nichtGekoppelt) }
    }

    func testKoppelnUndEntkoppeln() async throws {
        let (sitzung, basis) = FakeNetz.neu { _, _ in .json(#"{"version":"0.1.0","rev":3,"fotos":9}"#) }
        let (u, speicher) = try umgebung(sitzung)
        let link = "heimherz://koppeln?url=\(HeimClient.kodiere(basis.absoluteString))&token=\(TestSchluessel.token)&schluessel=\(TestSchluessel.schluesselB64url)"
        try await u.koppeln(link: link)
        XCTAssertTrue(u.istGekoppelt)
        XCTAssertEqual(u.status?.rev, 3)
        XCTAssertEqual(try u.client().token, TestSchluessel.token)
        XCTAssertEqual(speicher.mitAbfrage(Schluesselbund.kontoSchluessel), true)

        try await u.tresorDienst().speichereLokal(Tresor(eintraege: [testEintrag("a")]), schluessel: TestSchluessel.schluessel)
        XCTAssertNotNil(try u.ablage.lade())
        try u.entkoppeln()
        XCTAssertFalse(u.istGekoppelt)
        XCTAssertNil(u.status)
        XCTAssertNil(try u.ablage.lade(), "lokaler Tresor-Cache bleibt nicht liegen")
        XCTAssertNil(try speicher.lesen(Schluesselbund.kontoSchluessel, kontext: nil))
    }

    private func gekoppelt(_ sitzung: URLSession, basis: URL) async throws -> (AppUmgebung, SpeicherImRAM) {
        let (u, speicher) = try umgebung(sitzung)
        let link = "heimherz://koppeln?url=\(HeimClient.kodiere(basis.absoluteString))&token=\(TestSchluessel.token)&schluessel=\(TestSchluessel.schluesselB64url)"
        try await u.koppeln(link: link)
        return (u, speicher)
    }

    func testPruefungOhneEintraegeUndNachAbgleichIstAlleAmPC() async throws {
        let (sitzung, basis) = FakeNetz.neu { r, _ in r.httpMethod == "GET" && r.url?.path == "/v1/tresor" ? .init(status: 404) : .json(#"{"version":"0.1.0","rev":3,"fotos":9}"#) }
        let (u, _) = try await gekoppelt(sitzung, basis: basis)
        let leer = await u.pruefeVorEntkoppeln()
        XCTAssertEqual(leer, .alleAmPC)
    }

    func testPruefungOhnePCZaehltUngesendeteEintraegeUndMitPCBleibtNichtsOffen() async throws {
        let erreichbar = Kasten<Bool>(false)
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            if r.url?.path == "/v1/status" { return .json(#"{"version":"0.1.0","rev":3,"fotos":9}"#) }
            if !erreichbar.mit({ $0 }) { return .fehler(.notConnectedToInternet) }
            if r.httpMethod == "GET" { return .init(status: 404) }
            return .json(#"{"v":1,"rev":1,"nonce":"AAAAAAAAAAAAAAAA","daten":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#)
        }
        let (u, _) = try await gekoppelt(sitzung, basis: basis)
        try await u.tresorDienst().speichereLokal(Tresor(eintraege: [testEintrag("a"), testEintrag("b")]), schluessel: TestSchluessel.schluessel)
        let p = await u.pruefeVorEntkoppeln()
        XCTAssertEqual(p, .offen(2))
        XCTAssertTrue(p.nachricht.hasPrefix("2 Änderungen noch nicht am PC."))
        XCTAssertFalse(p.nachricht.contains("Am PC bleibt alles"), "nur sagen, wenn es stimmt")
        erreichbar.mit { $0 = true }
        let danach = await u.pruefeVorEntkoppeln()
        XCTAssertEqual(danach, .alleAmPC, "der letzte Abgleich hat alles hochgeschickt")
    }

    func testNachrichtenZumEntkoppeln() {
        XCTAssertTrue(EntkoppelPruefung.alleAmPC.nachricht.contains("Am PC bleibt alles"))
        XCTAssertTrue(EntkoppelPruefung.offen(1).nachricht.hasPrefix("1 Änderung noch nicht am PC."))
        XCTAssertFalse(EntkoppelPruefung.unbekannt.nachricht.contains("Am PC bleibt alles"))
    }

    func testEntkoppelnMeldetFehlerStattSieZuVerschlucken() throws {
        final class Klemmt: KeychainSpeicher, @unchecked Sendable {
            let innen = MemorySpeicher()
            func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? { try innen.lesen(konto, kontext: kontext) }
            func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws { try innen.schreiben(konto, daten: daten, mitAbfrage: mitAbfrage) }
            func loeschen(_ konto: String) throws {
                if konto == Schluesselbund.kontoToken { throw SchluesselbundFehler.loeschen(-25244) }
                try innen.loeschen(konto)
            }
        }
        let bund = Schluesselbund(speicher: Klemmt())
        try bund.speichereGeraet(Geraet(url: URL(string: "https://pc.ts.net") ?? URL(fileURLWithPath: "/"), token: "t"))
        let u = AppUmgebung(bund: bund, ablage: TresorAblage(ordner: try tempOrdner()), sperreAktiv: false)
        XCTAssertTrue(u.istGekoppelt)
        XCTAssertThrowsError(try u.entkoppeln()) { XCTAssertEqual($0 as? SchluesselbundFehler, .loeschen(-25244)) }
        XCTAssertFalse(u.istGekoppelt, "URL und Schlüssel sind trotz des Fehlers weg, ohne Token gibt es keinen Zugang")
    }

    func testNeuerZugangErsetztDenAltenCacheUndZaehltHoch() async throws {
        let (sitzung, basis) = FakeNetz.neu { _, _ in .json(#"{"version":"0.1.0","rev":3,"fotos":9}"#) }
        let (u, _) = try await gekoppelt(sitzung, basis: basis)
        let vorher = u.kopplung
        try await u.tresorDienst().speichereLokal(Tresor(eintraege: [testEintrag("a")]), schluessel: TestSchluessel.schluessel)
        let link = "heimherz://koppeln?url=\(HeimClient.kodiere(basis.absoluteString))&token=\(TestSchluessel.token)&schluessel=\(TestSchluessel.schluesselB64url)"
        try await u.koppeln(link: link)
        XCTAssertEqual(u.kopplung, vorher + 1)
        XCTAssertNil(try u.ablage.lade(), "der Cache gehörte zum alten Zugang")
    }

    func testFremdeAdresseKopptNicht() async throws {
        let (u, speicher) = try umgebung()
        let link = "heimherz://koppeln?url=https%3A%2F%2Fexample.org&token=\(TestSchluessel.token)&schluessel=\(TestSchluessel.schluesselB64url)"
        do { try await u.koppeln(link: link); XCTFail() } catch { XCTAssertEqual(error as? KoppelFehler, .keinTailnet) }
        XCTAssertFalse(u.istGekoppelt)
        XCTAssertNil(try speicher.lesen(Schluesselbund.kontoSchluessel, kontext: nil))
    }

    func testStatusFehlerWirdAlsTextGemerkt() async throws {
        let (sitzung, basis) = FakeNetz.neu { _, _ in .fehler(.cannotConnectToHost) }
        let (u, _) = try umgebung(sitzung)
        try u.bund.speichereGeraet(Geraet(url: basis, token: TestSchluessel.token))
        let u2 = AppUmgebung(bund: u.bund, ablage: u.ablage, sitzung: sitzung, sperreAktiv: false)
        await u2.ladeStatus()
        XCTAssertEqual(u2.statusFehler, HeimFehler.nichtErreichbar.nutzerText)
        XCTAssertNil(u2.status)
    }
}

/// Kontraste nach WCAG 2.1: Text 4,5:1, Linien und Knopfflächen 3:1, in hell und dunkel.
final class FarbenKontrastTests: XCTestCase {
    private static func leuchtdichte(_ hex: UInt32) -> Double {
        func kanal(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * kanal(16) + 0.7152 * kanal(8) + 0.0722 * kanal(0)
    }

    static func verhaeltnis(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (leuchtdichte(a), leuchtdichte(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testPaare() {
        let text: [(FarbToken, [FarbToken])] = [
            (Palette.tinte, [Palette.grund, Palette.karte, Palette.grundWarm, Palette.chip, Palette.karteZart, Palette.heroEins, Palette.heroZwei, Palette.heroDrei]),
            (Palette.tinte2, [Palette.grund, Palette.karte, Palette.grundWarm, Palette.chip, Palette.heroEins, Palette.heroZwei, Palette.heroDrei]),
            (Palette.tinte3, [Palette.grund, Palette.karte]),
            (Palette.gruen, [Palette.grund, Palette.karte, Palette.chip]),
            (Palette.herz, [Palette.grund, Palette.karte]),
            (Palette.ok, [Palette.okGrund, Palette.karte]),
            (Palette.warn, [Palette.warnGrund, Palette.karte]),
            (Palette.schlecht, [Palette.schlechtGrund, Palette.karte]),
            (Palette.aufKnopf, [Palette.knopf])
        ]
        let flaechen: [(FarbToken, [FarbToken])] = [(Palette.linie, [Palette.grund, Palette.karte]), (Palette.knopf, [Palette.grund])]
        for (modus, dunkel) in [("hell", false), ("dunkel", true)] {
            for hoch in [false, true] {
                for (vorn, hintergruende) in text {
                    for hinten in hintergruende {
                        let v = Self.verhaeltnis(vorn.hex(dunkelModus: dunkel, hoch: hoch), hinten.hex(dunkelModus: dunkel, hoch: hoch))
                        XCTAssertGreaterThanOrEqual(v, 4.5, "\(vorn.name) auf \(hinten.name) (\(modus), hoch \(hoch))")
                    }
                }
                for (vorn, hintergruende) in flaechen {
                    for hinten in hintergruende {
                        let v = Self.verhaeltnis(vorn.hex(dunkelModus: dunkel, hoch: hoch), hinten.hex(dunkelModus: dunkel, hoch: hoch))
                        XCTAssertGreaterThanOrEqual(v, 3.0, "\(vorn.name) auf \(hinten.name) (\(modus), hoch \(hoch))")
                    }
                }
            }
        }
    }
}
