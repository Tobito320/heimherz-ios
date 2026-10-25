import XCTest
@testable import Heimherz

private final class FakeMitteilungen: MitteilungsDienst, Sendable {
    let texte = Kasten<[String]>([])
    func erlaubnisFragen() async {}
    func erlaubt() async -> Bool? { true }
    func zeige(text: String) async { texte.mit { $0.append(text) } }
}

final class FotoMitteilungTests: XCTestCase {
    private func einstellungen(an: Bool? = nil) throws -> GeteilteEinstellungen {
        let name = "heimherz-test-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let e = GeteilteEinstellungen(speicher: d)
        if let an { e.fotoMitteilung = an }
        return e
    }

    func testText() {
        XCTAssertEqual(FotoMitteilung.text(gesichert: 1), "1 Foto gesichert")
        XCTAssertEqual(FotoMitteilung.text(gesichert: 2), "2 Fotos gesichert")
        XCTAssertEqual(FotoMitteilung.text(gesichert: 1_234), "\(1_234.formatted()) Fotos gesichert")
    }

    func testMeldetNurWennEtwasAnkamUndDerSchalterAnIst() {
        XCTAssertTrue(FotoMitteilung.sollMelden(gesichert: 3, vomNutzerAngehalten: false, schalterAn: true))
        XCTAssertFalse(FotoMitteilung.sollMelden(gesichert: 0, vomNutzerAngehalten: false, schalterAn: true), "nichts gesichert")
        XCTAssertFalse(FotoMitteilung.sollMelden(gesichert: 3, vomNutzerAngehalten: false, schalterAn: false), "Schalter aus")
        XCTAssertFalse(FotoMitteilung.sollMelden(gesichert: 3, vomNutzerAngehalten: true, schalterAn: true), "Anhalten meldet nichts")
    }

    func testStandardIstAn() async throws {
        let dienst = FakeMitteilungen()
        let an = try einstellungen().fotoMitteilung
        let gemeldet = await FotoMitteilung.meldeNachLauf(gesichert: 5, vomNutzerAngehalten: false, schalterAn: an, dienst: dienst)
        XCTAssertTrue(gemeldet)
        XCTAssertEqual(dienst.texte.mit { $0 }, ["5 Fotos gesichert"])
    }

    func testSchalterAusSendetNichts() async throws {
        let dienst = FakeMitteilungen()
        let an = try einstellungen(an: false).fotoMitteilung
        let gemeldet = await FotoMitteilung.meldeNachLauf(gesichert: 5, vomNutzerAngehalten: false, schalterAn: an, dienst: dienst)
        XCTAssertFalse(gemeldet)
        XCTAssertEqual(dienst.texte.mit { $0 }, [])
    }

    func testAnhaltenUndNullSendenNichts() async throws {
        let dienst = FakeMitteilungen()
        let e = try einstellungen(an: true)
        let a = await FotoMitteilung.meldeNachLauf(gesichert: 5, vomNutzerAngehalten: true, schalterAn: e.fotoMitteilung, dienst: dienst)
        let b = await FotoMitteilung.meldeNachLauf(gesichert: 0, vomNutzerAngehalten: false, schalterAn: e.fotoMitteilung, dienst: dienst)
        XCTAssertFalse(a || b)
        XCTAssertEqual(dienst.texte.mit { $0 }, [])
    }
}
