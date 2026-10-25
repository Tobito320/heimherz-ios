import Foundation

/// Einstellungen des Passwort-Generators (SPEC 9): Zeichen-Modus (Länge 8 bis 64, Ziffern, Sonderzeichen) oder Wortgruppen-Modus.
struct PasswortRegeln: Sendable, Equatable {
    enum Modus: Sendable, Hashable { case zeichen, wortgruppe }

    var modus: Modus = .zeichen
    var laenge = 20
    var ziffern = true
    var sonderzeichen = true
    var woerter = 5
    var trenner = "-"
    var grossschreiben = true
    var mitZahl = true
}

/// Erzeugt Passwörter aus dem Zufallsgenerator des Systems. Der Generator ist ein Parameter, damit Tests ihn festlegen können.
/// Gleichverteilt: `Int.random(in:using:)` und `randomElement(using:)` ziehen ohne Modulo-Verzerrung.
enum PasswortGenerator {
    static let laengen = 8...64
    static let wortAnzahl = 3...8
    static let kleinbuchstaben = Array("abcdefghijklmnopqrstuvwxyz")
    static let grossbuchstaben = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let ziffernZeichen = Array("0123456789")
    static let sonderZeichen = Array("!#$%&*+-=?@_")

    static func erzeuge(_ regeln: PasswortRegeln) -> String {
        var zufall = SystemRandomNumberGenerator()
        return erzeuge(regeln, mit: &zufall)
    }

    static func erzeuge<G: RandomNumberGenerator>(_ regeln: PasswortRegeln, mit zufall: inout G) -> String {
        switch regeln.modus {
        case .zeichen: return zeichenPasswort(regeln, &zufall)
        case .wortgruppe: return wortgruppe(regeln, &zufall)
        }
    }

    private static func zeichenPasswort<G: RandomNumberGenerator>(_ regeln: PasswortRegeln, _ zufall: inout G) -> String {
        var klassen = [kleinbuchstaben, grossbuchstaben]
        if regeln.ziffern { klassen.append(ziffernZeichen) }
        if regeln.sonderzeichen { klassen.append(sonderZeichen) }
        let laenge = min(max(regeln.laenge, laengen.lowerBound), laengen.upperBound)
        // Von jeder eingeschalteten Klasse mindestens ein Zeichen, der Rest aus allen; dann mischen.
        var zeichen = klassen.compactMap { $0.randomElement(using: &zufall) }
        let alle = klassen.flatMap { $0 }
        while zeichen.count < laenge, let z = alle.randomElement(using: &zufall) { zeichen.append(z) }
        zeichen.shuffle(using: &zufall)
        return String(zeichen)
    }

    private static func wortgruppe<G: RandomNumberGenerator>(_ regeln: PasswortRegeln, _ zufall: inout G) -> String {
        let anzahl = min(max(regeln.woerter, wortAnzahl.lowerBound), wortAnzahl.upperBound)
        var teile: [String] = []
        for _ in 0..<anzahl {
            guard let wort = Wortliste.woerter.randomElement(using: &zufall) else { continue }
            teile.append(regeln.grossschreiben ? wort.prefix(1).uppercased() + String(wort.dropFirst()) : wort)
        }
        if regeln.mitZahl { teile.append(String(Int.random(in: 10...99, using: &zufall))) }
        return teile.joined(separator: regeln.trenner)
    }

    /// Grobe Stärke in Bit (Zeichenanzahl mal log2 des Alphabets, bei Wörtern Wortanzahl mal log2 der Liste); für die Anzeige.
    static func bits(_ regeln: PasswortRegeln) -> Int {
        switch regeln.modus {
        case .zeichen:
            let alphabet = 52 + (regeln.ziffern ? 10 : 0) + (regeln.sonderzeichen ? sonderZeichen.count : 0)
            let laenge = min(max(regeln.laenge, laengen.lowerBound), laengen.upperBound)
            return Int(Double(laenge) * log2(Double(alphabet)))
        case .wortgruppe:
            let anzahl = min(max(regeln.woerter, wortAnzahl.lowerBound), wortAnzahl.upperBound)
            let wortBits = Double(anzahl) * log2(Double(max(2, Wortliste.woerter.count)))
            return Int(wortBits + (regeln.mitZahl ? log2(90) : 0))
        }
    }
}
