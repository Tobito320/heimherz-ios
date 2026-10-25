import XCTest
@testable import Heimherz

/// Mediathek aus erfundenen Assets; schreibt echte Temp-Dateien, damit das Aufräumen prüfbar ist.
private struct FakeQuelle: FotoQuelle {
    let assets: [(kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)])]
    let ordner: URL
    var aufnahme: Date? = Date(timeIntervalSince1970: 1_790_000_000)

    func plane(stand: FotoStand) async -> FotoPlan.Ergebnis {
        FotoPlan.plane(koepfe: assets.map(\.kopf), stand: stand) { k in
            guard let a = assets.first(where: { $0.kopf == k }) else { return [] }
            return FotoRegeln.ressourcen(kopf: k, aufnahme: aufnahme, teile: a.teile)
        }
    }

    func exportiere(_ r: FotoRessource, fortschritt: @escaping @Sendable (Double) -> Void) async throws -> URL {
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
    }

    private func baue(assets: [(kopf: FotoKopf, teile: [(art: FotoArt, dateiname: String)])], bekannt: String = "[]", bekanntStatus: Int = 200,
                      wlan: Bool = true, nurWLAN: Bool? = nil, sender: FakeSender = FakeSender()) throws -> Umgebung {
        let temp = try tempOrdner()
        let ablage = FotoStandAblage(ordner: try tempOrdner())
        if let nurWLAN { ablage.aendere { $0.nurWLAN = nurWLAN } }
        let (sitzung, basis) = FakeNetz.neu { r, _ in
            XCTAssertEqual(r.url?.path, "/v1/fotos/bekannt")
            return .json(bekannt, status: bekanntStatus)
        }
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        let anzeigen = Kasten<[FotoAnzeige]>([])
        let a = FotoAbgleich(client: client, quelle: FakeQuelle(assets: assets, ordner: temp), sender: sender, netz: FakeNetzart(wlan: wlan), ablage: ablage,
                             jetzt: { Date(timeIntervalSince1970: 1_800_000_000) }) { neu in anzeigen.mit { $0.append(neu) } }
        return Umgebung(abgleich: a, sender: sender, ablage: ablage, temp: temp, anzeigen: anzeigen)
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
        XCTAssertEqual(u.ablage.lade().fehler, "1 Datei konnte nicht übertragen werden.")
        XCTAssertEqual(u.anzeigen.mit { $0.last }?.zahlen, FotoZahlen(gesamt: 3, amPC: 2))
    }
}
