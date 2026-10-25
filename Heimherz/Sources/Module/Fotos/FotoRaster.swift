import Foundation

enum FotoFilter: String, CaseIterable, Sendable, Identifiable {
    case alle, amPC, nochNicht
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .alle: return "Alle"
        case .amPC: return "Am PC"
        case .nochNicht: return "Noch nicht"
        }
    }
}

/// Wo ein Bild der Mediathek steht. Symbol und Text tragen die Aussage, nie die Farbe allein.
enum FotoStatus: Equatable, Sendable {
    case amPC, laeuft, wartet, fehler(String), offen

    var text: String {
        switch self {
        case .amPC: return "Am PC"
        case .laeuft: return "Wird gesendet"
        case .wartet: return "Wartet auf den Abgleich"
        case .fehler(let grund): return "Fehler: \(grund)"
        case .offen: return "Noch nicht am PC"
        }
    }

    var symbol: String {
        switch self {
        case .amPC: return "checkmark.circle.fill"
        case .laeuft: return "arrow.triangle.2.circlepath"
        case .wartet: return "clock.fill"
        case .fehler: return "exclamationmark.triangle.fill"
        case .offen: return "circle.dashed"
        }
    }
}

/// Reine Regeln für das Raster "Fotos sehen": Status je Bild, Filter, Vorlade-Fenster.
enum FotoRaster {
    /// Läuft ein Abgleich, wartet alles, was nicht fertig ist; sonst ist es einfach noch offen.
    static func status(kennung: String, anzeige: FotoAnzeige) -> FotoStatus {
        if anzeige.fertig.contains(kennung) { return .amPC }
        if anzeige.laufend.contains(kennung) { return .laeuft }
        if let grund = anzeige.fehler[kennung] { return .fehler(grund) }
        return anzeige.laeuft ? .wartet : .offen
    }

    /// Positionen der Bilder, die der Filter zeigt; Reihenfolge der Mediathek (neueste zuerst) bleibt.
    static func indizes(koepfe: [FotoKopf], filter: FotoFilter, anzeige: FotoAnzeige) -> [Int] {
        switch filter {
        case .alle: return Array(koepfe.indices)
        case .amPC: return koepfe.indices.filter { anzeige.fertig.contains(koepfe[$0].kennung) }
        case .nochNicht: return koepfe.indices.filter { !anzeige.fertig.contains(koepfe[$0].kennung) }
        }
    }

    /// Bereich um die sichtbare Stelle, für den PhotoKit Vorschauen vorbereitet.
    static func cacheFenster(mitte: Int, anzahl: Int, vor: Int = 40, nach: Int = 80) -> Range<Int> {
        guard anzahl > 0 else { return 0..<0 }
        let m = min(max(mitte, 0), anzahl - 1)
        return max(0, m - vor)..<min(anzahl, m + nach)
    }

    /// Was beim Wechsel des Fensters neu anzufangen und was zu beenden ist (nur die Ränder, der Rest bleibt im Cache).
    static func fensterwechsel(alt: Range<Int>?, neu: Range<Int>) -> (start: [Range<Int>], stopp: [Range<Int>]) {
        guard let alt else { return (neu.isEmpty ? [] : [neu], []) }
        return (differenz(neu, alt), differenz(alt, neu))
    }

    private static func differenz(_ a: Range<Int>, _ b: Range<Int>) -> [Range<Int>] {
        guard a.overlaps(b) else { return a.isEmpty ? [] : [a] }
        var r: [Range<Int>] = []
        if a.lowerBound < b.lowerBound { r.append(a.lowerBound..<b.lowerBound) }
        if b.upperBound < a.upperBound { r.append(b.upperBound..<a.upperBound) }
        return r
    }
}
