import Foundation

/// Ein Tresoreintrag (SPEC 5). Feldnamen und Reihenfolge beim Schreiben wie dort; unbekannte Felder bleiben in `unbekannt` erhalten.
/// Gelöschte Einträge bleiben als Grabstein (`geloescht == true`, Felder leer) 90 Tage im Tresor (`Zusammenfuehren`).
struct Eintrag: Codable, Sendable, Equatable, Identifiable {
    static let artLogin = "login"
    static let artNotiz = "notiz"

    var id: String
    /// `login` oder `notiz`; ein unbekannter Wert eines neueren Geräts bleibt stehen.
    var art: String
    var name: String
    var benutzer: String
    var passwort: String
    var urls: [String]
    /// `otpauth://`-URI oder rohes Base32 (`TOTP`), leer ohne Einmalcode.
    var totp: String
    var notiz: String
    var favorit: Bool
    /// ISO-Zeit mit Millisekunden in UTC (`Zeit.iso`). Bei jeder Änderung neu setzen, sonst gewinnt die Merge-Regel falsch.
    var geaendert: String
    var geloescht: Bool
    /// Felder, die diese App-Version nicht kennt.
    var unbekannt: [String: JSONWert]

    init(id: String = UUID().uuidString, art: String = Eintrag.artLogin, name: String, benutzer: String = "", passwort: String = "",
         urls: [String] = [], totp: String = "", notiz: String = "", favorit: Bool = false,
         geaendert: String = Zeit.iso(Date()), geloescht: Bool = false, unbekannt: [String: JSONWert] = [:]) {
        self.id = id
        self.art = art
        self.name = name
        self.benutzer = benutzer
        self.passwort = passwort
        self.urls = urls
        self.totp = totp
        self.notiz = notiz
        self.favorit = favorit
        self.geaendert = geaendert
        self.geloescht = geloescht
        self.unbekannt = unbekannt
    }

    /// Fehlende Felder bekommen Standardwerte; nur die `id` muss da sein, sonst fielen alle solche Einträge im Merge zusammen.
    init(from decoder: Decoder) throws {
        try self.init(wert: JSONWert(from: decoder))
    }

    init(wert: JSONWert) throws {
        guard case .objekt(var d) = wert else {
            throw DecodingError.typeMismatch(Eintrag.self, .init(codingPath: [], debugDescription: "Eintrag ist kein Objekt"))
        }
        guard let id = d.removeValue(forKey: "id")?.alsText, !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Eintrag ohne id"))
        }
        self.id = id
        art = d.removeValue(forKey: "art")?.alsText ?? Eintrag.artLogin
        name = d.removeValue(forKey: "name")?.alsText ?? ""
        benutzer = d.removeValue(forKey: "benutzer")?.alsText ?? ""
        passwort = d.removeValue(forKey: "passwort")?.alsText ?? ""
        urls = (d.removeValue(forKey: "urls")?.alsListe ?? []).compactMap(\.alsText)
        totp = d.removeValue(forKey: "totp")?.alsText ?? ""
        notiz = d.removeValue(forKey: "notiz")?.alsText ?? ""
        favorit = d.removeValue(forKey: "favorit")?.alsBool ?? false
        geaendert = d.removeValue(forKey: "geaendert")?.alsText ?? ""
        geloescht = d.removeValue(forKey: "geloescht")?.alsBool ?? false
        unbekannt = d
    }

    func encode(to encoder: Encoder) throws {
        try wert.encode(to: encoder)
    }

    /// Alle Felder als JSON-Wert (bekannte und unbekannte).
    var wert: JSONWert {
        var d = unbekannt
        d["id"] = .text(id)
        d["art"] = .text(art)
        d["name"] = .text(name)
        d["benutzer"] = .text(benutzer)
        d["passwort"] = .text(passwort)
        d["urls"] = .liste(urls.map { .text($0) })
        d["totp"] = .text(totp)
        d["notiz"] = .text(notiz)
        d["favorit"] = .bool(favorit)
        d["geaendert"] = .text(geaendert)
        d["geloescht"] = .bool(geloescht)
        return .objekt(d)
    }

    /// JSON-Text wie `JSON.stringify` in TS: bekannte Felder in SPEC-Reihenfolge, danach die unbekannten.
    func json() -> String {
        let vorn: [(String, String)] = [
            ("id", JSONWert.textLiteral(id)), ("art", JSONWert.textLiteral(art)), ("name", JSONWert.textLiteral(name)),
            ("benutzer", JSONWert.textLiteral(benutzer)), ("passwort", JSONWert.textLiteral(passwort)),
            ("urls", "[" + urls.map(JSONWert.textLiteral).joined(separator: ",") + "]"),
            ("totp", JSONWert.textLiteral(totp)), ("notiz", JSONWert.textLiteral(notiz)),
            ("favorit", favorit ? "true" : "false"), ("geaendert", JSONWert.textLiteral(geaendert)),
            ("geloescht", geloescht ? "true" : "false")
        ]
        return JSONWert.objektText(vorn: vorn, rest: unbekannt)
    }

    /// Der Grabstein zu diesem Eintrag: gleiche id, alle Inhalte leer, neuer Zeitstempel (so löschen Geräte per Merge mit).
    func alsGrabstein(geaendert: String = Zeit.iso(Date())) -> Eintrag {
        Eintrag(id: id, art: art, name: "", urls: [], geaendert: geaendert, geloescht: true)
    }
}
