import CryptoKit
import Foundation
import Synchronization
import XCTest
@testable import Heimherz

/// Die gemeinsamen Fixtures aus `fixtures/` (dieselben Dateien lesen die Bun-Tests). Im Bundle als Ordnerreferenz, sonst über den Quellpfad.
enum Fixture {
    private final class Anker {}

    private static var wurzel: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func url(_ ordner: String, _ datei: String) -> URL {
        let name = (datei as NSString).deletingPathExtension
        let endung = (datei as NSString).pathExtension
        if let u = Bundle(for: Anker.self).url(forResource: name, withExtension: endung, subdirectory: "fixtures/\(ordner)") { return u }
        return wurzel.appendingPathComponent("fixtures/\(ordner)/\(datei)")
    }

    static func daten(_ ordner: String, _ datei: String) throws -> Data {
        try Data(contentsOf: url(ordner, datei))
    }

    static func lade<T: Decodable>(_ typ: T.Type, _ ordner: String, _ datei: String) throws -> T {
        try JSONDecoder().decode(typ, from: daten(ordner, datei))
    }

    /// Dateinamen (*.json) eines Fixture-Ordners.
    static func dateien(_ ordner: String) throws -> [String] {
        let bundleOrdner = Bundle(for: Anker.self).resourceURL?.appendingPathComponent("fixtures/\(ordner)")
        let quelle = wurzel.appendingPathComponent("fixtures/\(ordner)")
        for kandidat in [bundleOrdner, quelle].compactMap({ $0 }) {
            if let liste = try? FileManager.default.contentsOfDirectory(atPath: kandidat.path), !liste.isEmpty {
                return liste.filter { $0.hasSuffix(".json") }.sorted()
            }
        }
        return []
    }
}

/// Der Test-Schlüssel der Fixtures: Bytes 0x01 bis 0x20 (erfunden, nie ein echter Schlüssel).
enum TestSchluessel {
    static var roh: Data { Data(Array(1...32)) }
    static var schluessel: SymmetricKey { SymmetricKey(data: roh) }
    /// Test-Token: Bytes 0x40 bis 0x5f als b64url (43 Zeichen).
    static let token = "QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"
    /// Test-Schlüssel als b64url (wie im Koppel-Link).
    static let schluesselB64url = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
}

/// Schlüsselbund im Speicher (im ungesignierten Testlauf liefert der echte Fehler -34018); merkt sich, ob mit Abfrage gespeichert wurde.
typealias MemorySpeicher = SpeicherImRAM

/// Attrappe für `URLSession`: pro Test ein eigener Host, der Handler bekommt Anfrage und Body und liefert die Antwort.
final class FakeNetz: URLProtocol {
    struct Antwort: Sendable {
        var status = 200
        var kopf: [String: String] = [:]
        var koerper = Data()
        /// Wenn gesetzt, scheitert die Anfrage mit diesem URL-Fehler (Netz weg).
        var urlFehler: URLError.Code?
        static func json(_ text: String, status: Int = 200) -> Antwort { Antwort(status: status, kopf: ["Content-Type": "application/json"], koerper: Data(text.utf8)) }
        static func fehler(_ code: URLError.Code) -> Antwort { Antwort(urlFehler: code) }
    }
    typealias Handler = @Sendable (URLRequest, Data) -> Antwort

    private static let handler = Mutex<[String: Handler]>([:])

    /// Eine Sitzung und die Basis-Adresse dazu; jede Anfrage geht an `handler`.
    static func neu(_ h: @escaping Handler) -> (sitzung: URLSession, basis: URL) {
        let host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
        handler.withLock { $0[host] = h }
        let konfig = URLSessionConfiguration.ephemeral
        konfig.protocolClasses = [FakeNetz.self]
        return (URLSession(configuration: konfig), URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/"))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func koerper(_ r: URLRequest) -> Data {
        if let d = r.httpBody { return d }
        guard let strom = r.httpBodyStream else { return Data() }
        strom.open()
        defer { strom.close() }
        var aus = Data()
        var puffer = [UInt8](repeating: 0, count: 4096)
        while strom.hasBytesAvailable {
            let n = strom.read(&puffer, maxLength: puffer.count)
            if n <= 0 { break }
            aus.append(puffer, count: n)
        }
        return aus
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let h = Self.handler.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let a = h(request, Self.koerper(request))
        if let code = a.urlFehler {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        guard let antwort = HTTPURLResponse(url: url, statusCode: a.status, httpVersion: "HTTP/1.1", headerFields: a.kopf) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: antwort, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: a.koerper)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension XCTestCase {
    /// Ein frischer Temp-Ordner, der nach dem Test verschwindet.
    func tempOrdner() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("heimherz-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }
}

/// Ein Eintrag mit erfundenen Daten.
func testEintrag(_ id: String, name: String = "Konto", passwort: String = "geheim", geaendert: String = "2026-10-01T10:00:00.000Z", geloescht: Bool = false) -> Eintrag {
    Eintrag(id: id, name: name, benutzer: "tobi", passwort: passwort, urls: ["https://example.org"], geaendert: geaendert, geloescht: geloescht)
}
