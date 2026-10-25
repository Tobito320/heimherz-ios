import XCTest
@testable import Heimherz

final class FotoStandTests: XCTestCase {
    private func ressource(_ kennung: String, _ name: String, art: FotoArt = .foto) -> FotoRessource {
        FotoRessource(assetId: "id-\(kennung)", kennung: kennung, name: name, art: art, dateiname: "\(kennung).heic", aufnahme: nil)
    }

    func testSpeichernUndLesen() throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        XCTAssertEqual(ablage.lade(), FotoStand(), "ohne Datei ein leerer Stand")
        var s = FotoStand()
        s.fertig = ["A"]; s.teil = ["B/foto-0"]; s.fehler = "kaputt"; s.nurWLAN = false; s.gesamt = 7
        s.letzteUebertragung = Date(timeIntervalSince1970: 1_800_000_000)
        ablage.speichere(s)
        XCTAssertEqual(ablage.lade(), s)
        ablage.aendere { $0.fehler = nil }
        XCTAssertNil(ablage.lade().fehler)
        XCTAssertEqual(ablage.lade().fertig, ["A"])
    }

    func testAlteDateiOhneNeueFelderLaesstSichLesen() throws {
        let ordner = try tempOrdner()
        try Data(#"{"fertig":["A"],"teil":["B/foto-0"]}"#.utf8).write(to: ordner.appending(path: "fotos-stand.json"))
        let s = FotoStandAblage(ordner: ordner).lade()
        XCTAssertEqual(s.fertig, ["A"])
        XCTAssertNil(s.nurWLAN)
        XCTAssertTrue(s.wlanNoetig, "Standard: nur WLAN")
    }

    func testKaputteDateiGibtLeerenStand() throws {
        let ordner = try tempOrdner()
        try Data("{".utf8).write(to: ordner.appending(path: "fotos-stand.json"))
        XCTAssertEqual(FotoStandAblage(ordner: ordner).lade(), FotoStand())
    }

    func testBekanntUebernehmenUndAufraeumen() {
        var s = FotoStand()
        s.uebernimm(bekannt: [BekanntesFoto(kennung: "A", ressource: "foto-0", groesse: 5), BekanntesFoto(kennung: "B", ressource: "foto-0", groesse: 5)])
        XCTAssertEqual(s.teil, ["A/foto-0", "B/foto-0"])
        s.fertig = ["A"]
        s.raeumeAuf()
        XCTAssertEqual(s.teil, ["B/foto-0"], "Dateien fertiger Assets brauchen keinen Einzeleintrag mehr")
    }

    func testPlanUeberspringtFertigeOhnePhotoKitZuRufen() {
        let a = FotoRegeln.kopf(assetId: "a"), b = FotoRegeln.kopf(assetId: "b"), c = FotoRegeln.kopf(assetId: "c")
        var s = FotoStand()
        s.fertig = [a.kennung]
        s.teil = [FotoRegeln.schluessel(kennung: b.kennung, name: "foto-0")]
        var gerufen: [String] = []
        let p = FotoPlan.plane(koepfe: [a, b, c], stand: s) { kopf in
            gerufen.append(kopf.kennung)
            return FotoRegeln.ressourcen(kopf: kopf, aufnahme: nil, teile: [(.foto, "x.heic")])
        }
        XCTAssertEqual(gerufen, [b.kennung, c.kennung], "für fertige Assets wird nie nach Dateien gefragt")
        XCTAssertEqual(p.zahlen, FotoZahlen(gesamt: 3, amPC: 2))
        XCTAssertEqual(p.zahlen.offen, 1)
        XCTAssertEqual(p.neuFertig, [b.kennung])
        XCTAssertEqual(p.offen.map(\.kennung), [c.kennung])
    }

    func testPlanTeilweiseUndUnterwegsUndHoechstens() {
        let a = FotoRegeln.kopf(assetId: "a"), b = FotoRegeln.kopf(assetId: "b"), c = FotoRegeln.kopf(assetId: "c")
        var s = FotoStand()
        s.teil = [FotoRegeln.schluessel(kennung: a.kennung, name: "foto-0")] // Live Photo: Foto da, Video fehlt
        let zwei: (FotoKopf) -> [FotoRessource] = { FotoRegeln.ressourcen(kopf: $0, aufnahme: nil, teile: [(.foto, "x.heic"), (.live, "x.mov")]) }
        let p = FotoPlan.plane(koepfe: [a, b, c], stand: s, ressourcen: zwei)
        XCTAssertEqual(p.offen.map(\.schluessel), [FotoRegeln.schluessel(kennung: a.kennung, name: "live-0")] + zwei(b).map(\.schluessel) + zwei(c).map(\.schluessel))
        XCTAssertEqual(p.zahlen.amPC, 0)

        let unterwegs: Set<String> = [FotoRegeln.schluessel(kennung: a.kennung, name: "live-0")]
        let q = FotoPlan.plane(koepfe: [a, b, c], stand: s, uebersprungen: unterwegs, hoechstens: 2, ressourcen: zwei)
        XCTAssertEqual(q.offen.map(\.schluessel), zwei(b).map(\.schluessel), "unterwegs wird übersprungen, hoechstens begrenzt")
    }

    func testPlanAssetOhneOriginaleZaehltAlsErledigt() {
        let a = FotoRegeln.kopf(assetId: "a")
        let p = FotoPlan.plane(koepfe: [a], stand: FotoStand()) { _ in [] }
        XCTAssertEqual(p.zahlen, FotoZahlen(gesamt: 1, amPC: 1))
        XCTAssertEqual(p.neuFertig, [a.kennung])
    }
}
