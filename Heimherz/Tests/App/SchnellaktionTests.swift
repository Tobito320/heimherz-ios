import XCTest
@testable import Heimherz

@MainActor
final class SchnellaktionTests: XCTestCase {
    func testTypenFuehrenInDenRichtigenTab() {
        XCTAssertEqual(Schnellaktion(typ: "com.onlyus.heimherz.aktion.codes"), .codes)
        XCTAssertEqual(Schnellaktion(typ: "com.onlyus.heimherz.aktion.fotos"), .fotosSichern)
        XCTAssertEqual(Schnellaktion(typ: "com.onlyus.heimherz.aktion.passwort"), .neuesPasswort)
        XCTAssertNil(Schnellaktion(typ: "com.example.fremd"))
        XCTAssertNil(Schnellaktion(typ: ""))
        XCTAssertEqual(Schnellaktion.codes.tab, .passwoerter)
        XCTAssertEqual(Schnellaktion.neuesPasswort.tab, .passwoerter)
        XCTAssertEqual(Schnellaktion.fotosSichern.tab, .fotos)
    }

    func testInfoPlistUndCodeNennenDieselbenAktionen() throws {
        let eintraege = try XCTUnwrap(Bundle(for: SchnellaktionPostfach.self).object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        let typen = eintraege.compactMap { $0["UIApplicationShortcutItemType"] as? String }
        XCTAssertEqual(typen, Schnellaktion.allCases.map(\.rawValue), "Reihenfolge wie am Symbol: Codes, Fotos sichern, Neues Passwort")
        for e in eintraege {
            XCTAssertNotNil(e["UIApplicationShortcutItemTitle"] as? String)
            XCTAssertNotNil(e["UIApplicationShortcutItemIconSymbolName"] as? String)
        }
    }

    func testPostfachGibtDieAktionNurEinmalUndNurAnDenRichtigen() {
        let p = SchnellaktionPostfach()
        XCTAssertFalse(p.nimm(.codes), "leer")
        p.lege(.codes)
        XCTAssertFalse(p.nimm(.neuesPasswort), "andere Aktion lässt sie liegen")
        XCTAssertEqual(p.offen, .codes)
        XCTAssertTrue(p.nimm(.codes))
        XCTAssertFalse(p.nimm(.codes), "nur einmal")
        XCTAssertNil(p.offen)
    }

    func testNeueAktionErsetztDieAlte() {
        let p = SchnellaktionPostfach()
        p.lege(.codes)
        p.lege(.fotosSichern)
        XCTAssertEqual(p.offen, .fotosSichern)
    }

    func testVerwerfenNurFuerDenTab() {
        let p = SchnellaktionPostfach()
        p.lege(.fotosSichern)
        p.verwirf(tab: .passwoerter)
        XCTAssertEqual(p.offen, .fotosSichern)
        p.verwirf(tab: .fotos)
        XCTAssertNil(p.offen)
    }

    func testTabEinstellungen() {
        XCTAssertEqual(HeimherzTab(rawValue: "einstellungen"), .einstellungen)
        XCTAssertNil(HeimherzTab(rawValue: "mehr"))
        XCTAssertEqual(HeimherzTab.einstellungen.titel, "Einstellungen")
        XCTAssertEqual(HeimherzTab.einstellungen.symbolName, "gearshape.fill")
    }
}
