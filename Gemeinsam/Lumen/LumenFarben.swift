// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI
import UIKit

/// Ein Farb-Token: Hex hell, dunkel und (optional) mit erhöhtem Kontrast. Rein, damit der Kontrast-Test ohne UIKit rechnet.
struct FarbToken: Sendable, Hashable {
    let name: String
    let hell: UInt32
    let dunkel: UInt32
    let hellHoch: UInt32?
    let dunkelHoch: UInt32?

    init(_ name: String, _ hell: UInt32, _ dunkel: UInt32, hellHoch: UInt32? = nil, dunkelHoch: UInt32? = nil) {
        self.name = name
        self.hell = hell
        self.dunkel = dunkel
        self.hellHoch = hellHoch
        self.dunkelHoch = dunkelHoch
    }

    func hex(dunkelModus: Bool, hoch: Bool) -> UInt32 {
        if dunkelModus { return hoch ? (dunkelHoch ?? dunkel) : dunkel }
        return hoch ? (hellHoch ?? hell) : hell
    }
}

/// Alle Farben der Lumen-Familie (Revolut-Stil, Skill revolut-stil): flaches Grau/Schwarz, Blau als Akzent. App-eigene Farben in einer eigenen Datei als `extension Palette` und `extension Color`. Kontraste nachgerechnet,
/// `FarbenKontrastTests` prüft sie hart (Text 4,5:1, Linien und Knopfflächen 3:1, hell und dunkel).
enum Palette {
    static let grund = FarbToken("grund", 0xF7F7F7, 0x000000)
    static let grundWarm = FarbToken("grundWarm", 0xEFEFF1, 0x0A0A0B)
    static let karte = FarbToken("karte", 0xFFFFFF, 0x161618)
    static let karteZart = FarbToken("karteZart", 0xF2F2F4, 0x1E1E20)
    static let chip = FarbToken("chip", 0xEAEAEC, 0x2A2A2D)
    static let tinte = FarbToken("tinte", 0x191C1F, 0xFFFFFF)
    static let tinte2 = FarbToken("tinte2", 0x565B62, 0xB0B3B8, hellHoch: 0x3D4248, dunkelHoch: 0xD0D2D6)
    static let tinte3 = FarbToken("tinte3", 0x5F656D, 0xA0A3A8, hellHoch: 0x3D4248, dunkelHoch: 0xD0D2D6)
    /// Blau für Links, Symbole und Hervorhebung auf Karten und Grund.
    static let akzent = FarbToken("akzent", 0x0058D6, 0x6EA8FF, hellHoch: 0x0046AD, dunkelHoch: 0x9CC3FF)
    /// Fläche des Hauptknopfs; Text darauf ist `aufKnopf`.
    static let knopf = FarbToken("knopf", 0x0A62E8, 0x3D8BFF)
    static let aufKnopf = FarbToken("aufKnopf", 0xFFFFFF, 0x000000)
    static let linie = FarbToken("linie", 0x7A8088, 0x6B6E73, hellHoch: 0x565B62, dunkelHoch: 0xA0A3A8)
    static let haar = FarbToken("haar", 0xE0E0E3, 0x2A2A2D)
    static let ok = FarbToken("ok", 0x066B4B, 0x2BD99A)
    static let okGrund = FarbToken("okGrund", 0xDDF5E8, 0x0F2A22)
    static let warn = FarbToken("warn", 0x8F4B00, 0xFFB84D)
    static let warnGrund = FarbToken("warnGrund", 0xFFEACB, 0x3A2A0A)
    static let schlecht = FarbToken("schlecht", 0xC4122F, 0xFF6B7A)
    static let schlechtGrund = FarbToken("schlechtGrund", 0xFFDADF, 0x3F1118)

    static let alle: [FarbToken] = [
        grund, grundWarm, karte, karteZart, chip, tinte, tinte2, tinte3, akzent, knopf, aufKnopf, linie, haar,
        ok, okGrund, warn, warnGrund, schlecht, schlechtGrund
    ]
}

extension Color {
    static func token(_ token: FarbToken) -> Color {
        Color(UIColor { traits in
            let hex = token.hex(dunkelModus: traits.userInterfaceStyle == .dark, hoch: traits.accessibilityContrast == .high)
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let grund = token(Palette.grund)
    static let grundWarm = token(Palette.grundWarm)
    static let karte = token(Palette.karte)
    static let karteZart = token(Palette.karteZart)
    static let chip = token(Palette.chip)
    static let tinte = token(Palette.tinte)
    static let tinte2 = token(Palette.tinte2)
    static let tinte3 = token(Palette.tinte3)
    static let akzent = token(Palette.akzent)
    static let knopf = token(Palette.knopf)
    static let aufKnopf = token(Palette.aufKnopf)
    static let linie = token(Palette.linie)
    static let haar = token(Palette.haar)
    static let ok = token(Palette.ok)
    static let okGrund = token(Palette.okGrund)
    static let warn = token(Palette.warn)
    static let warnGrund = token(Palette.warnGrund)
    static let schlecht = token(Palette.schlecht)
    static let schlechtGrund = token(Palette.schlechtGrund)
}
