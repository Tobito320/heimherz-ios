import XCTest
@testable import Heimherz

final class PasswortSicherheitTests: XCTestCase {
    private func login(_ id: String, _ pw: String, name: String = "Seite", benutzer: String = "mia") -> Eintrag {
        Eintrag(id: id, name: name, benutzer: benutzer, passwort: pw, urls: ["https://\(id).example.org"])
    }

    func testGleichesPasswortInZweiEintraegenIstBereitsVerwendet() {
        let h = PasswortSicherheit.pruefe([login("a", "Zr7!kQpL92xw"), login("b", "Zr7!kQpL92xw"), login("c", "Andere!Lang8ung")])
        XCTAssertEqual(h.map(\.eintragId), ["a", "b"])
        XCTAssertEqual(h.first?.gruende, [.wiederverwendet])
        XCTAssertEqual(h.first?.text, "Bereits verwendetes Passwort")
    }

    func testNotizenLeereGrabsteineUndGeloeschteZaehlenNicht() {
        let notiz = Eintrag(id: "n", art: Eintrag.artNotiz, name: "N", passwort: "Zr7!kQpL92xw")
        let leer1 = login("l1", ""), leer2 = login("l2", "")
        var weg = login("w", "Zr7!kQpL92xw"); weg.geloescht = true
        let h = PasswortSicherheit.pruefe([login("a", "Zr7!kQpL92xw"), notiz, leer1, leer2, weg])
        XCTAssertEqual(h, [], "ein einziges lebendiges Login mit diesem Passwort, die anderen zählen nicht")
    }

    func testSchwacheMuster() {
        for pw in ["kurz", "1234567", "12345678", "123456789012", "abcdefgh", "98765432", "aaaaaaaa", "abababab", "qwertz", "asdfghjk", "Passwort1", "passwort123",
                   "123123123", "abcabcabc", "00000000000000000", "11223344"] {
            XCTAssertTrue(PasswortSicherheit.istSchwach(pw), "\(pw) muss schwach sein")
        }
    }

    func testStarkeUndPassphrasenSindNichtSchwach() {
        for pw in ["cereal annual owner strong evidence sword", "regry7-ciXnaf-nuqjim", "Tr0ub4dor&3", "sonne mond sterne wolken regen", "kleinkariertgeschrieben", "Zr7!kQpL92xw"] {
            XCTAssertFalse(PasswortSicherheit.istSchwach(pw), "\(pw) darf nicht schwach sein")
        }
        XCTAssertFalse(PasswortSicherheit.istSchwach(""))
    }

    func testPasswortGleichBenutzerOderNameIstSchwach() {
        XCTAssertTrue(PasswortSicherheit.istSchwach("MiaBeispiel2026", benutzer: "miabeispiel2026"))
        XCTAssertTrue(PasswortSicherheit.istSchwach("Café Sonnenschein", name: "café sonnenschein"))
    }

    func testBeideGruendeWiederverwendetZuerst() {
        let h = PasswortSicherheit.pruefe([login("a", "passwort1"), login("b", "passwort1")])
        XCTAssertEqual(h.first?.gruende, [.wiederverwendet, .schwach])
    }

    func testHinweisEnthaeltKeinPasswort() {
        let h = PasswortSicherheit.pruefe([login("a", "passwort1")])
        XCTAssertFalse(String(describing: h).contains("passwort1"))
    }
}

final class PasswoerterLogikTests: XCTestCase {
    private let jetzt = Date(timeIntervalSince1970: 1_792_886_400)   // 2026-10-25

    private func tage(_ n: Int) -> String { Zeit.iso(jetzt.addingTimeInterval(Double(-n) * 86_400)) }

    private func tresor() -> Tresor {
        let fido: JSONWert = .liste([.objekt(["rpId": .text("passkey.example.net"), "rpName": .text("Passkey Example"), "userName": .text("max")])])
        let eigene: JSONWert = .liste([.objekt(["rpId": .text("github.com"), "userName": .text(""), "userDisplayName": .text("Mia")])])
        return Tresor(eintraege: [
            Eintrag(id: "1", name: "GitHub", benutzer: "mia", passwort: "Zr7!kQpL92xw", urls: ["https://github.com"], totp: "JBSWY3DPEHPK3PXP", favorit: true, geaendert: tage(1)),
            Eintrag(id: "2", name: "Passkey-Seite", benutzer: "max", passwort: "Zr7!kQpL92xw", urls: ["https://passkey.example.net"], geaendert: tage(2), unbekannt: ["bitwardenFido2": fido]),
            Eintrag(id: "3", name: "Kino", benutzer: "mia", passwort: "kurz", geaendert: tage(3), unbekannt: ["passkeys": eigene]),
            Eintrag(id: "4", art: Eintrag.artNotiz, name: "WLAN", notiz: "geheim", geaendert: tage(4)),
            Eintrag(id: "5", name: "Defekt", benutzer: "x", passwort: "Andere!Lang8ung", totp: "kein-base32-!!", geaendert: tage(5)),
            Eintrag(id: "6", name: "Frisch gelöscht", benutzer: "mia", passwort: "pw-gelöscht-1", geaendert: tage(10), geloescht: true),
            Eintrag(id: "7", name: "Zu alt gelöscht", benutzer: "mia", passwort: "pw-alt-1", geaendert: tage(31), geloescht: true),
            Eintrag(id: "8", name: "", geaendert: tage(1), geloescht: true)
        ])
    }

    func testKategorienUndZaehlerStimmenMitDenListenUeberein() {
        let t = tresor()
        let z = PasswoerterLogik.zaehler(in: t, jetzt: jetzt)
        for k in PasswoerterKategorie.allCases {
            XCTAssertEqual(z[k], PasswoerterLogik.eintraege(k, in: t, jetzt: jetzt).count, k.titel)
        }
        XCTAssertEqual(z[.alle], 5, "ohne Gelöschte, Notizen zählen mit")
        XCTAssertEqual(PasswoerterLogik.eintraege(.favoriten, in: t, jetzt: jetzt).map(\.id), ["1"])
        XCTAssertEqual(PasswoerterLogik.eintraege(.codes, in: t, jetzt: jetzt).map(\.id), ["1"], "ein unlesbares Geheimnis ist kein Code")
        XCTAssertEqual(PasswoerterLogik.eintraege(.passkeys, in: t, jetzt: jetzt).map(\.id), ["2", "3"])
        XCTAssertEqual(Set(PasswoerterLogik.eintraege(.sicherheit, in: t, jetzt: jetzt).map(\.id)), ["1", "2", "3"], "doppelt (1, 2) und schwach (3)")
    }

    func testGeloeschtZeigtNurWiederherstellbare() {
        let t = tresor()
        XCTAssertEqual(PasswoerterLogik.eintraege(.geloescht, in: t, jetzt: jetzt).map(\.id), ["6"])
        for k in PasswoerterKategorie.allCases where k != .geloescht {
            XCTAssertFalse(PasswoerterLogik.eintraege(k, in: t, jetzt: jetzt).contains { $0.geloescht }, "\(k.titel) zeigt nie einen Grabstein")
        }
    }

    func testGrenzeNachDreissigTagen() {
        let knapp = Eintrag(id: "k", name: "Knapp", passwort: "x", geaendert: Zeit.iso(jetzt.addingTimeInterval(-30 * 86_400)), geloescht: true)
        let darueber = Eintrag(id: "d", name: "Darüber", passwort: "x", geaendert: Zeit.iso(jetzt.addingTimeInterval(-30 * 86_400 - 0.001)), geloescht: true)
        XCTAssertTrue(PasswoerterLogik.istWiederherstellbar(knapp, jetzt: jetzt))
        XCTAssertFalse(PasswoerterLogik.istWiederherstellbar(darueber, jetzt: jetzt))
    }

    func testBereinigeLeertAlteGrabsteineMitNeuemStempel() throws {
        let t = tresor()
        let b = try XCTUnwrap(PasswoerterLogik.bereinige(t, jetzt: jetzt))
        let alt = try XCTUnwrap(b.eintraege.first { $0.id == "7" })
        XCTAssertTrue(alt.geloescht)
        XCTAssertEqual([alt.name, alt.passwort, alt.benutzer], ["", "", ""])
        XCTAssertEqual(alt.geaendert, Zeit.iso(jetzt), "neuer Stempel, sonst gewinnt beim Zusammenführen der Stein mit Inhalt")
        XCTAssertEqual(b.eintraege.first { $0.id == "6" }?.passwort, "pw-gelöscht-1", "frische bleiben")
        XCTAssertEqual(b.eintraege.first { $0.id == "1" }, t.eintraege.first { $0.id == "1" })
        XCTAssertNil(PasswoerterLogik.bereinige(b, jetzt: jetzt), "ein zweiter Lauf ändert nichts")
        let gemischt = Zusammenfuehren.zusammenfuehren(t, b, jetzt: jetzt)
        XCTAssertEqual(gemischt.eintraege.first { $0.id == "7" }?.passwort, "", "der geleerte Stein setzt sich gegen den alten mit Inhalt durch")
    }

    func testPasskeysAusBeidenQuellen() {
        let t = tresor()
        XCTAssertEqual(PasswoerterLogik.passkeys(von: t.eintraege[1]), [PasskeyKonto(seite: "Passkey Example", konto: "max")])
        XCTAssertEqual(PasswoerterLogik.passkeys(von: t.eintraege[2]), [PasskeyKonto(seite: "github.com", konto: "Mia")])
        XCTAssertEqual(PasswoerterLogik.passkeys(von: t.eintraege[0]), [])
    }

    func testAbschnitteNachNameMitUmlautenZiffernUndRaute() {
        let namen = ["Zeta", "Äther", "amazon", "1Password", "Ärzte", "Beta", "", "Éclair", "ßtrasse", "—Strich"]
        let e = namen.enumerated().map { Eintrag(id: "i\($0.offset)", name: $0.element) }
        let a = PasswoerterLogik.abschnitte(e, sortierung: .name)
        XCTAssertEqual(a.map(\.kennung), ["A", "B", "E", "S", "Z", "#"])
        XCTAssertEqual(a[0].eintraege.map(\.name), ["amazon", "Äther", "Ärzte"].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(Set(a.last?.eintraege.map(\.name) ?? []), ["1Password", "", "—Strich"])
        XCTAssertEqual(a.flatMap(\.eintraege).count, namen.count)
    }

    func testAbschnitteNachAenderungNeuesteZuerstEinAbschnitt() {
        let e = [Eintrag(id: "a", name: "A", geaendert: tage(5)), Eintrag(id: "b", name: "B", geaendert: tage(1)), Eintrag(id: "c", name: "C", geaendert: tage(3))]
        let a = PasswoerterLogik.abschnitte(e, sortierung: .geaendert)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].eintraege.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(PasswoerterLogik.abschnitte([], sortierung: .name), [])
        XCTAssertEqual(PasswoerterLogik.abschnitte([], sortierung: .geaendert), [])
    }
}

final class GrabsteinTests: XCTestCase {
    private let k = "2026-10-25T10:00:00.000Z"
    private let spaeter = "2026-10-26T10:00:00.000Z"

    private func eintrag() -> Eintrag {
        Eintrag(id: "a", name: "GitHub", benutzer: "mia", passwort: "geheim", urls: ["https://github.com"], totp: "JBSWY3DPEHPK3PXP", notiz: "n", favorit: true, geaendert: k,
                unbekannt: ["bitwardenFido2": .liste([.objekt(["keyValue": .text("privat")])]), "passwortVerlauf": .liste([.objekt(["passwort": .text("alt")])])])
    }

    func testLoeschenBehaeltAlleFelder() {
        let g = eintrag().alsGrabstein(geaendert: spaeter)
        XCTAssertTrue(g.geloescht)
        XCTAssertEqual(g.geaendert, spaeter)
        var erwartet = eintrag()
        erwartet.geloescht = true
        erwartet.geaendert = spaeter
        XCTAssertEqual(g, erwartet)
    }

    func testWiederherstellenIstLebendigMitNeuemStempelUndAllenFeldern() {
        let g = eintrag().alsGrabstein(geaendert: spaeter)
        let w = g.wiederhergestellt(geaendert: "2026-10-27T10:00:00.000Z")
        XCTAssertFalse(w.geloescht)
        XCTAssertEqual(w.geaendert, "2026-10-27T10:00:00.000Z")
        XCTAssertEqual(w.passwort, "geheim")
        XCTAssertEqual(w.unbekannt, eintrag().unbekannt)
    }

    func testEndgueltigLeertAuchDieUnbekanntenFelder() {
        let g = eintrag().alsGrabstein(geaendert: spaeter).endgueltigGeloescht(geaendert: "2026-10-27T10:00:00.000Z")
        XCTAssertTrue(g.geloescht)
        XCTAssertEqual([g.name, g.benutzer, g.passwort, g.totp, g.notiz], ["", "", "", "", ""])
        XCTAssertEqual(g.urls, [])
        XCTAssertEqual(g.unbekannt, [:], "Passkey-Schlüssel und alte Passwörter sind weg")
        XCTAssertFalse(g.favorit)
        XCTAssertFalse(g.hatInhalt)
        XCTAssertEqual(g.id, "a")
        XCTAssertTrue(eintrag().hatInhalt)
    }

    func testMergeMitGrabsteinMitFeldern() {
        let live = Tresor(eintraege: [eintrag()])
        let stein = Tresor(eintraege: [eintrag().alsGrabstein(geaendert: spaeter)])
        let zurueck = Tresor(eintraege: [eintrag().alsGrabstein(geaendert: spaeter).wiederhergestellt(geaendert: "2026-10-27T10:00:00.000Z")])
        let jetzt = Date(timeIntervalSince1970: 1_793_000_000)
        XCTAssertTrue(Zusammenfuehren.zusammenfuehren(live, stein, jetzt: jetzt).eintraege[0].geloescht, "der neuere Grabstein gewinnt gegen den lebenden")
        XCTAssertFalse(Zusammenfuehren.zusammenfuehren(stein, zurueck, jetzt: jetzt).eintraege[0].geloescht, "die neuere Wiederherstellung gewinnt gegen den Grabstein")
        XCTAssertEqual(Zusammenfuehren.zusammenfuehren(zurueck, stein, jetzt: jetzt), Zusammenfuehren.zusammenfuehren(stein, zurueck, jetzt: jetzt), "Reihenfolge egal")
        let endgueltig = Tresor(eintraege: [eintrag().endgueltigGeloescht(geaendert: "2026-10-28T10:00:00.000Z")])
        let ergebnis = Zusammenfuehren.zusammenfuehren(Zusammenfuehren.zusammenfuehren(stein, zurueck, jetzt: jetzt), endgueltig, jetzt: jetzt)
        XCTAssertEqual(ergebnis.eintraege[0].passwort, "", "endgültig gelöscht gewinnt, wenn es das Neueste ist")
    }

    func testAutoFillKenntKeinenGrabsteinMitInhalt() {
        let t = Tresor(eintraege: [eintrag().alsGrabstein(geaendert: spaeter)])
        XCTAssertTrue(AutoFillIdentitaeten.baue(aus: t).isEmpty)
        XCTAssertEqual(EintragSuche.logins(in: t.eintraege), [])
        XCTAssertEqual(EintragSuche.aufteilen(t.eintraege, anfrageHosts: ["github.com"]).passend, [])
        guard case .neu = PasswortSpeichern.plane(in: t, host: "github.com", name: "GitHub", benutzer: "mia", passwort: "geheim", jetzt: Date()) else { return XCTFail("kein Treffer im Papierkorb") }
    }
}
