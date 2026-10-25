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

/// Alle Farben der App, eigenes Thema "warmes Grün" (Wiese, Heimat) mit Korallrot für das Herz. Die Kontraste sind nachgerechnet,
/// `FarbenKontrastTests` prüft sie hart (Text 4,5:1, Linien und Knopfflächen 3:1, hell und dunkel).
enum Palette {
    static let grund = FarbToken("grund", 0xF3F8EC, 0x10170F)
    static let grundWarm = FarbToken("grundWarm", 0xE4EFD6, 0x1A2518)
    static let karte = FarbToken("karte", 0xFFFFFF, 0x1C281A)
    static let karteZart = FarbToken("karteZart", 0xF8FBF3, 0x243322)
    static let chip = FarbToken("chip", 0xDCEACB, 0x2C3E28)
    static let tinte = FarbToken("tinte", 0x15281A, 0xF0F7E8)
    static let tinte2 = FarbToken("tinte2", 0x3F5A3A, 0xC3D7B8, hellHoch: 0x2B4528, dunkelHoch: 0xE2EED9)
    static let tinte3 = FarbToken("tinte3", 0x52694B, 0xA8BF9B, hellHoch: 0x2B4528, dunkelHoch: 0xE2EED9)
    /// Grün für Text und Symbole auf Karten und Grund.
    static let gruen = FarbToken("gruen", 0x2A6B33, 0x86D98F, hellHoch: 0x1F5427, dunkelHoch: 0xA8EBB0)
    /// Fläche des Hauptknopfs; Text darauf ist `aufKnopf`.
    static let knopf = FarbToken("knopf", 0x2A6B33, 0x86D98F)
    static let aufKnopf = FarbToken("aufKnopf", 0xFFFFFF, 0x0B2410)
    /// Das Herz (Korall).
    static let herz = FarbToken("herz", 0xB93A2B, 0xFF9D8D, hellHoch: 0x9A2A1D, dunkelHoch: 0xFFB4A8)
    static let linie = FarbToken("linie", 0x6E8A64, 0x7A9570, hellHoch: 0x4F6B46, dunkelHoch: 0xA3BC98)
    static let haar = FarbToken("haar", 0xD3E3C2, 0x2C3E28)
    static let ok = FarbToken("ok", 0x1B6A3C, 0x7BDDA0)
    static let okGrund = FarbToken("okGrund", 0xDDF3E3, 0x183824)
    static let warn = FarbToken("warn", 0x8A4B00, 0xFFC470)
    static let warnGrund = FarbToken("warnGrund", 0xFFEBC9, 0x43300F)
    static let schlecht = FarbToken("schlecht", 0xB3202F, 0xFF8A94)
    static let schlechtGrund = FarbToken("schlechtGrund", 0xFFDADF, 0x4A1D24)
    // Hero-Verlauf (genau einmal je Bildschirm): Stopps, auf denen tinte und tinte2 nachgerechnet lesbar sind.
    static let heroEins = FarbToken("heroEins", 0xD3EAC1, 0x22391F)
    static let heroZwei = FarbToken("heroZwei", 0xEAF3C6, 0x2C381C)
    static let heroDrei = FarbToken("heroDrei", 0xCDEBDC, 0x1C3A2E)

    static let alle: [FarbToken] = [
        grund, grundWarm, karte, karteZart, chip, tinte, tinte2, tinte3, gruen, knopf, aufKnopf, herz, linie, haar,
        ok, okGrund, warn, warnGrund, schlecht, schlechtGrund, heroEins, heroZwei, heroDrei
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
    static let gruen = token(Palette.gruen)
    static let knopf = token(Palette.knopf)
    static let aufKnopf = token(Palette.aufKnopf)
    static let herz = token(Palette.herz)
    static let linie = token(Palette.linie)
    static let haar = token(Palette.haar)
    static let ok = token(Palette.ok)
    static let okGrund = token(Palette.okGrund)
    static let warn = token(Palette.warn)
    static let warnGrund = token(Palette.warnGrund)
    static let schlecht = token(Palette.schlecht)
    static let schlechtGrund = token(Palette.schlechtGrund)
    static let heroEins = token(Palette.heroEins)
    static let heroZwei = token(Palette.heroZwei)
    static let heroDrei = token(Palette.heroDrei)
}
