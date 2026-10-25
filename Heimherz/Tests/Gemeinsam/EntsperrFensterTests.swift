import CryptoKit
import Foundation
import Synchronization
import XCTest
@testable import Heimherz

/// Eine Uhr und eine Dauer zum Verstellen, damit die Tests nicht warten.
private final class Regler: @unchecked Sendable {
    private let uhr = Mutex(Date(timeIntervalSince1970: 1_792_886_400))
    private let laenge = Mutex(EntsperrDauer.fuenfMinuten)
    var jetzt: Date { uhr.withLock { $0 } }
    var dauer: EntsperrDauer {
        get { laenge.withLock { $0 } }
        set { laenge.withLock { $0 = newValue } }
    }
    func vor(_ s: TimeInterval) { uhr.withLock { $0 = $0.addingTimeInterval(s) } }
}

/// Das Entsperr-Fenster (SPEC 2, 10): K ohne Abfrage für `entsperrDauer`, danach wieder nur mit Face ID.
final class EntsperrFensterTests: XCTestCase {
    private let k = TestSchluessel.schluessel

    private func aufbau() throws -> (bund: Schluesselbund, speicher: MemorySpeicher, regler: Regler) {
        let regler = Regler()
        let speicher = MemorySpeicher()
        let bund = Schluesselbund(speicher: speicher, dauer: { regler.dauer }, jetzt: { regler.jetzt })
        try bund.speichereSchluessel(k)
        return (bund, speicher, regler)
    }

    private func gleich(_ a: SymmetricKey?, _ b: SymmetricKey) -> Bool { a.map { $0.withUnsafeBytes { Data($0) } == b.withUnsafeBytes { Data($0) } } ?? false }

    func testKeinFensterVorDemErstenFaceId() throws {
        let a = try aufbau()
        XCTAssertNil(a.bund.fensterSchluessel())
        XCTAssertFalse(a.bund.fensterOffen)
    }

    func testErfolgreicheAbfrageOeffnetDasFensterOhneUserPresence() async throws {
        let a = try aufbau()
        let geladen = try await a.bund.ladeSchluessel()
        XCTAssertTrue(gleich(geladen, k))
        XCTAssertEqual(a.speicher.schutz(Schluesselbund.kontoFenster), .entsperrt, "WhenUnlocked, ohne .userPresence")
        XCTAssertEqual(a.speicher.schutz(Schluesselbund.kontoSchluessel), .abfrage, "das Original bleibt hinter Face ID")
        XCTAssertTrue(gleich(a.bund.fensterSchluessel(), k))
    }

    func testImOffenenFensterKommtKOhneDasOriginalZuLesen() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        try a.speicher.loeschen(Schluesselbund.kontoSchluessel)   // Beweis: gelesen wird nur die Kopie
        let wieder = try await a.bund.ladeSchluessel()
        XCTAssertTrue(gleich(wieder, k))
    }

    func testFensterLaeuftNachDerDauerAbUndDieKopieWirdGeloescht() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        a.regler.vor(299)
        XCTAssertTrue(a.bund.fensterOffen)
        a.regler.vor(2)
        XCTAssertNil(a.bund.fensterSchluessel())
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil), "abgelaufen = gelöscht")
    }

    func testFensterGleitetNichtBeimLesenAus() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        a.regler.vor(200)
        XCTAssertTrue(a.bund.fensterOffen)
        a.regler.vor(101)
        XCTAssertFalse(a.bund.fensterOffen, "das Lesen im Fenster verlängert es nicht")
    }

    func testAusMachtJedenZugriffZuUndLoeschtDieKopie() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        a.regler.dauer = .aus
        XCTAssertNil(a.bund.fensterSchluessel())
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil))
        _ = try await a.bund.ladeSchluessel()
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil), "bei \"Jedes Mal\" öffnet auch eine Abfrage kein Fenster")
    }

    func testVerkuerzteDauerSchliesstDasAlteFenster() async throws {
        let a = try aufbau()
        a.regler.dauer = .stunde
        _ = try await a.bund.ladeSchluessel()
        a.regler.vor(600)
        XCTAssertTrue(a.bund.fensterOffen)
        a.regler.dauer = .eineMinute
        XCTAssertNil(a.bund.fensterSchluessel())
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil))
    }

    func testZurueckgestellteUhrOeffnetNichts() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        a.regler.vor(-60)
        XCTAssertNil(a.bund.fensterSchluessel(), "Öffnungszeit liegt in der Zukunft")
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil))
    }

    func testKaputteKopieIstKeinFensterUndWirdGeloescht() throws {
        let a = try aufbau()
        for muell in [Data(), Data(repeating: 1, count: 8), Data(repeating: 1, count: 40)] {
            try a.speicher.schreiben(Schluesselbund.kontoFenster, daten: muell, schutz: .entsperrt)
            XCTAssertNil(a.bund.fensterSchluessel())
            XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil))
        }
    }

    func testSchliesseVergissUndNeuesKLoeschenDieKopie() async throws {
        let a = try aufbau()
        _ = try await a.bund.ladeSchluessel()
        a.bund.schliesseFenster()
        XCTAssertFalse(a.bund.fensterOffen)
        _ = try await a.bund.ladeSchluessel()
        try a.bund.speichereSchluessel(SymmetricKey(size: .bits256))
        XCTAssertFalse(a.bund.fensterOffen, "ein neues K gilt nicht für die Kopie des alten")
        _ = try await a.bund.ladeSchluessel()
        try a.bund.vergiss()
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoFenster, kontext: nil))
        XCTAssertNil(try a.speicher.lesen(Schluesselbund.kontoSchluessel, kontext: nil))
    }
}
