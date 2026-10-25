import XCTest
@testable import Heimherz

final class CredentialImportTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)
    private var stempel: String { Zeit.iso(jetzt) }

    private func konto(_ titel: String, benutzer: String = "mia", passwort: String = "neu-pw-1", urls: [String] = ["https://github.com/login"], totp: String = "", notiz: String = "",
                       passkeys: [ImportPasskey] = []) -> ImportKonto {
        ImportKonto(titel: titel, benutzer: benutzer, passwort: passwort, urls: urls, totp: totp, notiz: notiz, passkeys: passkeys)
    }

    private func passkey(_ id: String = "cred-1", rp: String = "github.com") -> ImportPasskey {
        ImportPasskey(credentialId: id, rpId: rp, userName: "mia", userDisplayName: "Mia", userHandle: "aGFuZGxl", schluessel: "c2NobHVlc3NlbA")
    }

    func testNeuesKontoMitAllenFeldern() {
        let uri = ImportAbbildung.totpURI(geheim: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), periode: 30, stellen: 6, algorithmus: "sha1", aussteller: "GitHub", benutzer: "mia")
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(), [konto("GitHub", urls: ["https://github.com/login", "https://gist.github.com"], totp: uri, notiz: "Arbeit")], jetzt: jetzt)
        XCTAssertEqual(z, ImportZaehler(neu: 1, aktualisiert: 0, passkeys: 0, uebersprungen: 0))
        let e = t.eintraege[0]
        XCTAssertEqual([e.name, e.benutzer, e.passwort, e.notiz], ["GitHub", "mia", "neu-pw-1", "Arbeit"])
        XCTAssertEqual(e.urls, ["https://github.com/login", "https://gist.github.com"])
        XCTAssertEqual(e.totp, uri)
        XCTAssertEqual(e.geaendert, stempel)
        XCTAssertFalse(e.geloescht)
        XCTAssertEqual(e.art, Eintrag.artLogin)
    }

    func testTotpURIWirdVomTresorGelesen() throws {
        let geheim = Data("12345678901234567890".utf8)
        let uri = ImportAbbildung.totpURI(geheim: geheim, periode: 30, stellen: 8, algorithmus: "sha256", aussteller: "Ex Ample", benutzer: "mia@example.org")
        XCTAssertTrue(uri.hasPrefix("otpauth://totp/Ex%20Ample:mia%40example.org?"), uri)
        let einstellung = try XCTUnwrap(TOTP.einstellung(aus: uri))
        XCTAssertEqual(einstellung.geheim, geheim)
        XCTAssertEqual([einstellung.stellen, einstellung.periode], [8, 30])
        XCTAssertEqual(einstellung.algorithmus, .sha256)
        XCTAssertEqual(ImportAbbildung.base32Text(Data("foobar".utf8)), "MZXW6YTBOI")
        XCTAssertEqual(ImportAbbildung.base32Text(Data("fooba".utf8)), "MZXW6YTB")
        XCTAssertEqual(ImportAbbildung.base32Text(Data()), "")
    }

    func testBase64urlOhneFuellzeichen() {
        XCTAssertEqual(ImportAbbildung.base64url(Data([0xfb, 0xff, 0x01, 0x02])), "-_8BAg")
        XCTAssertEqual(ImportAbbildung.base64url(Data([0x01])), "AQ")
    }

    func testGleicherHostBenutzerUndPasswortWirdUebersprungen() {
        let da = Eintrag(id: "x", name: "GitHub", benutzer: "Mia", passwort: "neu-pw-1", urls: ["https://github.com"], geaendert: "2026-01-01T00:00:00.000Z")
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(eintraege: [da]), [konto("GitHub")], uebersprungenVorher: 2, jetzt: jetzt)
        XCTAssertEqual(t.eintraege, [da], "nichts angefasst, auch der Zeitstempel nicht")
        XCTAssertEqual(z, ImportZaehler(neu: 0, aktualisiert: 0, passkeys: 0, uebersprungen: 3))
    }

    func testAnderesPasswortAktualisiertUndMerktDasAlte() {
        let da = Eintrag(id: "x", name: "GitHub", benutzer: "mia", passwort: "alt-pw", urls: ["https://github.com"], notiz: "meine Notiz", geaendert: "2026-01-01T00:00:00.000Z",
                         unbekannt: ["zukunft": .text("bleibt")])
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(eintraege: [da]), [konto("GitHub", notiz: "andere Notiz", urls: ["https://github.com/login", "https://neu.example"])], jetzt: jetzt)
        XCTAssertEqual(t.eintraege.count, 1)
        let e = t.eintraege[0]
        XCTAssertEqual(e.id, "x")
        XCTAssertEqual(e.passwort, "neu-pw-1")
        XCTAssertEqual(e.geaendert, stempel)
        XCTAssertEqual(e.notiz, "meine Notiz", "eigene Notiz bleibt")
        XCTAssertEqual(e.urls, ["https://github.com", "https://neu.example"], "neue Seite kommt dazu, bekannte Hosts nicht doppelt")
        XCTAssertEqual(e.unbekannt["zukunft"], .text("bleibt"))
        XCTAssertEqual(e.unbekannt["passwortVerlauf"], .liste([.objekt(["passwort": .text("alt-pw"), "bis": .text(stempel)])]))
        XCTAssertEqual(z, ImportZaehler(neu: 0, aktualisiert: 1, passkeys: 0, uebersprungen: 0))
    }

    func testAndererBenutzerOderHostIstEinNeuerEintrag() {
        let da = Eintrag(id: "x", name: "GitHub", benutzer: "mia", passwort: "pw", urls: ["https://github.com"])
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(eintraege: [da]), [konto("GitHub", benutzer: "max"), konto("GitLab", urls: ["https://gitlab.com"])], jetzt: jetzt)
        XCTAssertEqual(t.eintraege.count, 3)
        XCTAssertEqual(z.neu, 2)
    }

    func testGeloeschterEintragZaehltNichtAlsVorhanden() {
        var da = Eintrag(id: "x", name: "GitHub", benutzer: "mia", passwort: "neu-pw-1", urls: ["https://github.com"])
        da.geloescht = true
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(eintraege: [da]), [konto("GitHub")], jetzt: jetzt)
        XCTAssertEqual(z.neu, 1)
        XCTAssertEqual(t.lebendige.count, 1)
    }

    func testPasskeysAnLoginUndAlsEigenerEintrag() throws {
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(), [
            konto("GitHub", passkeys: [passkey("a"), passkey("b")]),
            ImportKonto(titel: "", benutzer: "bob@example.com", passwort: "", urls: [], passkeys: [passkey("c", rp: "example.com")])
        ], jetzt: jetzt)
        XCTAssertEqual(z, ImportZaehler(neu: 2, aktualisiert: 0, passkeys: 3, uebersprungen: 0))
        XCTAssertEqual(t.eintraege[0].unbekannt["passkeys"]?.alsListe?.count, 2)
        let nur = t.eintraege[1]
        XCTAssertEqual(nur.name, "example.com", "ohne Titel: der Host der Seite")
        XCTAssertEqual(nur.urls, ["https://example.com"])
        XCTAssertEqual(PasswoerterLogik.passkeys(von: nur), [PasskeyKonto(seite: "example.com", konto: "mia")])
        let w = try XCTUnwrap(t.eintraege[0].unbekannt["passkeys"]?.alsListe?.first)
        guard case .objekt(let d) = w else { return XCTFail("kein Objekt") }
        XCTAssertEqual(d["rpId"], .text("github.com"))
        XCTAssertEqual(d["credentialId"], .text("a"))
        XCTAssertEqual(d["userHandle"], .text("aGFuZGxl"))
        XCTAssertEqual(d["key"], .text("c2NobHVlc3NlbA"))
    }

    func testPasskeysKommenNurEinmalDazu() {
        let erster = ImportAbbildung.einarbeiten(Tresor(), [konto("GitHub", passkeys: [passkey("a")])], jetzt: jetzt)
        let zweiter = ImportAbbildung.einarbeiten(erster.tresor, [konto("GitHub", passkeys: [passkey("a"), passkey("b")])], jetzt: jetzt.addingTimeInterval(60))
        XCTAssertEqual(zweiter.zaehler, ImportZaehler(neu: 0, aktualisiert: 0, passkeys: 1, uebersprungen: 0), "gleiches Passwort, nur ein neuer Passkey")
        XCTAssertEqual(zweiter.tresor.eintraege[0].unbekannt["passkeys"]?.alsListe?.count, 2)
        let dritter = ImportAbbildung.einarbeiten(zweiter.tresor, [konto("GitHub", passkeys: [passkey("a"), passkey("b")])], jetzt: jetzt.addingTimeInterval(120))
        XCTAssertEqual(dritter.zaehler, ImportZaehler(neu: 0, aktualisiert: 0, passkeys: 0, uebersprungen: 1))
        XCTAssertEqual(dritter.tresor, zweiter.tresor)
    }

    func testPasskeyAusBitwardenWirdNichtDoppeltGesichert() {
        let fido: JSONWert = .liste([.objekt(["credentialId": .text("a"), "rpId": .text("github.com")])])
        let da = Eintrag(id: "x", name: "GitHub", benutzer: "mia", passwort: "neu-pw-1", urls: ["https://github.com"], unbekannt: ["bitwardenFido2": fido])
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(eintraege: [da]), [konto("GitHub", passkeys: [passkey("a")])], jetzt: jetzt)
        XCTAssertEqual(z.passkeys, 0)
        XCTAssertNil(t.eintraege[0].unbekannt["passkeys"])
    }

    func testDoppelteImselbenImportWerdenUebersprungen() {
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(), [konto("GitHub"), konto("GitHub")], jetzt: jetzt)
        XCTAssertEqual(t.eintraege.count, 1)
        XCTAssertEqual(z, ImportZaehler(neu: 1, aktualisiert: 0, passkeys: 0, uebersprungen: 1))
    }

    func testNotizen() {
        var n = ImportKonto(titel: "Ferienhaus", notiz: "Schlüssel liegt im Briefkasten")
        n.art = Eintrag.artNotiz
        let erster = ImportAbbildung.einarbeiten(Tresor(), [n], jetzt: jetzt)
        XCTAssertEqual(erster.tresor.eintraege[0].art, Eintrag.artNotiz)
        XCTAssertEqual(erster.tresor.eintraege[0].notiz, "Schlüssel liegt im Briefkasten")
        XCTAssertEqual(erster.zaehler.neu, 1)
        let zweiter = ImportAbbildung.einarbeiten(erster.tresor, [n], jetzt: jetzt)
        XCTAssertEqual(zweiter.zaehler, ImportZaehler(neu: 0, aktualisiert: 0, passkeys: 0, uebersprungen: 1))
    }

    func testZaehlerTextNurZahlen() {
        XCTAssertEqual(ImportZaehler(neu: 3, aktualisiert: 2, passkeys: 1, uebersprungen: 4).text, "3 neu, 2 aktualisiert, 1 Passkeys gesichert, 4 übersprungen")
    }

    func testImportierteEintraegeBleibenNachDemMischenMitDemPC() {
        let (t, _) = ImportAbbildung.einarbeiten(Tresor(), [konto("GitHub", passkeys: [passkey("a")])], jetzt: jetzt)
        let zurueck = try? Tresor.aus(daten: t.jsonDaten)
        XCTAssertEqual(zurueck, t, "Passkey-Feld überlebt Schreiben und Lesen des Tresors")
    }
}
