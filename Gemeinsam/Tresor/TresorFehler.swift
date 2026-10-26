import Foundation

/// Fehler beim Lesen, Öffnen und Verschließen des Tresors. `nutzerText` ist für die Oberfläche gedacht (Deutsch, ohne Fachwort).
enum TresorFehler: Error, Equatable, LocalizedError {
    /// Der Tresorschlüssel hat nicht 32 Byte.
    case schluesselLaenge
    /// Der Umschlag hat nicht die Form aus SPEC 5 (v 1, nonce 12 Byte, daten mindestens 16 Byte).
    case umschlagUngueltig
    /// Falscher Schlüssel oder beschädigte Daten (GCM-Prüfung schlägt fehl).
    case entschluesselungFehlgeschlagen
    /// Der entschlüsselte Inhalt ist kein gültiger Tresor.
    case inhaltUngueltig
    /// Ein neueres Tresor-Format als diese App-Version kennt. Nie überschreiben.
    case formatUnbekannt(Int)

    var nutzerText: String {
        switch self {
        case .schluesselLaenge: return "Der Tresorschlüssel ist ungültig. Bitte das Handy neu koppeln."
        case .umschlagUngueltig: return "Die Tresordaten haben ein unbekanntes Format."
        case .entschluesselungFehlgeschlagen: return "Der Tresor lässt sich mit diesem Schlüssel nicht öffnen. Bitte das Handy neu koppeln."
        case .inhaltUngueltig: return "Der Tresor ist beschädigt."
        case .formatUnbekannt: return "Der Tresor stammt aus einer neueren Version. Bitte Lumen aktualisieren."
        }
    }

    var errorDescription: String? { nutzerText }
}
