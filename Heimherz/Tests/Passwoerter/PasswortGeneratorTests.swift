import XCTest
@testable import Heimherz

/// Fester Zufall für Tests (SplitMix64): gleicher Startwert, gleiche Folge.
struct FesterZufall: RandomNumberGenerator {
    var zustand: UInt64
    init(_ start: UInt64) { zustand = start }
    mutating func next() -> UInt64 {
        zustand &+= 0x9E37_79B9_7F4A_7C15
        var z = zustand
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class PasswortGeneratorTests: XCTestCase {
    func testLaengeGrenzenWerdenEingehalten() {
        var z = FesterZufall(1)
        for (soll, laenge) in [(8, 3), (8, 8), (20, 20), (64, 64), (64, 500)] {
            var r = PasswortRegeln()
            r.laenge = laenge
            XCTAssertEqual(PasswortGenerator.erzeuge(r, mit: &z).count, soll, "Länge \(laenge)")
        }
    }

    func testVonJederEingeschaltetenKlasseMindestensEinZeichen() {
        var z = FesterZufall(2)
        for _ in 0..<300 {
            var r = PasswortRegeln()
            r.laenge = 8
            let p = PasswortGenerator.erzeuge(r, mit: &z)
            XCTAssertTrue(p.contains { PasswortGenerator.kleinbuchstaben.contains($0) }, p)
            XCTAssertTrue(p.contains { PasswortGenerator.grossbuchstaben.contains($0) }, p)
            XCTAssertTrue(p.contains { PasswortGenerator.ziffernZeichen.contains($0) }, p)
            XCTAssertTrue(p.contains { PasswortGenerator.sonderZeichen.contains($0) }, p)
        }
    }

    func testAusgeschalteteKlassenKommenNichtVor() {
        var z = FesterZufall(3)
        var r = PasswortRegeln()
        r.laenge = 64
        r.ziffern = false
        r.sonderzeichen = false
        for _ in 0..<50 {
            let p = PasswortGenerator.erzeuge(r, mit: &z)
            XCTAssertTrue(p.allSatisfy { $0.isLetter && $0.isASCII }, p)
        }
    }

    func testGleicherStartwertGleichesPasswortAnderesSystemzufallAnders() {
        var a = FesterZufall(7), b = FesterZufall(7)
        let r = PasswortRegeln()
        XCTAssertEqual(PasswortGenerator.erzeuge(r, mit: &a), PasswortGenerator.erzeuge(r, mit: &b))
        XCTAssertNotEqual(PasswortGenerator.erzeuge(r), PasswortGenerator.erzeuge(r), "Systemzufall: zwei gleiche 20-Zeichen-Passwörter wären ein Fehler")
    }

    func testWortgruppe() {
        var z = FesterZufall(4)
        var r = PasswortRegeln()
        r.modus = .wortgruppe
        r.woerter = 5
        let p = PasswortGenerator.erzeuge(r, mit: &z)
        let teile = p.split(separator: "-").map(String.init)
        XCTAssertEqual(teile.count, 6, p)
        XCTAssertTrue(teile.dropLast().allSatisfy { Wortliste.woerter.contains($0.lowercased()) && $0.first?.isUppercase == true }, p)
        XCTAssertNotNil(Int(teile[5]))
        r.mitZahl = false
        r.grossschreiben = false
        r.trenner = "."
        r.woerter = 99
        let q = PasswortGenerator.erzeuge(r, mit: &z)
        XCTAssertEqual(q.split(separator: ".").count, PasswortGenerator.wortAnzahl.upperBound, "Wortzahl wird begrenzt")
        XCTAssertEqual(q, q.lowercased())
    }

    func testPassphraseHatStandardmaessigSechsWoerter() {
        var z = FesterZufall(5)
        var r = PasswortRegeln()
        r.modus = .wortgruppe
        XCTAssertEqual(r.woerter, 6)
        XCTAssertEqual(PasswortGenerator.erzeuge(r, mit: &z).split(separator: "-").count, 7, "sechs Wörter und die Zahl")
        var v = FesterZufall(6)
        let wort = PasswortVorschlaege.erzeuge(regeln: [nil], mit: &v).first { $0.art == .wortgruppe }
        XCTAssertEqual(wort?.wert.split(separator: "-").count, 7, "auch der AutoFill-Vorschlag")
    }

    func testWortlisteIstSauber() {
        let w = Wortliste.woerter
        XCTAssertGreaterThanOrEqual(w.count, 1024, "mindestens 10 Bit je Wort")
        XCTAssertEqual(Set(w).count, w.count, "keine Doppelten")
        for wort in w {
            XCTAssertNotNil(wort.range(of: "^[a-z]{3,12}$", options: .regularExpression), "nur a-z, kein Umlaut, kein ß: \(wort)")
        }
    }

    func testBitsWachsenMitLaengeUndAlphabet() {
        var r = PasswortRegeln()
        let standard = PasswortGenerator.bits(r)
        XCTAssertGreaterThan(standard, 100)
        r.sonderzeichen = false
        r.ziffern = false
        XCTAssertLessThan(PasswortGenerator.bits(r), standard)
        r.modus = .wortgruppe
        XCTAssertGreaterThan(PasswortGenerator.bits(r), 50)
    }
}
