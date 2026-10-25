import Synchronization
import UIKit
import XCTest
@testable import Heimherz

final class SymbolTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)

    private func client(_ h: @escaping FakeNetz.Handler) -> HeimClient {
        let (sitzung, basis) = FakeNetz.neu(h)
        return HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
    }

    func testClientHoltSymbolMitTokenUndKodiertDenHost() async throws {
        let bild = Data([0x89, 0x50, 0x4e, 0x47])
        let c = client { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/symbol")
            XCTAssertEqual(r.url?.query, "host=www.example.org")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer \(TestSchluessel.token)")
            return .init(status: 200, kopf: ["Content-Type": "image/png"], koerper: bild)
        }
        let d = try await c.symbolHolen(host: "www.example.org")
        XCTAssertEqual(d, bild)
    }

    func testKeinSymbolIstNilAberEinFehlerBleibtEiner() async throws {
        for status in [404, 400] {
            let c = client { _, _ in .init(status: status) }
            let d = try await c.symbolHolen(host: "x.example")
            XCTAssertNil(d)
        }
        let kaputt = client { _, _ in .init(status: 401) }
        do { _ = try await kaputt.symbolHolen(host: "x.example"); XCTFail("401") } catch { XCTAssertEqual(error as? HeimFehler, .nichtBerechtigt) }
        let aus = client { _, _ in .fehler(.notConnectedToInternet) }
        do { _ = try await aus.symbolHolen(host: "x.example"); XCTFail("offline") } catch { XCTAssertEqual(error as? HeimFehler, .nichtErreichbar) }
    }

    func testCacheSchreibtLiestUndLaeuftNachDreissigTagenAb() throws {
        let cache = SymbolCache(ordner: try tempOrdner())
        XCTAssertNil(cache.lies("a.example", jetzt: jetzt))
        cache.schreibe("A.Example", .bild(Data([1, 2, 3])))
        XCTAssertEqual(cache.lies("a.example"), .bild(Data([1, 2, 3])), "Groß und Klein egal")
        cache.schreibe("b.example", .keins)
        XCTAssertEqual(cache.lies("b.example"), .keins)
        XCTAssertNil(cache.lies("b.example", jetzt: Date().addingTimeInterval(31 * 86_400)), "nach 30 Tagen wieder fragen")
        XCTAssertEqual(cache.lies("b.example", jetzt: Date().addingTimeInterval(29 * 86_400)), .keins)
        cache.schreibe("b.example", .bild(Data([9])))
        XCTAssertEqual(cache.lies("b.example"), .bild(Data([9])), "ein Bild ersetzt das Merken von keins")
    }

    func testCacheDateinamenVerratenDenHostNicht() throws {
        let ordner = try tempOrdner()
        SymbolCache(ordner: ordner).schreibe("geheim.example", .bild(Data([1])))
        let namen = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        XCTAssertEqual(namen.count, 1)
        XCTAssertFalse(namen[0].contains("geheim"))
    }

    @MainActor
    func testLaderZeigtBildNachdemEsDaIstUndFragtJedenHostNurEinmal() async throws {
        let zaehler = Zaehler()
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let ordner = try tempOrdner()
        let lader = SymbolLader(cache: SymbolCache(ordner: ordner)) { _ in
            zaehler.erhoehe()
            return png
        }
        XCTAssertNil(lader.bild(fuer: "a.example"))
        await lader.lade("a.example")
        await lader.lade("a.example")
        XCTAssertNotNil(lader.bild(fuer: "a.example"))
        XCTAssertEqual(zaehler.wert, 1)
        // Neue Sitzung, gleicher Cache: keine neue Anfrage
        let zweiter = SymbolLader(cache: SymbolCache(ordner: ordner), holen: { _ in zaehler.erhoehe(); return nil })
        await zweiter.lade("a.example")
        XCTAssertNotNil(zweiter.bild(fuer: "a.example"))
        XCTAssertEqual(zaehler.wert, 1)
    }

    @MainActor
    func testLaderMerktKeinSymbolUndVersuchtNetzfehlerNochmal() async throws {
        let ordner = try tempOrdner()
        let n = Zaehler()
        let keins = SymbolLader(cache: SymbolCache(ordner: ordner)) { _ in n.erhoehe(); return nil }
        await keins.lade("k.example")
        XCTAssertNil(keins.bild(fuer: "k.example"))
        XCTAssertEqual(SymbolCache(ordner: ordner).lies("k.example"), .keins)

        let aus = Zaehler()
        let offline = SymbolLader(cache: SymbolCache(ordner: try tempOrdner())) { _ in aus.erhoehe(); throw HeimFehler.nichtErreichbar }
        await offline.lade("o.example")
        await offline.lade("o.example")
        XCTAssertEqual(aus.wert, 2, "ein Netzfehler wird nicht gemerkt")
    }
}

private final class Zaehler: Sendable {
    private let n = Mutex(0)
    var wert: Int { n.withLock { $0 } }
    func erhoehe() { n.withLock { $0 += 1 } }
}
