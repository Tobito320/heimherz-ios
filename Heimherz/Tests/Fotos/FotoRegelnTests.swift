import Photos
import XCTest
@testable import Heimherz

final class FotoRegelnTests: XCTestCase {
    func testKennungIstSHA256AlsB64urlOhneFuellzeichen() {
        // SHA-256("abc") = ba7816bf ... (FIPS 180-2), als b64url
        XCTAssertEqual(FotoRegeln.kennung(assetId: "abc"), "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
        let echt = FotoRegeln.kennung(assetId: "9F6A1B2C-0000-4000-8000-000000000001/L0/001")
        XCTAssertEqual(echt.count, 43)
        XCTAssertTrue(HeimClient.istKennung(echt), "der Server nimmt nur [A-Za-z0-9_-]")
    }

    func testNamenSindArtPlusIndexUndStabil() {
        let kopf = FotoRegeln.kopf(assetId: "A")
        let teile: [(art: FotoArt, dateiname: String)] = [(.foto, "IMG_1.HEIC"), (.live, "IMG_1.MOV"), (.foto, "IMG_1b.JPG"), (.alternative, "IMG_1.DNG")]
        let a = FotoRegeln.ressourcen(kopf: kopf, aufnahme: nil, teile: teile)
        XCTAssertEqual(a.map(\.name), ["foto-0", "live-0", "foto-1", "alternative-0"])
        XCTAssertEqual(a, FotoRegeln.ressourcen(kopf: kopf, aufnahme: nil, teile: teile))
        XCTAssertTrue(a.allSatisfy { HeimClient.istKennung($0.name) })
        XCTAssertEqual(a[0].schluessel, "\(kopf.kennung)/foto-0")
    }

    func testNurOriginaleZaehlen() {
        XCTAssertEqual(FotoArt(.photo), .foto)
        XCTAssertEqual(FotoArt(.video), .video)
        XCTAssertEqual(FotoArt(.pairedVideo), .live)
        XCTAssertEqual(FotoArt(.alternatePhoto), .alternative)
        XCTAssertEqual(FotoArt(.audio), .ton)
        XCTAssertNil(FotoArt(.fullSizePhoto))
        XCTAssertNil(FotoArt(.fullSizeVideo))
        XCTAssertNil(FotoArt(.adjustmentData))
        XCTAssertTrue(FotoArt.video.istVideo && FotoArt.live.istVideo && !FotoArt.foto.istVideo)
    }

    func testSchluesselAusPfadDerUploadAnfrage() throws {
        let c = HeimClient(basis: try XCTUnwrap(URL(string: "https://pc.example.ts.net")), token: TestSchluessel.token)
        let r = try c.fotoHochladenAnfrage(kennung: "K1", ressource: "foto-0", aufnahme: nil, dateiname: "x.heic")
        XCTAssertEqual(FotoRegeln.schluessel(pfad: try XCTUnwrap(r.url).path), "K1/foto-0")
        for schlecht in ["/v1/tresor", "/v1/fotos/bekannt", "/v1/fotos/a/b/c", "/x/fotos/a/b", ""] {
            XCTAssertNil(FotoRegeln.schluessel(pfad: schlecht), schlecht)
        }
    }

    // MARK: Fotos von selbst (SPEC 31)

    func testAbgleichStartetBeimOeffnenNurWennAllesPasstUndNichtAngehalten() {
        func start(gekoppelt: Bool = true, voll: Bool = true, laeuft: Bool = false, angehalten: Bool = false) -> Bool {
            FotoRegeln.startetVonSelbst(gekoppelt: gekoppelt, erlaubnisVoll: voll, laeuft: laeuft, vomNutzerAngehalten: angehalten)
        }
        XCTAssertTrue(start())
        XCTAssertFalse(start(gekoppelt: false), "ohne Kopplung gibt es kein Token")
        XCTAssertFalse(start(voll: false), "ohne volle Erlaubnis sieht die App nicht alle Fotos")
        XCTAssertFalse(start(laeuft: true), "nie zwei Läufe")
        XCTAssertFalse(start(angehalten: true), "W-003: nach Anhalten läuft nichts von selbst wieder an")
    }

    func testErweiterungIstStandardAnUndRespektiertDenSchalterDesNutzers() {
        XCTAssertTrue(FotoRegeln.erweiterungSollAn(gekoppelt: true, erlaubnisVoll: true, nutzerHatAusgeschaltet: false))
        XCTAssertFalse(FotoRegeln.erweiterungSollAn(gekoppelt: true, erlaubnisVoll: true, nutzerHatAusgeschaltet: true))
        XCTAssertFalse(FotoRegeln.erweiterungSollAn(gekoppelt: false, erlaubnisVoll: true, nutzerHatAusgeschaltet: false), "ohne Kopplung gäbe es Jobs ohne Zugang")
        XCTAssertFalse(FotoRegeln.erweiterungSollAn(gekoppelt: true, erlaubnisVoll: false, nutzerHatAusgeschaltet: false), "Apple verlangt volle Erlaubnis")
    }

    func testNachtlaufAuchOhneStromAberNichtImStromsparmodusAufDemAkku() {
        XCTAssertTrue(FotoRegeln.nachtlaufErlaubt(stromsparmodus: false, amStrom: false))
        XCTAssertTrue(FotoRegeln.nachtlaufErlaubt(stromsparmodus: true, amStrom: true))
        XCTAssertFalse(FotoRegeln.nachtlaufErlaubt(stromsparmodus: true, amStrom: false))
    }
}
