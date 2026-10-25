import Foundation

/// Zusammenführen zweier Tresore (SPEC 5), dieselben Regeln wie `lib/zusammenfuehren.ts`; beide lesen `fixtures/merge/*.json`.
/// - Pro `id` gewinnt das neuere `geaendert` (ganze Millisekunden).
/// - Gleichstand: der Grabstein gewinnt, sonst die größeren UTF-8-Bytes von `passwort NUL name NUL benutzer` (kein Swift-String-Vergleich).
/// - Einträge nur auf einer Seite bleiben; Grabsteine älter als 90 Tage fallen raus; Ergebnis nach UTF-8-Bytes der `id` sortiert.
/// Abweichung von TS: dort sortiert `<` nach UTF-16-Einheiten; das ist für UUIDs gleich und weicht nur bei ids außerhalb der Basisebene ab.
enum Zusammenfuehren {
    static let grabsteinTage = 90

    private static func bytes(_ e: Eintrag) -> [UInt8] {
        Array("\(e.passwort)\u{0}\(e.name)\u{0}\(e.benutzer)".utf8)
    }

    /// true, wenn `a` gegen `b` gewinnt. Ungültige Zeitstempel: `a` verliert (wie `NaN` in TS).
    static func gewinnt(_ a: Eintrag, _ b: Eintrag) -> Bool {
        guard let ma = Zeit.millis(iso: a.geaendert), let mb = Zeit.millis(iso: b.geaendert) else { return false }
        if ma != mb { return ma > mb }
        if a.geloescht != b.geloescht { return a.geloescht }
        return !bytes(a).lexicographicallyPrecedes(bytes(b))
    }

    /// `a` und `b` sind gleichberechtigt; das Ergebnis ist unabhängig von der Reihenfolge der Einträge (außer bei völlig gleichen Einträgen).
    static func zusammenfuehren(_ a: Tresor, _ b: Tresor, jetzt: Date = Date()) -> Tresor {
        // Schlüssel sind die UTF-8-Bytes der id: Swift gleicht `String` kanonisch ab, TS und der Server nach Code-Einheiten.
        var alle: [[UInt8]: Eintrag] = [:]
        for e in a.eintraege + b.eintraege {
            let schluessel = Array(e.id.utf8)
            if let da = alle[schluessel] {
                if gewinnt(e, da) { alle[schluessel] = e }
            } else {
                alle[schluessel] = e
            }
        }
        let grenze = Int64((jetzt.timeIntervalSince1970 * 1000).rounded(.down)) - Int64(grabsteinTage) * 86_400_000
        let eintraege = alle
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }
            .map(\.value)
            .filter { e in
                guard e.geloescht, let ms = Zeit.millis(iso: e.geaendert) else { return true }
                return ms >= grenze
            }
        var rest = b.unbekannt
        rest.merge(a.unbekannt) { _, neu in neu }
        return Tresor(eintraege: eintraege, unbekannt: rest)
    }
}
