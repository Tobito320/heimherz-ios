import SwiftUI

/// Ein Raster für alle Karten und Zeilen (4 pt).
enum Abstand {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16      // Seitenrand und Karteninnenrand
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Mindestgröße jeder Tippfläche.
    static let tippflaeche: CGFloat = 44
}

enum Rundung {
    static let klein: CGFloat = 12
    static let karte: CGFloat = 24
}

extension Shape where Self == RoundedRectangle {
    /// Die eine Kartenform der App: `.background(Color.karte, in: .heimherzKarte)`.
    static var heimherzKarte: RoundedRectangle { RoundedRectangle(cornerRadius: Rundung.karte, style: .continuous) }
    static var heimherzFeld: RoundedRectangle { RoundedRectangle(cornerRadius: Rundung.klein, style: .continuous) }
}
