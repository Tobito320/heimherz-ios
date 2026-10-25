import XCTest
@testable import Heimherz

/// Mediathek aus erfundenen Assets; schreibt echte Temp-Dateien, damit das Aufräumen prüfbar ist.
private struct FakeQuelle: FotoQuelle {
    let assets: [(kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)])]
    let ordner: URL
    var aufnahme: Date? = Date(timeIntervalSince1970: 1_790_000_000)
    /// Läuft vor dem Schreiben jeder Datei; darf hängen (`Task.sleep`) oder den Ablauf melden.
    var beimExport: (@Sendable (FotoRessource) async throws -> Void)?
    let plaene = Kasten<Int>(0)
    let iCloudWerte = Kasten<[Bool]>([])

    func plane(stand: FotoStand, hoechstens: Int, nur: [String]?, uebersprungen: Set<String>) async -> FotoPlan.Ergebnis {
        plaene.mit { $0 += 1 }
        let sicht = nur.map { ids in assets.filter { ids.contains($0.kopf.assetId) } } ?? assets
        return FotoPlan.plane(koepfe: sicht.map(\.kopf), stand: stand, uebersprungen: uebersprungen, hoechstens: hoechstens, zaehleAlles: true) { k in
            guard let a = sicht.first(where: { $0.kopf == k }) else { return [] }
            return FotoRegeln.ressourcen(kopf: k, aufnahme: aufnahme, teile: a.teile)
        }
    }

    func exportiere(_ r: FotoRessource, iCloud: Bool) async throws -> URL {
        iCloudWerte.mit { $0.append(iCloud) }
        try await beimExport?(r)
        let u = ordner.appending(path: "\(UUID().uuidString)-\(r.name)")
        try Data("inhalt \(r.name)".utf8).write(to: u)
        return u
    }
}

private final class FakeSender: FotoSender, Sendable {
    let anfragen = Kasten<[URLRequest]>([])
    let verhalten: @Sendable (URLRequest) -> HeimFehler?
    init(_ v: @escaping @Sendable (URLRequest) -> HeimFehler? = { _ in nil }) { verhalten = v }
    func sende(datei: URL, anfrage: URLRequest) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: datei.path), "die Datei muss beim Senden da sein")
        anfragen.mit { $0.append(anfrage) }
        if let f = verhalten(anfrage) { throw f }
    }
    var pfade: [String] { anfragen.mit { $0.compactMap { $0.url?.path } } }
}

private struct FakeNetzart: Netzart {
    let wlan: Bool
    func istWLAN() async -> Bool { wlan }
}

final class FotoAbgleichTests: XCTestCase {
    private func asset(_ id: String, _ teile: [(art: FotoArt, dateiname: String)]) -> (kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)]) {
        (FotoRegeln.kopf(assetId: id), teile)
    }

    private struct Umgebung {
        let abgleich: FotoAbgleich
        let sender: FakeSender
        let ablage: FotoStandAblage
        let temp: URL
        let anzeigen: Kasten<[FotoAnzeige]>
        let quelle: FakeQuelle
    }

    private func baue(assets: [(kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)])], bekannt: String = "[]", bekanntStatus: Int = 200,
                      wlan: Bool = true, nurWLAN: Bool? = nil, sender: FakeSender = FakeSender(), gleichzeitig: Int = 2, stueck: Int = 20,
                      ablage vorhanden: FotoStandAblage? = nil, beimExport: (@Sendable (FotoRessource) async throws -> Void)? = nil) throws -> Umgebung {
        let temp = try tempOrdner()
        let ablage = try vorhanden ?? FotoStandAblage(ordner: try tempOrdner())
        if let nurWLAN { ablage.aendere { $0.nurWLAN = nurWLAN } }
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/fotos/bekannt")
            return .json(bekannt, status: bekanntStatus)
        }
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        let anzeigen = Kasten<[FotoAnzeige]>([])
        let quelle = FakeQuelle(assets: assets, ordner: temp, beimExport: beimExport)
        let a = FotoAbgleich(client: client, quelle: quelle, sender: sender, netz: FakeNetzart(wlan: wlan), ablage: ablage,
                             gleichzeitig: gleichzeitig, stueck: stueck, jetzt: { Date(timeIntervalSince1970: 1_800_000_000) }) { neu in anzeigen.mit { $0.append(neu) } }
        return Umgebung(abgleich: a, sender: sender, ablage: ablage, temp: temp, anzeigen: anzeigen, quelle: quelle)
    }

    private func dateienIn(_ u: URL) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? [] }

    func testSendetNurWasAmPCFehltMitAllenKoepfen() async throws {
        let a = asset("a", [(.foto, "IMG_1.HEIC")]), b = asset("b", [(.foto, "IMG_2.HEIC"), (.live, "IMG_2.MOV")]), c = asset("c", [(.video, "MOV_3.MOV")])
        let bekannt = #"[{"kennung":"\#(a.kopf.kennung)","ressource":"foto-0","groesse":5},{"kennung":"\#(b.kopf.kennung)","ressource":"foto-0","groesse":5}]"#
        let u = try baue(assets: [a, b, c], bekannt: bekannt)
        await u.abgleich.abgleichen()

        XCTAssertEqual(Set(u.sender.pfade), ["/v1/fotos/\(b.kopf.kennung)/live-0", "/v1/fotos/\(c.kopf.kennung)/video-0"])
        let anfragen = u.sender.anfragen.mit { $0 }
        let live = try XCTUnwrap(anfragen.first { $0.url?.path.hasSuffix("/live-0") == true })
        XCTAssertEqual(live.value(forHTTPHeaderField: "X-Dateiname"), "IMG_2.MOV")
        XCTAssertEqual(live.value(forHTTPHeaderField: "X-Aufnahme"), Zeit.iso(Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertEqual(live.value(forHTTPHeaderField: "Authorization"), "Bearer \(TestSchluessel.token)")
        XCTAssertEqual(live.httpMethod, "PUT")

        let s = u.ablage.lade()
        XCTAssertEqual(s.fertig, [a.kopf.kennung, b.kopf.kennung, c.kopf.kennung], "danach liegt alles am PC")
        XCTAssertNil(s.fehler)
        XCTAssertEqual(s.letzteUebertragung, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(dateienIn(u.temp), [], "Temp-Dateien sind weg")
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertEqual(letzte.zahlen, FotoZahlen(gesamt: 3, amPC: 3))
        XCTAssertFalse(letzte.laeuft)
    }

    func testZweiterLaufMitAllesBekanntSendetNichts() async throws {
        let a = asset("a", [(.foto, "IMG_1.HEIC")])
        let bekannt = #"[{"kennung":"\#(a.kopf.kennung)","ressource":"foto-0","groesse":5}]"#
        let u = try baue(assets: [a], bekannt: bekannt)
        await u.abgleich.abgleichen()
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade, [])
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.zahlen, FotoZahlen(gesamt: 1, amPC: 1))
    }

    func testNurWLAN_OhneWLANWartenAlleDateien_VideosImmer() async throws {
        let a = asset("a", [(.foto, "IMG_1.HEIC")]), c = asset("c", [(.video, "MOV_3.MOV")])
        let u = try baue(assets: [a, c], wlan: false)
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade, [])
        XCTAssertEqual(u.ablage.lade().fehler, "2 Dateien warten auf WLAN.")
        XCTAssertEqual(dateienIn(u.temp), [], "ohne WLAN wird gar nicht erst exportiert")

        // Handy darf ins Mobilnetz: Fotos gehen, das Video wartet trotzdem.
        let v = try baue(assets: [a, c], wlan: false, nurWLAN: false)
        await v.abgleich.abgleichen()
        let anfragen = v.sender.anfragen.mit { $0 }
        XCTAssertEqual(anfragen.map { $0.url?.path }, ["/v1/fotos/\(a.kopf.kennung)/foto-0"])
        XCTAssertTrue(anfragen[0].allowsCellularAccess)
        XCTAssertEqual(v.ablage.lade().fehler, "1 Datei wartet auf WLAN.")
    }

    func testAnfragenSindNurImWLANWennDerSchalterAnIst() async throws {
        let a = asset("a", [(.foto, "IMG_1.HEIC")])
        let u = try baue(assets: [a])
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.anfragen.mit { $0.first?.allowsCellularAccess }, false)
    }

    func testPCNichtErreichbarBeimAbfragen() async throws {
        let u = try baue(assets: [asset("a", [(.foto, "x.heic")])], bekanntStatus: 401)
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade, [])
        XCTAssertEqual(u.ablage.lade().fehler, HeimFehler.nichtBerechtigt.nutzerText)
        XCTAssertFalse(try XCTUnwrap(u.anzeigen.mit { $0.last }).laeuft)
    }

    func testNetzFehlerBeimSendenStopptDenLauf() async throws {
        let sender = FakeSender { _ in .nichtErreichbar }
        let u = try baue(assets: (1...6).map { asset("a\($0)", [(.foto, "x\($0).heic")]) }, sender: sender)
        await u.abgleich.abgleichen()
        XCTAssertLessThanOrEqual(sender.pfade.count, 2, "höchstens die zwei gleichzeitig laufenden")
        XCTAssertEqual(u.ablage.lade().fehler, HeimFehler.nichtErreichbar.nutzerText)
        XCTAssertEqual(u.ablage.lade().teil, [])
        XCTAssertEqual(dateienIn(u.temp), [])
    }

    func testAbgelehnteDateiBrichtNichtAb() async throws {
        let sender = FakeSender { r in r.url?.path.hasSuffix("/foto-0") == true && r.value(forHTTPHeaderField: "X-Dateiname") == "boese.heic" ? .abgelehnt(400) : nil }
        let u = try baue(assets: [asset("a", [(.foto, "boese.heic")]), asset("b", [(.foto, "gut.heic")]), asset("c", [(.foto, "gut2.heic")])], sender: sender)
        await u.abgleich.abgleichen()
        XCTAssertEqual(sender.pfade.count, 3)
        XCTAssertEqual(u.ablage.lade().fehler, "1 Datei konnte nicht übertragen werden (vom PC abgelehnt, Code 400).")
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.zahlen, FotoZahlen(gesamt: 3, amPC: 2))
    }

    func testServerfehlerEinerDateiUeberspringtNurDieseDatei() async throws {
        for fehler in [HeimFehler.serverFehler(503), .serverFehler(500), .abgelehnt(400), .abgelehnt(411), .zuGross, .verboten] {
            let sender = FakeSender { r in r.value(forHTTPHeaderField: "X-Dateiname") == "kaputt.heic" ? fehler : nil }
            let u = try baue(assets: [asset("a", [(.foto, "kaputt.heic")]), asset("b", [(.foto, "gut.heic")]), asset("c", [(.foto, "gut2.heic")]), asset("d", [(.foto, "gut3.heic")])], sender: sender)
            await u.abgleich.abgleichen()
            XCTAssertEqual(sender.pfade.count, 4, "\(fehler): alle Dateien wurden versucht, der Lauf lief weiter")
            XCTAssertEqual(u.ablage.lade().fertig.count, 3, "\(fehler)")
            let text = try XCTUnwrap(u.ablage.lade().fehler)
            XCTAssertTrue(text.hasPrefix("1 Datei konnte nicht übertragen werden ("), "\(fehler): \(text)")
        }
    }

    func testServerfehlerImStandMitGrund() async throws {
        let sender = FakeSender { r in r.value(forHTTPHeaderField: "X-Dateiname") == "kaputt.heic" ? .serverFehler(503) : nil }
        let u = try baue(assets: [asset("a", [(.foto, "kaputt.heic")]), asset("b", [(.foto, "gut.heic")])], sender: sender)
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.ablage.lade().fehler, "1 Datei konnte nicht übertragen werden (Serverfehler 503).")
    }

    func testNurZugangPlatteVollUndVerbindungStoppenDenLauf() async throws {
        let faelle: [(HeimFehler, String)] = [
            (.nichtBerechtigt, HeimFehler.nichtBerechtigt.nutzerText),
            (.speicherVoll, HeimFehler.speicherVoll.nutzerText),
            (.nichtErreichbar, HeimFehler.nichtErreichbar.nutzerText),
            (.zeitueberschreitung, HeimFehler.zeitueberschreitung.nutzerText)
        ]
        for (fehler, text) in faelle {
            let sender = FakeSender { _ in fehler }
            let u = try baue(assets: (1...6).map { asset("a\($0)", [(.foto, "x\($0).heic")]) }, sender: sender)
            await u.abgleich.abgleichen()
            XCTAssertLessThanOrEqual(sender.pfade.count, 2, "\(fehler): höchstens die zwei gleichzeitig laufenden")
            XCTAssertEqual(u.ablage.lade().fehler, text, "\(fehler)")
        }
        XCTAssertTrue(HeimFehler.speicherVoll.nutzerText.contains("voll"))
    }

    // MARK: Stücke, Anhalten, Weitermachen

    private func viele(_ n: Int) -> [(kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)])] {
        (1...n).map { asset("a\($0)", [(.foto, "x\($0).heic")]) }
    }

    func testPlantInStueckenUndSendetNeuesteZuerst() async throws {
        let assets = viele(7)
        let u = try baue(assets: assets, gleichzeitig: 1, stueck: 3)
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade, assets.map { "/v1/fotos/\($0.kopf.kennung)/foto-0" }, "in der Reihenfolge der Mediathek (neueste zuerst), eine Datei nach der anderen")
        XCTAssertEqual(u.quelle.plaene.mit { $0 }, 4, "drei Stücke (3, 3, 1) und eine letzte Suche ohne Rest")
        XCTAssertEqual(u.ablage.lade().fertig.count, 7)
        XCTAssertEqual(dateienIn(u.temp), [])
    }

    func testAnhaltenHaeltSofortAnAuchWennEinExportHaengt() async throws {
        let (signal, weiter) = AsyncStream.makeStream(of: Void.self)
        let assets = viele(5)
        let u = try baue(assets: assets, gleichzeitig: 1) { r in
            if r.dateiname == "x3.heic" {
                weiter.yield(Void())
                try await Task.sleep(for: .seconds(60))   // hängt, bis der Abbruch kommt
            }
        }
        let lauf = Task { await u.abgleich.abgleichen() }
        for await _ in signal { break }
        lauf.cancel()
        await lauf.value

        XCTAssertEqual(u.sender.pfade, assets.prefix(2).map { "/v1/fotos/\($0.kopf.kennung)/foto-0" }, "nur die zwei fertigen Dateien gingen")
        let s = u.ablage.lade()
        XCTAssertEqual(s.fertig, [assets[0].kopf.kennung, assets[1].kopf.kennung], "sie zählen, die halbe dritte nicht")
        XCTAssertNil(s.fehler, "Anhalten ist kein Fehler")
        XCTAssertEqual(u.quelle.plaene.mit { $0 }, 1, "nach dem Abbruch wird nicht noch einmal die ganze Mediathek durchsucht")
        XCTAssertEqual(dateienIn(u.temp), [])
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertTrue(letzte.angehalten)
        XCTAssertFalse(letzte.laeuft)
        XCTAssertEqual(letzte.laufend, [])
        XCTAssertEqual(letzte.zahlen, FotoZahlen(gesamt: 5, amPC: 2))
    }

    func testNaechsterStartMachtDortWeiter() async throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        let assets = viele(5)
        // Erster Lauf: nach zwei Dateien angehalten.
        let (signal, weiter) = AsyncStream.makeStream(of: Void.self)
        let erster = try baue(assets: assets, gleichzeitig: 1, ablage: ablage) { r in
            if r.dateiname == "x3.heic" { weiter.yield(Void()); try await Task.sleep(for: .seconds(60)) }
        }
        let lauf = Task { await erster.abgleich.abgleichen() }
        for await _ in signal { break }
        lauf.cancel()
        await lauf.value
        // Zweiter Lauf: der PC kennt die zwei Dateien; der Stand kommt aus der Datei, nicht aus dem Speicher.
        let bekannt = assets.prefix(2).map { #"{"kennung":"\#($0.kopf.kennung)","ressource":"foto-0","groesse":5}"# }.joined(separator: ",")
        let zweiter = try baue(assets: assets, bekannt: "[\(bekannt)]", gleichzeitig: 1, ablage: ablage)
        await zweiter.abgleich.abgleichen()
        XCTAssertEqual(zweiter.sender.pfade, assets.dropFirst(2).map { "/v1/fotos/\($0.kopf.kennung)/foto-0" }, "genau die drei übrigen, in derselben Reihenfolge")
        XCTAssertEqual(ablage.lade().fertig.count, 5)
        XCTAssertFalse(try XCTUnwrap(zweiter.anzeigen.mit { $0.last }).angehalten)
    }

    func testStandUeberlebtNeustartOhneAntwortDesPC() async throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        let assets = viele(3)
        let erster = try baue(assets: assets, ablage: ablage)
        await erster.abgleich.abgleichen()
        let zweiter = try baue(assets: assets, ablage: ablage)   // der PC meldet "[]", der Stand auf dem Handy kennt alles
        await zweiter.abgleich.abgleichen()
        XCTAssertEqual(zweiter.sender.pfade, [])
    }

    func testHaekchenKommtSobaldDieLetzteDateiDesAssetsDaIst() async throws {
        let assets = viele(3)
        let u = try baue(assets: assets, gleichzeitig: 1)
        await u.abgleich.abgleichen()
        let zwischen = u.anzeigen.mit { $0 }.contains { $0.laeuft && $0.fertig.contains(assets[0].kopf.kennung) && !$0.fertig.contains(assets[2].kopf.kennung) }
        XCTAssertTrue(zwischen, "das erste Bild hat sein Häkchen, während das dritte noch aussteht")
        XCTAssertTrue(u.anzeigen.mit { $0.contains { $0.laufend.contains(assets[1].kopf.kennung) } }, "es gibt einen Moment, in dem das Bild als laufend gemeldet wird")
        XCTAssertEqual(try XCTUnwrap(u.anzeigen.mit { $0.last }).fertig.count, 3)
    }

    func testFehlerEinesBildesStehtBeiDiesemBild() async throws {
        let sender = FakeSender { r in r.value(forHTTPHeaderField: "X-Dateiname") == "kaputt.heic" ? .abgelehnt(400) : nil }
        let a = asset("a", [(.foto, "kaputt.heic")]), b = asset("b", [(.foto, "gut.heic")])
        let u = try baue(assets: [a, b], sender: sender)
        await u.abgleich.abgleichen()
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertEqual(letzte.fehler[a.kopf.kennung], "vom PC abgelehnt, Code 400")
        XCTAssertNil(letzte.fehler[b.kopf.kennung])
        XCTAssertEqual(FotoRaster.status(kennung: a.kopf.kennung, anzeige: letzte), .fehler("vom PC abgelehnt, Code 400"))
        XCTAssertEqual(FotoRaster.status(kennung: b.kopf.kennung, anzeige: letzte), .amPC)
    }

    func testEinstellungenAusDemLaufBleibenErhalten() async throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        let u = try baue(assets: viele(2), gleichzeitig: 1, ablage: ablage) { _ in
            ablage.aendere { $0.nurWLAN = false; $0.iCloudLaden = false }   // der Nutzer legt mitten im Lauf Schalter um
        }
        await u.abgleich.abgleichen()
        XCTAssertEqual(ablage.lade().nurWLAN, false)
        XCTAssertEqual(ablage.lade().iCloudLaden, false)
        XCTAssertEqual(u.quelle.iCloudWerte.mit { $0 }.last, false, "das nächste Stück liest den neuen Schalter")
    }

    func testICloudSchalterGehtAnDieQuelle() async throws {
        let u = try baue(assets: viele(1))
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.quelle.iCloudWerte.mit { $0 }, [true], "Standard: Originale aus iCloud laden")
    }

    func testZaehlenSendetNichts() async throws {
        let u = try baue(assets: viele(4))
        await u.abgleich.zaehle()
        XCTAssertEqual(u.sender.pfade, [])
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertEqual(letzte.zahlen, FotoZahlen(gesamt: 4, amPC: 0))
        XCTAssertFalse(letzte.laeuft)
        XCTAssertTrue(u.anzeigen.mit { $0.allSatisfy { !$0.laeuft } }, "ein Zähllauf zeigt nie 'läuft'")
    }

    func testEinzelUploadSendetNurDiesesBild() async throws {
        let assets = viele(3)
        let u = try baue(assets: assets)
        await u.abgleich.abgleichen(nur: [assets[1].kopf.assetId])
        XCTAssertEqual(u.sender.pfade, ["/v1/fotos/\(assets[1].kopf.kennung)/foto-0"])
        XCTAssertEqual(u.ablage.lade().fertig, [assets[1].kopf.kennung])
    }
}

