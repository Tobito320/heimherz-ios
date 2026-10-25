import Foundation

/// Beliebiger JSON-Wert. Hält die unbekannten Felder des Tresors (SPEC 5), damit sie beim Lesen und Schreiben erhalten bleiben
/// (ein älteres Gerät darf Felder eines neueren nie verlieren).
enum JSONWert: Sendable, Equatable {
    case null
    case bool(Bool)
    case zahl(Double)
    case text(String)
    case liste([JSONWert])
    case objekt([String: JSONWert])

    var alsText: String? { if case .text(let t) = self { return t } else { return nil } }
    var alsBool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var alsListe: [JSONWert]? { if case .liste(let l) = self { return l } else { return nil } }
}

extension JSONWert: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .zahl(d)
        } else if let s = try? c.decode(String.self) {
            self = .text(s)
        } else if let l = try? c.decode([JSONWert].self) {
            self = .liste(l)
        } else {
            self = .objekt(try c.decode([String: JSONWert].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .zahl(let d): try c.encode(d)
        case .text(let t): try c.encode(t)
        case .liste(let l): try c.encode(l)
        case .objekt(let o): try c.encode(o)
        }
    }
}

/// Eigener Schreiber statt `JSONEncoder`: derselbe Text wie `JSON.stringify` in TS (kompakt, `/` unmaskiert, rohes UTF-8,
/// Schlüssel in fester Reihenfolge). Nur so ist der verschlüsselte Umschlag aus Swift und TS byte-gleich (Fixture `umschlag-1.json`).
extension JSONWert {
    /// Kompakter JSON-Text. Objektschlüssel stehen nach UTF-8-Bytes sortiert.
    var jsonText: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .zahl(let d): return Self.zahlText(d)
        case .text(let t): return Self.textLiteral(t)
        case .liste(let l): return "[" + l.map(\.jsonText).joined(separator: ",") + "]"
        case .objekt(let o): return Self.objektText(vorn: [], rest: o)
        }
    }

    /// Objekt aus schon geschriebenen Paaren (feste Reihenfolge) gefolgt von den übrigen Schlüsseln, sortiert nach UTF-8-Bytes.
    static func objektText(vorn: [(String, String)], rest: [String: JSONWert]) -> String {
        var teile = vorn.map { textLiteral($0.0) + ":" + $0.1 }
        for k in rest.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }) {
            if let w = rest[k] { teile.append(textLiteral(k) + ":" + w.jsonText) }
        }
        return "{" + teile.joined(separator: ",") + "}"
    }

    static func textLiteral(_ t: String) -> String {
        var s = "\""
        for u in t.unicodeScalars {
            switch u {
            case "\"": s += "\\\""
            case "\\": s += "\\\\"
            case "\u{08}": s += "\\b"
            case "\u{0C}": s += "\\f"
            case "\n": s += "\\n"
            case "\r": s += "\\r"
            case "\t": s += "\\t"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    s += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    s.unicodeScalars.append(u)
                }
            }
        }
        return s + "\""
    }

    /// Ganze Zahlen ohne Nachkomma wie in JS (`1`, nie `1.0`).
    /// shortcut: Kommazahlen schreibt Swift, nicht JS-genau (`1.5e-07` statt `1.5e-7`); der Tresor hat keine, nur unbekannte Felder könnten welche tragen.
    static func zahlText(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }
}
