import AuthenticationServices
import XCTest
@testable import Heimherz

final class EintragSucheTests: XCTestCase {
    func testHostAusUrlOhneSchemaMitPortUndGrossschreibung() {
        XCTAssertEqual(EintragSuche.host(von: "https://GitHub.com/login?x=1"), "github.com")
        XCTAssertEqual(EintragSuche.host(von: "github.com/login"), "github.com")
        XCTAssertEqual(EintragSuche.host(von: "  http://user:pw@Mail.Example.org:8080/a "), "mail.example.org")
        XCTAssertEqual(EintragSuche.host(von: "example.com."), "example.com")
        XCTAssertNil(EintragSuche.host(von: ""))
        XCTAssertNil(EintragSuche.host(von: "   "))
    }

    func testPasstAnDerPunktgrenze() {
        XCTAssertTrue(EintragSuche.passt(eintragHost: "example.com", anfrageHost: "example.com"))
        XCTAssertTrue(EintragSuche.passt(eintragHost: "example.com", anfrageHost: "m.example.com"))
        XCTAssertTrue(EintragSuche.passt(eintragHost: "login.example.com", anfrageHost: "example.com"))
        XCTAssertFalse(EintragSuche.passt(eintragHost: "example.com", anfrageHost: "evilexample.com"))
        XCTAssertFalse(EintragSuche.passt(eintragHost: "evilexample.com", anfrageHost: "example.com"))
        XCTAssertFalse(EintragSuche.passt(eintragHost: "example.com", anfrageHost: "example.org"))
        XCTAssertFalse(EintragSuche.passt(eintragHost: "com", anfrageHost: "example.com"), "ein Rest ohne Punkt passt nie")
        XCTAssertFalse(EintragSuche.passt(eintragHost: "example.com", anfrageHost: "com"))
        XCTAssertFalse(EintragSuche.passt(eintragHost: "localhost", anfrageHost: "evil.localhost"))
    }

    func testHostsAusServiceBezeichnern() {
        var ids = [
            ASCredentialServiceIdentifier(identifier: "https://m.example.com/login", type: .URL),
            ASCredentialServiceIdentifier(identifier: "example.com", type: .domain)
        ]
        if #available(iOS 26.2, *) { ids.append(ASCredentialServiceIdentifier(identifier: "com.beispiel.app", type: .app)) }
        XCTAssertEqual(EintragSuche.hosts(von: ids), ["m.example.com", "example.com"], "Bundle-IDs haben keinen Host")
    }

    func testHostsEinesEintragsOhneDoppelte() {
        let e = Eintrag(id: "1", name: "x", urls: ["https://a.org/x", "a.org", "", "https://b.org"])
        XCTAssertEqual(EintragSuche.hosts(von: e), ["a.org", "b.org"])
    }

    func testAufteilenNurLoginsUndNachName() {
        let eintraege = [
            Eintrag(id: "1", name: "Zebra", urls: ["https://example.com"]),
            Eintrag(id: "2", name: "Anker", urls: ["https://m.example.com"]),
            Eintrag(id: "3", name: "Fremd", urls: ["https://evilexample.com"]),
            Eintrag(id: "4", art: Eintrag.artNotiz, name: "Notiz", urls: ["https://example.com"]),
            Eintrag(id: "5", name: "Weg", urls: ["https://example.com"], geloescht: true)
        ]
        let t = EintragSuche.aufteilen(eintraege, anfrageHosts: ["example.com"])
        XCTAssertEqual(t.passend.map(\.id), ["2", "1"])
        XCTAssertEqual(t.uebrige.map(\.id), ["3"])
        let ohne = EintragSuche.aufteilen(eintraege, anfrageHosts: [])
        XCTAssertEqual(ohne.passend.count, 0)
        XCTAssertEqual(ohne.uebrige.map(\.id), ["2", "3", "1"])
    }

    func testFiltern() {
        let eintraege = [
            Eintrag(id: "1", name: "GitHub", benutzer: "mia", urls: ["https://github.com"]),
            Eintrag(id: "2", name: "Café", benutzer: "tom@example.org", urls: ["https://cafe.example.org"]),
            Eintrag(id: "3", name: "Bank", benutzer: "anna", passwort: "githubgeheim", urls: [])
        ]
        XCTAssertEqual(EintragSuche.filtern(eintraege, begriff: "").count, 3)
        XCTAssertEqual(EintragSuche.filtern(eintraege, begriff: "GITHUB").map(\.id), ["1"], "Passwörter werden nie durchsucht")
        XCTAssertEqual(EintragSuche.filtern(eintraege, begriff: "cafe").map(\.id), ["2"], "ohne Akzent und Großschreibung")
        XCTAssertEqual(EintragSuche.filtern(eintraege, begriff: "tom example").map(\.id), ["2"], "alle Wörter müssen passen")
        XCTAssertEqual(EintragSuche.filtern(eintraege, begriff: "mia.com").count, 0)
    }
}

final class AutoFillIdentitaetenTests: XCTestCase {
    private func login(_ id: String, benutzer: String = "mia", urls: [String], totp: String = "", favorit: Bool = false, geloescht: Bool = false, art: String = Eintrag.artLogin) -> Eintrag {
        Eintrag(id: id, art: art, name: "Name \(id)", benutzer: benutzer, passwort: "GEHEIM-\(id)", urls: urls, totp: totp, favorit: favorit, geloescht: geloescht)
    }

    func testPasswortIdentitaetJeHostMitIdUndBenutzer() throws {
        let t = Tresor(eintraege: [login("a", urls: ["https://github.com", "https://www.github.com"], favorit: true)])
        let liste = AutoFillIdentitaeten.baue(aus: t)
        XCTAssertEqual(liste.count, 2)
        let p = try XCTUnwrap(liste.first as? ASPasswordCredentialIdentity)
        XCTAssertEqual(p.serviceIdentifier.identifier, "github.com")
        XCTAssertEqual(p.serviceIdentifier.type, .domain)
        XCTAssertEqual(p.user, "mia")
        XCTAssertEqual(p.recordIdentifier, "a")
        XCTAssertEqual(p.rank, 1)
    }

    func testOhneTotpKeineEinmalcodeIdentitaet() {
        let liste = AutoFillIdentitaeten.baue(aus: Tresor(eintraege: [login("a", urls: ["https://x.org"], totp: "kein base32!")]))
        XCTAssertEqual(liste.count, 1)
        XCTAssertTrue(liste[0] is ASPasswordCredentialIdentity)
    }

    func testMitTotpEinmalcodeIdentitaetOhneGeheimnisImLabel() throws {
        let liste = AutoFillIdentitaeten.baue(aus: Tresor(eintraege: [login("a", urls: ["https://x.org"], totp: "JBSWY3DPEHPK3PXP")]))
        XCTAssertEqual(liste.count, 2)
        let o = try XCTUnwrap(liste.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }.first)
        XCTAssertEqual(o.recordIdentifier, "a")
        XCTAssertEqual(o.serviceIdentifier.identifier, "x.org")
        XCTAssertFalse(o.label.contains("JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(o.label.contains("GEHEIM"))
    }

    func testKeinPasswortUndKeinGeheimnisInIrgendeinerIdentitaet() {
        let t = Tresor(eintraege: [login("a", urls: ["https://x.org"], totp: "JBSWY3DPEHPK3PXP")])
        for i in AutoFillIdentitaeten.baue(aus: t) {
            XCTAssertFalse("\(i)".contains("GEHEIM-a"))
            XCTAssertFalse("\(i)".contains("JBSWY3DPEHPK3PXP"))
        }
    }

    func testNotizenGrabsteineUndEintraegeOhneHostFehlen() {
        let t = Tresor(eintraege: [
            login("n", urls: ["https://x.org"], art: Eintrag.artNotiz),
            login("g", urls: ["https://x.org"], geloescht: true),
            login("h", urls: []),
            login("leer", urls: ["   "])
        ])
        XCTAssertEqual(AutoFillIdentitaeten.baue(aus: t).count, 0)
    }

    func testEintragOhneBenutzerBekommtNurEinmalcode() {
        let t = Tresor(eintraege: [login("a", benutzer: "", urls: ["https://x.org"], totp: "JBSWY3DPEHPK3PXP")])
        let liste = AutoFillIdentitaeten.baue(aus: t)
        XCTAssertEqual(liste.count, 1)
        XCTAssertTrue(liste[0] is ASOneTimeCodeCredentialIdentity)
    }
}
