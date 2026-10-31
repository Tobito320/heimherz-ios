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
        XCTAssertNil(s.iCloudLaden)
        XCTAssertTrue(s.iCloudErlaubt, "Standard: Originale aus iCloud laden")
        XCTAssertNil(s.angehaltenVomNutzer)
        XCTAssertFalse(s.nutzerHatAngehalten, "Standard: nicht angehalten, der Abgleich darf von selbst laufen")
        XCTAssertNil(s.erweiterungAus)
        XCTAssertFalse(s.nutzerHatErweiterungAusgeschaltet)
    }

    func testAngehaltenUndErweiterungAusBleibenDauerhaftGespeichert() throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        ablage.aendere { $0.angehaltenVomNutzer = true; $0.erweiterungAus = true }
        let neu = ablage.lade()
        XCTAssertTrue(neu.nutzerHatAngehalten)
        XCTAssertTrue(neu.nutzerHatErweiterungAusgeschaltet)
        ablage.aendere { $0.angehaltenVomNutzer = false }
        XCTAssertFalse(ablage.lade().nutzerHatAngehalten, "\"Abgleich starten\" hebt es auf")
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

    func testPlanZaehltAllesAberSchlaegtNurNoetigesNach() {
        let koepfe = (1...6).map { FotoRegeln.kopf(assetId: "k\($0)") }
        var s = FotoStand()
        s.fertig = [koepfe[0].kennung]
        s.teil = [FotoRegeln.schluessel(kennung: koepfe[4].kennung, name: "foto-0")]   // der PC kennt schon die einzige Datei von Nr. 5
        var gerufen: [String] = []
        let p = FotoPlan.plane(koepfe: koepfe, stand: s, hoechstens: 2, zaehleAlles: true) { kopf in
            gerufen.append(kopf.kennung)
            return FotoRegeln.ressourcen(kopf: kopf, aufnahme: nil, teile: [(.foto, "x.heic")])
        }
        XCTAssertEqual(p.offen.map(\.kennung), [koepfe[1].kennung, koepfe[2].kennung], "das Stück: die nächsten zwei, neueste zuerst")
        XCTAssertEqual(gerufen, [koepfe[1].kennung, koepfe[2].kennung, koepfe[4].kennung], "nach dem Stück nur noch Assets, von denen der PC schon etwas kennt")
        XCTAssertEqual(p.zahlen, FotoZahlen(gesamt: 6, amPC: 2), "Nr. 1 war fertig, Nr. 5 ist es jetzt")
        XCTAssertEqual(p.neuFertig, [koepfe[4].kennung])
        XCTAssertEqual(p.fehlend, [koepfe[1].kennung: 1, koepfe[2].kennung: 1])
    }

    func testPlanNurZaehlenMitHoechstensNull() {
        let koepfe = (1...3).map { FotoRegeln.kopf(assetId: "k\($0)") }
        let p = FotoPlan.plane(koepfe: koepfe, stand: FotoStand(), hoechstens: 0, zaehleAlles: true) { _ in
            XCTFail("ohne Hinweis vom PC wird nichts nachgeschlagen")
            return []
        }
        XCTAssertEqual(p.offen, [])
        XCTAssertEqual(p.zahlen, FotoZahlen(gesamt: 3, amPC: 0))
    }

    func testPlanUeberspringtNichtGegangeneDateien() {
        let a = FotoRegeln.kopf(assetId: "a"), b = FotoRegeln.kopf(assetId: "b")
        let eine: (FotoKopf) -> [FotoRessource] = { FotoRegeln.ressourcen(kopf: $0, aufnahme: nil, teile: [(.foto, "x.heic")]) }
        let p = FotoPlan.plane(koepfe: [a, b], stand: FotoStand(), uebersprungen: [eine(a)[0].schluessel], hoechstens: 5, zaehleAlles: true, ressourcen: eine)
        XCTAssertEqual(p.offen.map(\.kennung), [b.kennung])
    }

    func testKennungAusSchluessel() {
        XCTAssertEqual(FotoRegeln.kennung(vonSchluessel: "AbC-_1/foto-0"), "AbC-_1")
    }
}
