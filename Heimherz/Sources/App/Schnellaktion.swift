import Foundation
import Observation

/// Die Schnellaktionen am App-Symbol (langes Drücken). Die Typen stehen auch in `project.yml` (`UIApplicationShortcutItems`);
/// `SchnellaktionTests` hält beide Listen gleich.
enum Schnellaktion: String, CaseIterable, Sendable {
    case codes = "com.onlyus.heimherz.aktion.codes"
    case fotosSichern = "com.onlyus.heimherz.aktion.fotos"
    case neuesPasswort = "com.onlyus.heimherz.aktion.passwort"

    init?(typ: String) { self.init(rawValue: typ) }

    #if DEBUG
    /// Nur Screenshots in CI: `-heimherzAktion codes|fotos|passwort`.
    static func demo(_ name: String) -> Schnellaktion? {
        switch name {
        case "codes": return .codes
        case "fotos": return .fotosSichern
        case "passwort": return .neuesPasswort
        default: return nil
        }
    }
    #endif

    /// In welchen Tab die Aktion führt.
    var tab: HeimherzTab {
        switch self {
        case .codes, .neuesPasswort: return .passwoerter
        case .fotosSichern: return .fotos
        }
    }
}

/// Kleines geteiltes Postfach wie `ImportPostfach`: Szene und App-Delegate legen die Aktion ab, die Ansicht des Ziels nimmt sie,
/// sobald sie darf (nicht gesperrt, Tresor offen). Es hält höchstens eine Aktion; eine neue ersetzt die alte. Wer sie nimmt, räumt sie weg.
@MainActor @Observable
final class SchnellaktionPostfach {
    static let geteilt = SchnellaktionPostfach()

    private(set) var offen: Schnellaktion?

    init() {}

    func lege(_ aktion: Schnellaktion) { offen = aktion }

    /// true und weg aus dem Postfach, wenn genau diese Aktion wartet.
    func nimm(_ aktion: Schnellaktion) -> Bool {
        guard offen == aktion else { return false }
        offen = nil
        return true
    }

    /// Wirft die wartende Aktion weg, wenn sie in diesen Tab führt (z. B. nicht gekoppelt: es gibt nichts auszuführen).
    func verwirf(tab: HeimherzTab) {
        if offen?.tab == tab { offen = nil }
    }
}
