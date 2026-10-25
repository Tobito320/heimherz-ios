import Foundation

/// Die Eingaben des Formulars für Neu und Bearbeiten, getrennt vom `Eintrag`, damit Prüfen und Übernehmen testbar sind.
/// `anwenden(auf:)` ändert nur die Felder des Formulars; unbekannte Felder und die `id` des Eintrags bleiben (SPEC 5).
struct Entwurf: Equatable {
    struct UrlFeld: Identifiable, Equatable {
        let id: UUID
        var text: String
        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    var art: String
    var name = ""
    var benutzer = ""
    var passwort = ""
    var urlFelder: [UrlFeld] = [UrlFeld()]
    var totp = ""
    var notiz = ""
    var favorit = false

    init(art: String = Eintrag.artLogin) {
        self.art = art
    }

    init(eintrag: Eintrag) {
        art = eintrag.art
        name = eintrag.name
        benutzer = eintrag.benutzer
        passwort = eintrag.passwort
        urlFelder = eintrag.urls.isEmpty ? [UrlFeld()] : eintrag.urls.map { UrlFeld(text: $0) }
        totp = eintrag.totp
        notiz = eintrag.notiz
        favorit = eintrag.favorit
    }

    var urls: [String] {
        urlFelder.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var totpGueltig: Bool {
        let t = totp.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || TOTP.einstellung(aus: t) != nil
    }

    /// Speichern geht mit einem Namen (bei Logins ersatzweise einer Webseite) und lesbarem Einmalcode.
    var kannSpeichern: Bool {
        let hatName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hatName || (art == Eintrag.artLogin && !urls.isEmpty)) && totpGueltig
    }

    /// Der Eintrag mit den Eingaben. Notizen haben nur Name, Text und Favorit; die Login-Felder bleiben leer.
    func anwenden(auf eintrag: Eintrag) -> Eintrag {
        var e = eintrag
        let sauberName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        e.name = sauberName.isEmpty ? (urls.first.flatMap(EintragSuche.host(von:)) ?? "") : sauberName
        e.notiz = notiz
        e.favorit = favorit
        if art == Eintrag.artLogin {
            e.benutzer = benutzer.trimmingCharacters(in: .whitespacesAndNewlines)
            e.passwort = passwort
            e.urls = urls
            e.totp = totp.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return e
    }

    /// Ein neuer Eintrag aus den Eingaben.
    func neuerEintrag() -> Eintrag {
        anwenden(auf: Eintrag(art: art, name: ""))
    }
}
