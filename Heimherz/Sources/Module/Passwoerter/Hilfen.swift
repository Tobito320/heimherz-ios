import Foundation
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers

/// Kopieren in die Zwischenablage: nur auf diesem Gerät (kein Universal Clipboard zu Mac oder iPad) und nach 60 Sekunden wieder weg (SPEC 9).
@MainActor
enum Zwischenablage {
    static let ablaufSekunden: TimeInterval = 60

    static func optionen(jetzt: Date = Date()) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: jetzt.addingTimeInterval(ablaufSekunden)]
    }

    static func kopiere(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: optionen())
    }
}

/// Gerätecode oder Face ID vor dem Anzeigen eines Passworts.
enum GeraeteAbfrage {
    /// true bei Erfolg oder wenn das Gerät gar keinen Code hat (dann gibt es nichts zu prüfen, wie bei der App-Sperre).
    @concurrent
    static func pruefe(grund: String) async -> Bool {
        let kontext = LAContext()
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return true }
        return (try? await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: grund)) ?? false
    }
}

/// Der Einmalcode zu einem Eintrag für die Anzeige: Code, Restsekunden, Länge der Periode.
struct TOTPZustand: Equatable {
    let code: String
    let rest: Int
    let periode: Int

    var anteil: Double { Double(rest) / Double(max(1, periode)) }

    /// Zur Lesbarkeit in der Mitte getrennt: `123 456`, `1234 5678`.
    var gruppiert: String {
        guard code.count >= 6, code.count % 2 == 0 else { return code }
        let mitte = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<mitte]) + " " + String(code[mitte...])
    }
}

enum TOTPAnzeige {
    /// nil ohne lesbares TOTP-Geheimnis.
    static func zustand(_ totp: String, datum: Date) -> TOTPZustand? {
        guard let e = TOTP.einstellung(aus: totp) else { return nil }
        let zeit = Int(datum.timeIntervalSince1970)
        return TOTPZustand(code: TOTP.code(e, zeit: zeit), rest: TOTP.restsekunden(e, zeit: zeit), periode: e.periode)
    }
}
