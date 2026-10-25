import Foundation

/// Der ganze Tresor (SPEC 5): `{"format":1,"eintraege":[…]}`. Klartext lebt nur im Speicher; auf Platte und im Netz liegt nur der `Umschlag`.
/// Unbekannte Felder auf oberster Ebene bleiben erhalten.
struct Tresor: Codable, Sendable, Equatable {
    static let aktuellesFormat = 1

    var eintraege: [Eintrag]
    var unbekannt: [String: JSONWert]

    init(eintraege: [Eintrag] = [], unbekannt: [String: JSONWert] = [:]) {
        self.eintraege = eintraege
        self.unbekannt = unbekannt
    }

    init(from decoder: Decoder) throws {
        guard case .objekt(var d) = try JSONWert(from: decoder) else {
            throw DecodingError.typeMismatch(Tresor.self, .init(codingPath: decoder.codingPath, debugDescription: "Tresor ist kein Objekt"))
        }
        if case .zahl(let f)? = d.removeValue(forKey: "format"), f != Double(Tresor.aktuellesFormat) {
            throw TresorFehler.formatUnbekannt(Int(f))
        }
        let roh = d.removeValue(forKey: "eintraege")?.alsListe ?? []
        // Ein fehlerhafter Eintrag bricht das Öffnen ab, nie stilles Weglassen (sonst würde der Rest später ohne ihn zurückgeschrieben).
        eintraege = try roh.map { try Eintrag(wert: $0) }
        unbekannt = d
    }

    func encode(to encoder: Encoder) throws {
        var d = unbekannt
        d["format"] = .zahl(Double(Tresor.aktuellesFormat))
        d["eintraege"] = .liste(eintraege.map(\.wert))
        try JSONWert.objekt(d).encode(to: encoder)
    }

    /// JSON-Text wie `JSON.stringify` in TS (kompakt, Eintragsfelder in SPEC-Reihenfolge); das ist der Klartext, den `Umschlag` verschlüsselt.
    func json() -> String {
        let vorn = [("format", String(Tresor.aktuellesFormat)), ("eintraege", "[" + eintraege.map { $0.json() }.joined(separator: ",") + "]")]
        return JSONWert.objektText(vorn: vorn, rest: unbekannt)
    }

    var jsonDaten: Data { Data(json().utf8) }

    /// Liest einen Tresor aus Klartext-JSON.
    static func aus(daten: Data) throws -> Tresor {
        do {
            return try JSONDecoder().decode(Tresor.self, from: daten)
        } catch let fehler as TresorFehler {
            throw fehler
        } catch {
            throw TresorFehler.inhaltUngueltig
        }
    }

    /// Einträge ohne Grabsteine, für Anzeige und AutoFill.
    var lebendige: [Eintrag] { eintraege.filter { !$0.geloescht } }
}
