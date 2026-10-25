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
    /// "dateiname:iCloud" in der Reihenfolge der Exportversuche.
    let versuche = Kasten<[String]>([])
    /// Diese Dateien liegen nur in iCloud: ohne iCloud-Erlaubnis scheitert der Export.
    var nurInICloud: Set<String> = []

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
        versuche.mit { $0.append("\(r.dateiname):\(iCloud)") }
        if !iCloud, nurInICloud.contains(r.dateiname) { throw FotoFehler.nurInICloud }
        try await beimExport?(r)
        let u = ordner.appending(path: "\(UUID().uuidString)-\(r.name)")
        try Data("inhalt \(r.name)".utf8).write(to: u)
        return u
    }
}

private final class FakeSender: FotoSender, Sendable {
    let anfragen = Kasten<[URLRequest]>([])
    let verhalten: @Sendable (URLRequest) -> HeimFehler?
    /// Läuft während des "Hochladens" (darf dauern oder hängen) und kennt die Temp-Datei.
    let waehrendDessen: (@Sendable (URL, URLRequest) async throws -> Void)?
    init(_ v: @escaping @Sendable (URLRequest) -> HeimFehler? = { _ in nil }, waehrendDessen: (@Sendable (URL, URLRequest) async throws -> Void)? = nil) {
        verhalten = v
        self.waehrendDessen = waehrendDessen
    }
    func sende(datei: URL, anfrage: URLRequest) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: datei.path), "die Datei muss beim Senden da sein")
        anfragen.mit { $0.append(anfrage) }
        try await waehrendDessen?(datei, anfrage)
        if let f = verhalten(anfrage) { throw f }
    }
    var pfade: [String] { anfragen.mit { $0.compactMap { $0.url?.path } } }
}

private struct FakeNetzart: Netzart {
    let wlan: Bool
    func istWLAN() async -> Bool { wlan }
}

final class FotoAbgleichTests: XCTestCase {
    private func asset(_ id: String, _ teile: [(art: FotoArt, dateiname: String)], video: Bool = false) -> (kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)]) {
        (FotoRegeln.kopf(assetId: id, istVideo: video), teile)
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
                      wlan: Bool = true, nurWLAN: Bool? = nil, sender: FakeSender = FakeSender(), gleichzeitig: Int = 2, voraus: Int = 0, stueck: Int = 20,
                      ablage vorhanden: FotoStandAblage? = nil, nurInICloud: Set<String> = [], beimExport: (@Sendable (FotoRessource) async throws -> Void)? = nil) throws -> Umgebung {
        let temp = try tempOrdner()
        let ablage = try vorhanden ?? FotoStandAblage(ordner: try tempOrdner())
        if let nurWLAN { ablage.aendere { $0.nurWLAN = nurWLAN } }
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/fotos/bekannt")
            return .json(bekannt, status: bekanntStatus)
        }
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        let anzeigen = Kasten<[FotoAnzeige]>([])
        var quelle = FakeQuelle(assets: assets, ordner: temp, beimExport: beimExport)
        quelle.nurInICloud = nurInICloud
        let a = FotoAbgleich(client: client, quelle: quelle, sender: sender, netz: FakeNetzart(wlan: wlan), ablage: ablage,
                             gleichzeitig: gleichzeitig, voraus: voraus, stueck: stueck, jetzt: { Date(timeIntervalSince1970: 1_800_000_000) }) { neu in anzeigen.mit { $0.append(neu) } }
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
        XCTAssertEqual(letzte.gesichert, 2, "b und c sind in diesem Lauf angekommen, a lag schon am PC")
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
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.gesichert, 0)
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
        let u = try baue(assets: viele(2), gleichzeitig: 1, stueck: 1, ablage: ablage) { _ in
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
        XCTAssertEqual(u.quelle.iCloudWerte.mit { $0 }, [false], "erster Durchgang: lokal, ohne iCloud-Download; die Datei war lokal, mehr braucht es nicht")
    }

    func testErstAllesLokalDannDieICloudOriginale() async throws {
        let assets = viele(3)
        let u = try baue(assets: assets, gleichzeitig: 1, nurInICloud: ["x2.heic"])
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.quelle.versuche.mit { $0 }, ["x1.heic:false", "x2.heic:false", "x3.heic:false", "x2.heic:true"], "x2 wartet auf den zweiten Durchgang")
        XCTAssertEqual(u.sender.pfade, [0, 2, 1].map { "/v1/fotos/\(assets[$0].kopf.kennung)/foto-0" }, "das Schnelle zuerst, das iCloud-Bild zuletzt")
        XCTAssertEqual(u.ablage.lade().fertig.count, 3)
        XCTAssertNil(u.ablage.lade().fehler, "Zurückstellen ist kein Fehler")
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.gesichert, 3)
    }

    func testOhneICloudErlaubnisBleibtDasICloudBildOffen() async throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        ablage.aendere { $0.iCloudLaden = false }
        let assets = viele(3)
        let u = try baue(assets: assets, gleichzeitig: 1, ablage: ablage, nurInICloud: ["x2.heic"])
        await u.abgleich.abgleichen()
        XCTAssertFalse(u.quelle.versuche.mit { $0 }.contains { $0.hasSuffix(":true") }, "kein Download")
        XCTAssertEqual(u.ablage.lade().fertig.count, 2)
        XCTAssertEqual(u.ablage.lade().fehler, "1 Datei konnte nicht übertragen werden (liegt nur in iCloud, und das Laden von iCloud ist aus).")
    }

    func testHoechstensZweiICloudDownloadsGleichzeitig() async throws {
        let jetzt = Kasten<Int>(0), hoechstens = Kasten<Int>(0)
        let namen = Set((1...6).map { "x\($0).heic" })
        let u = try baue(assets: viele(6), gleichzeitig: 6, nurInICloud: namen) { _ in
            let n = jetzt.mit { $0 += 1; return $0 }
            hoechstens.mit { $0 = max($0, n) }
            try await Task.sleep(for: .milliseconds(40))
            jetzt.mit { $0 -= 1 }
        }
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade.count, 6)
        XCTAssertEqual(hoechstens.mit { $0 }, 2, "zwei Downloads zugleich, nie mehr")
    }

    func testPufferGrenzeHaeltDenExportAnWennZuvielWartet() async throws {
        let exporte = Kasten<Int>(0)
        let hoechstensWartend = Kasten<Int>(0)
        let hochgeladen = Kasten<Int>(0)
        // Der erste Upload hängt kurz: bis dahin darf der Export höchstens `voraus` Dateien Vorsprung haben.
        let sender = FakeSender(waehrendDessen: { _, _ in
            try await Task.sleep(for: .milliseconds(150))
            hochgeladen.mit { $0 += 1 }
        })
        let u = try baue(assets: viele(20), sender: sender, gleichzeitig: 1, voraus: 3) { _ in
            let n = exporte.mit { $0 += 1; return $0 }
            hoechstensWartend.mit { $0 = max($0, n - hochgeladen.mit { $0 }) }
        }
        await u.abgleich.abgleichen()
        XCTAssertLessThanOrEqual(hoechstensWartend.mit { $0 }, 4, "ein Upload plus drei im Voraus exportiert")
        XCTAssertEqual(u.sender.pfade.count, 20)
    }

    /// Messung mit Attrappen: jeder Upload dauert 100 ms. Nacheinander brauchen 24 Dateien mehr als 2,4 s, sechs zugleich etwa ein Sechstel.
    func testParallelIstDeutlichSchnellerAlsNacheinander() async throws {
        func dauer(gleichzeitig: Int, voraus: Int) async throws -> Double {
            let sender = FakeSender(waehrendDessen: { _, _ in try await Task.sleep(for: .milliseconds(100)) })
            let u = try baue(assets: viele(24), sender: sender, gleichzeitig: gleichzeitig, voraus: voraus, stueck: 60)
            let start = ContinuousClock.now
            await u.abgleich.abgleichen()
            XCTAssertEqual(u.sender.pfade.count, 24)
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let nacheinander = try await dauer(gleichzeitig: 1, voraus: 0)
        let parallel = try await dauer(gleichzeitig: 6, voraus: 12)
        print("MESSUNG Attrappe: 24 Dateien je 100 ms: nacheinander \(nacheinander) s, sechs parallel \(parallel) s, Faktor \(nacheinander / parallel)")
        XCTAssertGreaterThan(nacheinander, 2.3)
        XCTAssertLessThan(parallel, nacheinander / 3, "mindestens dreimal schneller (ideal sechsmal)")
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

    func testAnhaltenInDerAnfangsphaseIstKeinFehler() async throws {
        let u = try baue(assets: viele(3))
        // Die Aufgabe bricht sich selbst ab, bevor der Abgleich anfängt: deterministisch wie ein Tipp auf "Anhalten" in den ersten Sekunden.
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await u.abgleich.abgleichen()
        }.value
        XCTAssertNil(u.ablage.lade().fehler, "Anhalten ist kein Fehler, auch nicht beim Abfragen des PCs")
        XCTAssertEqual(u.sender.pfade, [])
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertTrue(letzte.angehalten)
        XCTAssertFalse(letzte.laeuft)
    }

    func testEinzelUploadBehaeltDieZahlenVomLetztenMal() async throws {
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        ablage.aendere { $0.gesamt = 3 }
        let assets = viele(3)
        let u = try baue(assets: assets, ablage: ablage)
        await u.abgleich.abgleichen(nur: [assets[1].kopf.assetId])
        let alle = u.anzeigen.mit { $0 }
        XCTAssertEqual(alle.first?.zahlen, FotoZahlen(gesamt: 3, amPC: 0), "Überschrift und Balken verschwinden beim Start nicht")
        XCTAssertEqual(alle.last?.zahlen, FotoZahlen(gesamt: 3, amPC: 1), "das gesendete Bild zählt sofort mit")
    }

    // MARK: Parallel

    /// Zählt gleichzeitige Uploads und die Temp-Dateien, die dabei im Ordner liegen.
    private final class Messung: Sendable {
        let jetzt = Kasten<Int>(0)
        let hoechstens = Kasten<Int>(0)
        let hoechstensTemp = Kasten<Int>(0)
        func beginn(temp: URL) {
            let n = jetzt.mit { $0 += 1; return $0 }
            hoechstens.mit { $0 = max($0, n) }
            let dateien = (try? FileManager.default.contentsOfDirectory(atPath: temp.deletingLastPathComponent().path).count) ?? 0
            hoechstensTemp.mit { $0 = max($0, dateien) }
        }
        func ende() { jetzt.mit { $0 -= 1 } }
    }

    private func langsamerSender(_ m: Messung) -> FakeSender {
        FakeSender(waehrendDessen: { datei, _ in
            m.beginn(temp: datei)
            defer { m.ende() }
            try await Task.sleep(for: .milliseconds(40))
        })
    }

    func testVierUploadsGleichzeitigUndJedeDateiNurEinmal() async throws {
        let m = Messung()
        let assets = viele(24)
        let u = try baue(assets: assets, sender: langsamerSender(m), gleichzeitig: 4, voraus: 1, stueck: 7)
        await u.abgleich.abgleichen()

        XCTAssertEqual(m.hoechstens.mit { $0 }, 4, "vier gleichzeitig, nie mehr")
        let pfade = u.sender.pfade
        XCTAssertEqual(pfade.count, 24)
        XCTAssertEqual(Set(pfade), Set(assets.map { "/v1/fotos/\($0.kopf.kennung)/foto-0" }), "jede Datei genau einmal, keine doppelt (sonst 409 am PC)")
        XCTAssertEqual(u.ablage.lade().fertig.count, 24)
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.gesichert, 24)
        XCTAssertEqual(dateienIn(u.temp), [])
    }

    func testHoechstensGleichzeitigePlusEineTempDatei() async throws {
        let m = Messung()
        let u = try baue(assets: viele(20), sender: langsamerSender(m), gleichzeitig: 4, voraus: 1)
        await u.abgleich.abgleichen()
        XCTAssertLessThanOrEqual(m.hoechstensTemp.mit { $0 }, 5, "vier im Upload plus eine schon exportierte")
        XCTAssertEqual(u.sender.pfade.count, 20)
    }

    func testDieNaechsteDateiWirdExportiert_WaehrendDieErsteHochgeht() async throws {
        let exporte = Kasten<Int>(0)
        let erreicht = Kasten<Bool>(false)
        let sender = FakeSender(waehrendDessen: { _, _ in
            // Der erste Upload wartet, bis der zweite Export angefangen hat; ohne Vorlauf käme der nie und die Zeit liefe ab.
            for _ in 0..<100 where exporte.mit({ $0 }) < 2 { try await Task.sleep(for: .milliseconds(30)) }
            if exporte.mit({ $0 }) >= 2 { erreicht.mit { $0 = true } }
        })
        let u = try baue(assets: viele(2), sender: sender, gleichzeitig: 1, voraus: 1) { _ in exporte.mit { $0 += 1 } }
        await u.abgleich.abgleichen()
        XCTAssertTrue(erreicht.mit { $0 }, "der zweite Export lief, während der erste Upload noch ging")
        XCTAssertEqual(u.sender.pfade.count, 2)
    }

    func testAnhaltenBrichtAlleParallelenUploadsAbUndRaeumtAuf() async throws {
        let (signal, weiter) = AsyncStream.makeStream(of: Void.self)
        let gestartet = Kasten<Int>(0)
        let sender = FakeSender(waehrendDessen: { _, _ in
            if gestartet.mit({ $0 += 1; return $0 }) == 4 { weiter.yield(Void()) }
            try await Task.sleep(for: .seconds(60))   // hängt, bis der Abbruch kommt
        })
        let u = try baue(assets: viele(12), sender: sender, gleichzeitig: 4, voraus: 1)
        let lauf = Task { await u.abgleich.abgleichen() }
        for await _ in signal { break }
        lauf.cancel()
        await lauf.value

        XCTAssertEqual(dateienIn(u.temp), [], "halbe Exporte und laufende Uploads sind verworfen")
        XCTAssertNil(u.ablage.lade().fehler, "Anhalten ist kein Fehler")
        XCTAssertEqual(u.ablage.lade().fertig, [], "nichts war fertig")
        let letzte = try XCTUnwrap(u.anzeigen.mit { $0.last })
        XCTAssertTrue(letzte.angehalten)
        XCTAssertFalse(letzte.laeuft)
        XCTAssertEqual(letzte.laufend, [])
        XCTAssertEqual(letzte.gesichert, 0)
        XCTAssertEqual(gestartet.mit { $0 }, 4, "der fünfte stand nur bereit und kam nicht mehr zum Zug")
    }

    func testFertigeDateienZaehlenBeimAnhaltenAuchBeiParallelerArbeit() async throws {
        let (signal, weiter) = AsyncStream.makeStream(of: Void.self)
        let fertige = Kasten<Int>(0)
        // x1 und x2 gehen sofort durch, alle anderen hängen.
        let sender = FakeSender(waehrendDessen: { _, anfrage in
            if anfrage.value(forHTTPHeaderField: "X-Dateiname") == "x1.heic" || anfrage.value(forHTTPHeaderField: "X-Dateiname") == "x2.heic" {
                if fertige.mit({ $0 += 1; return $0 }) == 2 { weiter.yield(Void()) }
                return
            }
            try await Task.sleep(for: .seconds(60))
        })
        let assets = viele(8)
        let u = try baue(assets: assets, sender: sender, gleichzeitig: 4, voraus: 1)
        let lauf = Task { await u.abgleich.abgleichen() }
        for await _ in signal { break }
        try await Task.sleep(for: .milliseconds(200))   // der Abschluss der beiden wird verbucht
        lauf.cancel()
        await lauf.value
        XCTAssertEqual(u.ablage.lade().fertig, [assets[0].kopf.kennung, assets[1].kopf.kennung])
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.gesichert, 2)
        XCTAssertEqual(dateienIn(u.temp), [])
    }

    func testLivePhotoGehtMitBeidenDateienParallelOhneDoppelte() async throws {
        let m = Messung()
        let a = asset("a", [(.foto, "IMG.HEIC"), (.live, "IMG.MOV")]), b = asset("b", [(.foto, "IMG2.HEIC"), (.live, "IMG2.MOV")])
        let u = try baue(assets: [a, b], sender: langsamerSender(m), gleichzeitig: 4, voraus: 1)
        await u.abgleich.abgleichen()
        XCTAssertEqual(Set(u.sender.pfade).count, 4)
        XCTAssertEqual(u.sender.pfade.count, 4)
        XCTAssertEqual(u.ablage.lade().fertig, [a.kopf.kennung, b.kopf.kennung])
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.gesichert, 2, "ein Live Photo zählt einmal")
    }

    // MARK: Reihenfolge: Fotos vor Videos

    func testErstAlleFotosDannAlleVideosJeNeuesteZuerst() async throws {
        // Mediathek, neueste zuerst: Video, Foto, Video, Foto, Live Photo (bleibt ein Foto).
        let v1 = asset("v1", [(.video, "v1.mov")], video: true), f1 = asset("f1", [(.foto, "f1.heic")]), v2 = asset("v2", [(.video, "v2.mov")], video: true)
        let f2 = asset("f2", [(.foto, "f2.heic")]), l = asset("l", [(.foto, "l.heic"), (.live, "l.mov")])
        let u = try baue(assets: [v1, f1, v2, f2, l], gleichzeitig: 1)
        await u.abgleich.abgleichen()
        let erwartet = [
            "/v1/fotos/\(f1.kopf.kennung)/foto-0", "/v1/fotos/\(f2.kopf.kennung)/foto-0",
            "/v1/fotos/\(l.kopf.kennung)/foto-0", "/v1/fotos/\(l.kopf.kennung)/live-0",
            "/v1/fotos/\(v1.kopf.kennung)/video-0", "/v1/fotos/\(v2.kopf.kennung)/video-0"
        ]
        XCTAssertEqual(u.sender.pfade, erwartet, "Fotos (auch das ganze Live Photo) vor allen Videos, innerhalb davon neueste zuerst")
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.phasen, FotoPhasen(fotosGesamt: 3, fotosAmPC: 3, videosGesamt: 2, videosAmPC: 2))
    }

    func testVideosWartenAuchBeimErstenStueck() async throws {
        // Ein kleines Stück (2 Dateien) darf nicht schon Videos enthalten, solange noch Fotos offen sind.
        let v = asset("v", [(.video, "v.mov")], video: true)
        let fotos = (1...4).map { asset("f\($0)", [(.foto, "f\($0).heic")]) }
        let u = try baue(assets: [v] + fotos, gleichzeitig: 1, stueck: 2)
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.sender.pfade.last, "/v1/fotos/\(v.kopf.kennung)/video-0")
        XCTAssertEqual(u.sender.pfade.count, 5)
    }

    func testLokalFotosLokalVideosICloudFotosICloudVideos() async throws {
        let f1 = asset("f1", [(.foto, "f1.heic")]), f2 = asset("f2", [(.foto, "f2.heic")])
        let v1 = asset("v1", [(.video, "v1.mov")], video: true), v2 = asset("v2", [(.video, "v2.mov")], video: true)
        let u = try baue(assets: [v1, f1, v2, f2], gleichzeitig: 1, nurInICloud: ["f1.heic", "v1.mov"])
        await u.abgleich.abgleichen()
        XCTAssertEqual(u.quelle.versuche.mit { $0 }, ["f1.heic:false", "f2.heic:false", "v1.mov:false", "v2.mov:false", "f1.heic:true", "v1.mov:true"],
                       "lokal Fotos, lokal Videos, dann iCloud Fotos, iCloud Videos")
    }

    func testPhasenZahlenInDerPlanung() {
        let k = (1...5).map { FotoRegeln.kopf(assetId: "a\($0)", istVideo: $0 % 2 == 0) }   // a2 und a4 sind Videos
        func dateien(_ kopf: FotoKopf) -> [FotoRessource] { FotoRegeln.ressourcen(kopf: kopf, aufnahme: nil, teile: [(art: kopf.istVideo ? .video : .foto, dateiname: "x")]) }
        let p = FotoPlan.plane(koepfe: k, stand: FotoStand(), ressourcen: dateien)
        XCTAssertEqual(p.offen.map(\.assetId), ["a1", "a3", "a5", "a2", "a4"])
        XCTAssertEqual(p.phasen, FotoPhasen(fotosGesamt: 3, fotosAmPC: 0, videosGesamt: 2, videosAmPC: 0))
        let erstes = FotoPlan.plane(koepfe: k, stand: FotoStand(), hoechstens: 3, ressourcen: dateien)
        XCTAssertEqual(erstes.offen.map(\.assetId), ["a1", "a3", "a5"], "das erste Stück sind nur Fotos")
        var s = FotoStand()
        s.fertig = [k[0].kennung, k[1].kennung]
        let q = FotoPlan.plane(koepfe: k, stand: s, ressourcen: dateien)
        XCTAssertEqual(q.phasen, FotoPhasen(fotosGesamt: 3, fotosAmPC: 1, videosGesamt: 2, videosAmPC: 1))
        XCTAssertEqual(q.zahlen, FotoZahlen(gesamt: 5, amPC: 2))
    }

    func testPhasenText() {
        XCTAssertEqual(FotoText.phasen(FotoPhasen(fotosGesamt: 6_900, fotosAmPC: 4_812, videosGesamt: 625, videosAmPC: 0)), "Fotos: \(4_812.formatted()) von \(6_900.formatted()) · danach \(625.formatted()) Videos")
        XCTAssertEqual(FotoText.phasen(FotoPhasen(fotosGesamt: 10, fotosAmPC: 10, videosGesamt: 5, videosAmPC: 2)), "Videos: 2 von 5")
        XCTAssertEqual(FotoText.phasen(FotoPhasen(fotosGesamt: 10, fotosAmPC: 4, videosGesamt: 1, videosAmPC: 0)), "Fotos: 4 von 10 · danach 1 Video")
        XCTAssertNil(FotoText.phasen(FotoPhasen(fotosGesamt: 10, fotosAmPC: 4, videosGesamt: 0, videosAmPC: 0)), "ohne Videos genügt die Überschrift")
        XCTAssertNil(FotoText.phasen(FotoPhasen(fotosGesamt: 10, fotosAmPC: 10, videosGesamt: 5, videosAmPC: 5)))
        XCTAssertNil(FotoText.phasen(nil))
    }
}
