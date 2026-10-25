#if DEBUG
import Foundation

extension TresorStore {
    /// Erfundene Einträge für die Screenshots in CI (`-heimherzDemo YES`); nie echte Daten. Deckt alle Seiten ab: doppeltes und schwaches Passwort,
    /// Codes, Passkeys, Gelöschtes, Umlaute und Ziffern am Namensanfang, einen sehr langen Namen, einen Verlauf geänderter Passwörter.
    static let demoTresor: Tresor = {
        let vor = { (tage: Double) in Zeit.iso(Date().addingTimeInterval(-tage * 86_400)) }
        let fido: JSONWert = .liste([.objekt(["rpId": .text("passkey.example.net"), "rpName": .text("Passkey Beispiel"), "userName": .text("mia")])])
        let verlauf: JSONWert = .liste([.objekt(["passwort": .text("frueher-nur-zum-ansehen"), "bis": .text(vor(40))])])
        return Tresor(eintraege: [
            Eintrag(id: "demo-1", name: "GitHub", benutzer: "mia", passwort: "demo-Lang-und-stark-1!", urls: ["https://github.com"],
                    totp: "JBSWY3DPEHPK3PXP", favorit: true, geaendert: vor(2), unbekannt: ["passwortVerlauf": verlauf]),
            Eintrag(id: "demo-2", name: "Online-Bank", benutzer: "mia.beispiel", passwort: "demo-zwei-sehr-lang-und-stark", urls: ["https://bank.example.org"], favorit: true, geaendert: vor(5)),
            Eintrag(id: "demo-3", name: "Café Sonnenschein", benutzer: "mia@example.org", passwort: "gleiches-demo-passwort-7", urls: ["https://cafe.example.org", "https://www.cafe.example.org"], geaendert: vor(9)),
            Eintrag(id: "demo-4", name: "Kino", benutzer: "mia", passwort: "gleiches-demo-passwort-7", urls: ["https://kino.example.org"], totp: "JBSWY3DPEHPK3PXP", geaendert: vor(12)),
            Eintrag(id: "demo-5", art: Eintrag.artNotiz, name: "WLAN im Ferienhaus", notiz: "Netzwerk Seeblick, Passwort steht am Kühlschrank.", geaendert: vor(20)),
            Eintrag(id: "demo-6", name: "Äpfel vom Hof", benutzer: "mia", passwort: "123456", urls: ["https://apfelhof.example.org"], geaendert: vor(30)),
            Eintrag(id: "demo-7", name: "1 Stunde Fitness", benutzer: "mia", passwort: "demo-sieben-stark-und-lang", urls: ["https://fitness.example.org"], geaendert: vor(33)),
            Eintrag(id: "demo-8", name: "Passkey Beispiel", benutzer: "mia", passwort: "demo-acht-stark-und-lang", urls: ["https://passkey.example.net"], geaendert: vor(40),
                    unbekannt: ["bitwardenFido2": fido]),
            Eintrag(id: "demo-9", name: "Bibliothek der Stadt mit einem wirklich sehr langen Namen, damit nichts abgeschnitten wird", benutzer: "mia.bibliothek.mit.langer.adresse@example.org",
                    passwort: "demo-neun-stark-und-lang", urls: ["https://bibliothek.example.org"], geaendert: vor(50)),
            Eintrag(id: "demo-10", name: "Zeitung", benutzer: "mia", passwort: "demo-zehn-stark-und-lang", urls: ["https://zeitung.example.org"], geaendert: vor(60)),
            Eintrag(id: "demo-11", name: "Bahn", benutzer: "mia", passwort: "demo-elf-stark-und-lang", urls: ["https://bahn.example.org"], geaendert: vor(70)),
            Eintrag(id: "demo-12", name: "Musik", benutzer: "mia", passwort: "demo-zwoelf-stark-und-lang", urls: ["https://musik.example.org"], geaendert: vor(80)),
            Eintrag(id: "demo-13", name: "Reisebüro", benutzer: "mia", passwort: "demo-dreizehn-stark-und-lang", urls: ["https://reisen.example.org"], geaendert: vor(90)),
            Eintrag(id: "demo-g1", name: "Altes Forum", benutzer: "mia", passwort: "demo-gelöscht-1", urls: ["https://forum.example.org"], geaendert: vor(3), geloescht: true),
            Eintrag(id: "demo-g2", name: "Probe-Abo", benutzer: "mia@example.org", passwort: "demo-gelöscht-2", urls: ["https://abo.example.org"], geaendert: vor(18), geloescht: true)
        ])
    }()
}
#endif
