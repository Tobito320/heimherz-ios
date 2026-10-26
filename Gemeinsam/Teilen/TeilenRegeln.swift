import Foundation

/// Fehler, die nur beim Teilen vorkommen.
enum TeilenFehler: Error, Equatable {
    /// Die App, aus der geteilt wird, hat die Datei nicht herausgegeben.
    case nichtLesbar
}

/// Reine Regeln der Teilen-Erweiterung (W-045, SPEC 12). Liegen in `Gemeinsam/`, damit die Tests sie sehen.
enum TeilenRegeln {
    /// Zielpfad am PC: immer direkt in `Eingang/`; der Dienst legt den Ordner an und überschreibt nie (`name (2).ext`).
    static func zielPfad(name: String) -> String { "Eingang/" + sauber(name) }

    /// Nur der Dateiname: kein `/`, kein Punkt vorn (der Dienst versteckt oder weist solche Namen ab), nie leer.
    static func sauber(_ name: String) -> String {
        var n = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "Datei" : n
    }

    static func kopfzeile(anzahl: Int) -> String { anzahl == 1 ? "1 Datei an den PC" : "\(anzahl) Dateien an den PC" }

    static func fortschritt(gesendet: Int, von: Int) -> String { "\(gesendet) von \(von)" }

    /// Bei diesen Fehlern wartet auch der Rest der Dateien (PC aus, Handy unbekannt, Platte voll); sonst geht es mit der nächsten weiter.
    static func haeltAn(_ fehler: Error) -> Bool {
        guard let f = fehler as? HeimFehler else { return false }
        return f.istNetzproblem || f == .nichtBerechtigt || f == .speicherVoll || f == .nichtGekoppelt || f == .ungueltigeAdresse
    }

    static func fehlerText(_ fehler: Error) -> String {
        if fehler as? TeilenFehler == .nichtLesbar { return "Die Datei konnte nicht gelesen werden" }
        guard let f = fehler as? HeimFehler else { return fehler.localizedDescription }
        if f == .nichtGekoppelt { return "Lumen Cloud ist nicht gekoppelt" }
        if f.istNetzproblem { return "PC nicht erreichbar" }
        return f.nutzerText
    }

    /// Eine Zeile für den Fehlerfall; bei Teilerfolg steht vorn, wie viele schon am PC sind.
    static func fehlerZeile(_ fehler: Error, gesendet: Int, von: Int) -> String {
        let grund = fehlerText(fehler)
        return gesendet > 0 ? "\(gesendet) von \(von) gesendet. \(grund)" : grund
    }
}
