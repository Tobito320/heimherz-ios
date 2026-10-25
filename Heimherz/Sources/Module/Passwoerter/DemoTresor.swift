#if DEBUG
import Foundation

extension TresorStore {
    /// Erfundene Einträge für die Screenshots in CI (`-heimherzDemo YES`); nie echte Daten.
    static let demoTresor = Tresor(eintraege: [
        Eintrag(id: "demo-1", name: "GitHub", benutzer: "mia", passwort: "demo-nur-zum-ansehen", urls: ["https://github.com"],
                totp: "JBSWY3DPEHPK3PXP", favorit: true),
        Eintrag(id: "demo-2", name: "Online-Bank", benutzer: "mia.beispiel", passwort: "demo-zwei", urls: ["https://bank.example.org"], favorit: true),
        Eintrag(id: "demo-3", name: "Café Sonnenschein", benutzer: "mia@example.org", passwort: "demo-drei", urls: ["https://cafe.example.org", "https://www.cafe.example.org"]),
        Eintrag(id: "demo-4", name: "Kino", benutzer: "mia", passwort: "demo-vier", urls: ["https://kino.example.org"], totp: "JBSWY3DPEHPK3PXP"),
        Eintrag(id: "demo-5", art: Eintrag.artNotiz, name: "WLAN im Ferienhaus", notiz: "Netzwerk Seeblick, Passwort steht am Kühlschrank.")
    ])
}
#endif
