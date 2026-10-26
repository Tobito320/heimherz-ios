import XCTest
@testable import Heimherz

final class OrdnerAbgleichTests: XCTestCase {
    private func stand(_ g: Int64, _ t: Int64) -> OrdnerDateiStand { OrdnerDateiStand(groesse: g, geaendert: t) }

    func testNeueUndGeaenderteDateienGehenHoch() {
        let gemerkt = ["a.pdf": stand(10, 100), "b.pdf": stand(20, 100), "c.pdf": stand(30, 100)]
        let gefunden = ["a.pdf": stand(10, 100), "b.pdf": stand(21, 100), "c.pdf": stand(30, 101), "z/neu.pdf": stand(5, 1)]
        XCTAssertEqual(OrdnerRegeln.zuSenden(gefunden: gefunden, gemerkt: gemerkt), ["b.pdf", "c.pdf", "z/neu.pdf"])
        XCTAssertEqual(OrdnerRegeln.zuSenden(gefunden: gemerkt, gemerkt: gemerkt), [])
        // Was am Handy verschwindet, löst nichts aus (nie löschen, nie spiegeln).
        XCTAssertEqual(OrdnerRegeln.zuSenden(gefunden: [:], gemerkt: gemerkt), [])
    }

    func testZielPfad() {
        XCTAssertEqual(OrdnerRegeln.zielPfad(ordnerName: "Adobe Scan", relativ: "2026/scan 1.pdf"), "Eingang/Adobe Scan/2026/scan 1.pdf")
    }

    func testLiesFindetDateienRekursivOhneVersteckteUndSymlinks() throws {
        let fm = FileManager.default
        let wurzel = fm.temporaryDirectory.appending(path: "ordner-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: wurzel.appending(path: "unter/tief"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: wurzel) }
        try Data("eins".utf8).write(to: wurzel.appending(path: "a.txt"))
        try Data("zwei".utf8).write(to: wurzel.appending(path: "unter/tief/b.txt"))
        try Data("x".utf8).write(to: wurzel.appending(path: ".versteckt"))
        try fm.createSymbolicLink(at: wurzel.appending(path: "link"), withDestinationURL: wurzel.appending(path: "unter"))
        let gefunden = OrdnerRegeln.lies(wurzel)
        XCTAssertEqual(gefunden.keys.sorted(), ["a.txt", "unter/tief/b.txt"])
        XCTAssertEqual(gefunden["a.txt"]?.stand.groesse, 4)
    }
}
