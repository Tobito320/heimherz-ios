import Foundation

/// Warum ein Eintrag in "Sicherheit" steht.
enum SicherheitsGrund: Int, Comparable, Hashable, Sendable {
    case datenleck, wiederverwendet, schwach

    static func < (a: SicherheitsGrund, b: SicherheitsGrund) -> Bool { a.rawValue < b.rawValue }

    var text: String {
        switch self {
        case .datenleck: return "In einem Datenleck gefunden"
        case .wiederverwendet: return "Bereits verwendetes Passwort"
        case .schwach: return "Schwaches Passwort"
        }
    }
}

/// Ein Hinweis zu einem Eintrag. Enthält nie das Passwort selbst, nur die id und die Gründe (der wichtigste zuerst).
struct SicherheitsHinweis: Equatable, Sendable, Identifiable {
    let eintragId: String
    let gruende: [SicherheitsGrund]
    var id: String { eintragId }
    var text: String { gruende.first?.text ?? "" }
}

/// Wiederverwendet und schwach prüft das Handy selbst, ohne Netz. Datenlecks kommen von `LeckPruefung` (Pwned Passwords, nur wenn die Einstellung an ist,
/// k-Anonymität: nur 5 Zeichen eines SHA-1 gehen raus, nie das Passwort); hier fließt nur das Ergebnis (`lecks`, Eintrags-ids) ein.
enum PasswortSicherheit {
    static let mindestLaenge = 8
    /// Ab dieser Länge ist ein Passwort nie "zu kurz oder zu einfach" (Passphrasen aus kleingeschriebenen Wörtern sind stark); Muster zählen trotzdem.
    static let sicherLaenge = 16

    private static let haeufig: Set<String> = [
        "password", "passwort", "passw0rd", "12345678", "123456789", "1234567890", "qwertz", "qwerty", "qwertzuiop", "iloveyou",
        "letmein", "welcome", "willkommen", "admin", "administrator", "hallo", "geheim", "abc123", "sommer", "winter", "fussball", "monkey", "dragon", "master"
    ]
    private static let reihen = ["qwertzuiop", "qwertyuiop", "asdfghjkl", "yxcvbnm", "zxcvbnm", "1234567890", "0987654321", "abcdefghijklmnopqrstuvwxyz"]

    /// Alle Einträge mit einem Hinweis, in der Reihenfolge der übergebenen Einträge. Nur lebendige Logins mit Passwort zählen.
    /// `lecks`: ids, deren Passwort in einem Datenleck steckt (steht als wichtigster Grund zuerst).
    static func pruefe(_ eintraege: [Eintrag], lecks: Set<String> = []) -> [SicherheitsHinweis] {
        let logins = eintraege.filter { !$0.geloescht && $0.art == Eintrag.artLogin && !$0.passwort.isEmpty }
        var haeufigkeit: [String: Int] = [:]
        for e in logins { haeufigkeit[e.passwort, default: 0] += 1 }
        return logins.compactMap { e in
            var gruende: [SicherheitsGrund] = []
            if lecks.contains(e.id) { gruende.append(.datenleck) }
            if (haeufigkeit[e.passwort] ?? 0) > 1 { gruende.append(.wiederverwendet) }
            if istSchwach(e.passwort, benutzer: e.benutzer, name: e.name) { gruende.append(.schwach) }
            return gruende.isEmpty ? nil : SicherheitsHinweis(eintragId: e.id, gruende: gruende)
        }
    }

    static func istSchwach(_ passwort: String, benutzer: String = "", name: String = "") -> Bool {
        let p = passwort
        guard !p.isEmpty else { return false }
        let klein = p.lowercased()
        if klein == benutzer.lowercased() || klein == name.lowercased() { return true }
        let zeichen = Array(klein.unicodeScalars)
        if Set(zeichen).count <= 2 { return true }                                         // aaaaaaaa, abababab
        if istLaufendeFolge(zeichen) { return true }                                       // 12345678, abcdefgh, 987654321
        if p.count >= 6, reihen.contains(where: { $0.contains(klein) || String($0.reversed()).contains(klein) }) { return true }   // qwertz, asdfgh
        if istWiederholterBlock(zeichen) { return true }                                   // 123123123, abcabcabc
        if haeufig.contains(klein) || haeufig.contains(klein.trimmingCharacters(in: .decimalDigits)) { return true }   // passwort, passwort123
        if p.count >= sicherLaenge { return false }
        if p.count < mindestLaenge { return true }
        if p.count < 12, p.allSatisfy(\.isNumber) { return true }                          // nur Ziffern (PIN-artig)
        return false
    }

    /// Jedes Zeichen ist um genau 1 größer (oder kleiner) als das vorige: 12345678, abcdefgh, 98765432.
    private static func istLaufendeFolge(_ z: [Unicode.Scalar]) -> Bool {
        guard z.count >= 4 else { return false }
        let schritt = Int(z[1].value) - Int(z[0].value)
        guard schritt == 1 || schritt == -1 else { return false }
        return zip(z, z.dropFirst()).allSatisfy { Int($1.value) - Int($0.value) == schritt }
    }

    /// Ein Baustein von 1 bis 4 Zeichen, mindestens dreimal wiederholt (ganz, ohne Rest).
    private static func istWiederholterBlock(_ z: [Unicode.Scalar]) -> Bool {
        for laenge in 1...4 where z.count % laenge == 0 && z.count / laenge >= 3 {
            let block = Array(z[0..<laenge])
            if stride(from: 0, to: z.count, by: laenge).allSatisfy({ Array(z[$0..<($0 + laenge)]) == block }) { return true }
        }
        return false
    }
}
