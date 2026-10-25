import Foundation
import UIKit

/// Holt Vorschaubilder vom PC (`GET /v1/dateien/vorschau`) und hält sie im Speicher (Neustart oder Leeren der Dateien-Zwischenspeicher löscht sie, der PC hat sie ohnehin fertig).
/// Wie `SymbolLader`: nur sichtbare Zellen fragen an (`.task` pro Zelle), höchstens `parallel` gleichzeitig, bis dahin zeigt die Zelle das graue Dateisymbol.
@MainActor
final class VorschauLader {
    typealias Holen = @Sendable (_ pfad: String, _ px: Int) async throws -> Data?

    private let cache = NSCache<NSString, UIImage>()
    private let holen: Holen?
    /// Was der PC nicht kann (404, kein Bild): in dieser Sitzung nicht noch einmal fragen.
    private var keine = Set<String>()
    private var laufend = 0
    private var wartende: [CheckedContinuation<Void, Never>] = []
    let parallel: Int

    init(holen: Holen? = nil, parallel: Int = 4) {
        self.holen = holen
        self.parallel = parallel
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func bild(schluessel: String) -> UIImage? { cache.object(forKey: schluessel as NSString) }

    func lade(pfad: String, schluessel: String, px: Int) async -> UIImage? {
        if let b = bild(schluessel: schluessel) { return b }
        guard let holen, !keine.contains(schluessel) else { return nil }
        await platz()
        defer { freigeben() }
        if Task.isCancelled { return nil }
        if let b = bild(schluessel: schluessel) { return b } // inzwischen von einer anderen Zelle geholt
        do {
            guard let daten = try await holen(pfad, px), let b = UIImage(data: daten) else {
                keine.insert(schluessel)
                return nil
            }
            cache.setObject(b, forKey: schluessel as NSString, cost: Int(b.size.width * b.size.height * b.scale * b.scale * 4))
            return b
        } catch {
            return nil // Netz weg oder Zelle verschwunden: beim nächsten Erscheinen wieder versuchen, ohne es zu merken
        }
    }

    private func platz() async {
        if laufend < parallel {
            laufend += 1
            return
        }
        await withCheckedContinuation { wartende.append($0) }
    }

    private func freigeben() {
        if wartende.isEmpty { laufend -= 1 } else { wartende.removeFirst().resume() }
    }

    /// Wie die Anfragen laufen: Demo mit erfundenen Bildern, gekoppelt zum PC, sonst nil (die Zellen bleiben bei den Symbolen).
    static func holenFuer(_ umgebung: AppUmgebung) -> Holen? {
        if umgebung.istDemo { return { pfad, px in Self.demoBild(pfad: pfad, px: px) } }
        guard umgebung.istGekoppelt else { return nil }
        let sitzung = umgebung.sitzung
        let bund = umgebung.bund
        return { pfad, px in try await HeimClient.aus(bund, sitzung: sitzung).dateiVorschau(pfad: pfad, px: px) }
    }

    /// Nur Demo (Screenshots): erfundene Bilder, ein Farbverlauf je Name, bei PDFs eine weiße Seite mit Zeilen.
    nonisolated static func demoBild(pfad: String, px: Int) -> Data? {
        let farbe = Double(pfad.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) % 360 }) / 360
        let istPDF = pfad.lowercased().hasSuffix(".pdf")
        let groesse = istPDF ? CGSize(width: px * 3 / 4, height: px) : CGSize(width: px, height: px * 3 / 4)
        return UIGraphicsImageRenderer(size: groesse).jpegData(withCompressionQuality: 0.7) { ctx in
            let cg = ctx.cgContext
            if istPDF {
                UIColor.white.setFill()
                cg.fill(CGRect(origin: .zero, size: groesse))
                UIColor(white: 0.8, alpha: 1).setFill()
                var y = groesse.height * 0.14
                while y < groesse.height * 0.85 {
                    cg.fill(CGRect(x: groesse.width * 0.12, y: y, width: groesse.width * (y.truncatingRemainder(dividingBy: 3) < 1.5 ? 0.76 : 0.5), height: 3))
                    y += groesse.height * 0.07
                }
            } else {
                let farben = [UIColor(hue: farbe, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor,
                              UIColor(hue: (farbe + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.65, alpha: 1).cgColor]
                if let verlauf = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: farben as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(verlauf, start: .zero, end: CGPoint(x: groesse.width, y: groesse.height), options: [])
                }
            }
        }
    }
}
