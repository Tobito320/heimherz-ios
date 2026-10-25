import Foundation

/// Wie lange ein Face ID reicht: so lange füllt AutoFill ohne neue Abfrage aus (Benutzer, Passwort und Code hintereinander) und die App sperrt nicht.
enum EntsperrDauer: Int, CaseIterable, Identifiable, Sendable {
    case aus = 0
    case eineMinute = 60
    case fuenfMinuten = 300
    case viertelStunde = 900
    case stunde = 3600

    var id: Int { rawValue }
    var sekunden: TimeInterval { TimeInterval(rawValue) }

    var titel: String {
        switch self {
        case .aus: return "Jedes Mal"
        case .eineMinute: return "1 Minute"
        case .fuenfMinuten: return "5 Minuten"
        case .viertelStunde: return "15 Minuten"
        case .stunde: return "1 Stunde"
        }
    }
}

/// Einstellungen, die App und Erweiterungen teilen (UserDefaults der App Group). Nur Schalter und Zahlen, nie Geheimnisse.
/// Die Einstellungen-Ansicht schreibt, App und AutoFill lesen bei jedem Aufruf neu.
struct GeteilteEinstellungen {
    let speicher: UserDefaults

    init(speicher: UserDefaults? = UserDefaults(suiteName: Kennungen.appGruppe)) {
        self.speicher = speicher ?? .standard
    }

    private enum Schluessel {
        static let entsperrDauer = "einstellung.entsperrDauer"
        static let codeKopieren = "einstellung.codeKopieren"
        static let leckPruefung = "einstellung.leckPruefung"
        static let fotoMitteilung = "einstellung.fotoMitteilung"
    }

    /// Standard 5 Minuten (wie die bisherige App-Sperre).
    var entsperrDauer: EntsperrDauer {
        get { speicher.object(forKey: Schluessel.entsperrDauer).flatMap { ($0 as? Int).flatMap(EntsperrDauer.init) } ?? .fuenfMinuten }
        nonmutating set { speicher.set(newValue.rawValue, forKey: Schluessel.entsperrDauer) }
    }

    /// Nach dem Ausfüllen eines Passworts den 2FA-Code des Kontos in die Zwischenablage legen (lokal, läuft nach 60 s ab). Standard an.
    var codeKopieren: Bool {
        get { speicher.object(forKey: Schluessel.codeKopieren) as? Bool ?? true }
        nonmutating set { speicher.set(newValue, forKey: Schluessel.codeKopieren) }
    }

    /// Sicherheit: Passwörter gegen bekannte Datenlecks prüfen (Have I Been Pwned, k-Anonymität: nur die ersten 5 Zeichen des SHA-1 gehen raus). Standard an.
    var leckPruefung: Bool {
        get { speicher.object(forKey: Schluessel.leckPruefung) as? Bool ?? true }
        nonmutating set { speicher.set(newValue, forKey: Schluessel.leckPruefung) }
    }

    /// Mitteilung, wenn ein Foto-Abgleich fertig ist oder nachts etwas gesichert hat. Standard an.
    var fotoMitteilung: Bool {
        get { speicher.object(forKey: Schluessel.fotoMitteilung) as? Bool ?? true }
        nonmutating set { speicher.set(newValue, forKey: Schluessel.fotoMitteilung) }
    }
}
