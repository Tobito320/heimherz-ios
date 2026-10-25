import Foundation
import Observation
import Photos
import Synchronization
import UIKit

/// Die Mediathek für das Raster: alle Assets neueste zuerst (`PHFetchResult` lädt Objekte erst beim Zugriff, 8000+ sind billig)
/// und dazu die Kennungen, einmal abseits des Hauptthreads gebildet. Im Demo-Modus erfundene Bilder ohne PhotoKit.
@MainActor @Observable
final class FotoMediathek {
    struct Gelesen: @unchecked Sendable {   // shortcut: PHFetchResult ist unveränderlich und wird danach nur auf dem MainActor gelesen
        let treffer: PHFetchResult<PHAsset>
        let koepfe: [FotoKopf]
    }

    static let demoKoepfe: [FotoKopf] = (0..<600).map { FotoRegeln.kopf(assetId: "demo-\($0)") }

    private(set) var koepfe: [FotoKopf] = []
    private(set) var geladen = false
    private var treffer: PHFetchResult<PHAsset>?
    let istDemo: Bool

    init(istDemo: Bool) { self.istDemo = istDemo }

    func lade() async {
        if istDemo {
            koepfe = Self.demoKoepfe
        } else {
            let g = await MediathekLeser.lese()
            treffer = g.treffer
            koepfe = g.koepfe
            VorschauLader.geteilt.vergisstAlles()
        }
        geladen = true
    }

    func asset(at i: Int) -> PHAsset? {
        guard let treffer, i >= 0, i < treffer.count else { return nil }
        return treffer.object(at: i)
    }

    func assets(in bereich: Range<Int>) -> [PHAsset] {
        guard let treffer else { return [] }
        let gueltig = bereich.clamped(to: 0..<treffer.count)
        return treffer.objects(at: IndexSet(integersIn: gueltig))
    }
}

enum MediathekLeser {
    @concurrent
    static func lese() async -> FotoMediathek.Gelesen {
        let treffer = FotoBibliothek.abfrage()
        var koepfe: [FotoKopf] = []
        koepfe.reserveCapacity(treffer.count)
        treffer.enumerateObjects { asset, _, _ in koepfe.append(FotoRegeln.kopf(assetId: asset.localIdentifier)) }
        return FotoMediathek.Gelesen(treffer: treffer, koepfe: koepfe)
    }
}

/// Vorschaubilder über einen `PHCachingImageManager`: kleine Bilder, nie aus iCloud nachladen (das tut nur der Abgleich), Cache nur um die sichtbare Stelle.
@MainActor
final class VorschauLader {
    static let geteilt = VorschauLader()
    static let kante: CGFloat = 300

    private let manager = PHCachingImageManager()
    private let optionen: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false
        return o
    }()
    private var fenster: Range<Int>?
    private let ziel = CGSize(width: VorschauLader.kante, height: VorschauLader.kante)

    func bild(_ asset: PHAsset) async -> UIImage? {
        let anfrage = Mutex<PHImageRequestID?>(nil)
        let manager = manager
        let optionen = optionen
        let ziel = ziel
        return try? await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<UIImage?, any Error>) in
                let einmal = EinmalFortsetzung<UIImage?>()
                einmal.setze(c)
                let id = manager.requestImage(for: asset, targetSize: ziel, contentMode: .aspectFill, options: optionen) { bild, _ in
                    einmal.liefere(bild)
                }
                anfrage.withLock { $0 = id }
            }
        } onCancel: {
            if let id = anfrage.withLock({ $0 }) { manager.cancelImageRequest(id) }
        }
    }

    /// Das große Bild für die Einzelansicht; darf das Original aus iCloud holen.
    func gross(_ asset: PHAsset) async -> UIImage? {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = true
        let manager = PHImageManager.default()
        return try? await withCheckedThrowingContinuation { (c: CheckedContinuation<UIImage?, any Error>) in
            let einmal = EinmalFortsetzung<UIImage?>()
            einmal.setze(c)
            manager.requestImage(for: asset, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFit, options: o) { bild, _ in
                einmal.liefere(bild)
            }
        }
    }

    /// Ein Bild an Position `mitte` ist sichtbar: Vorschauen für die Nachbarschaft vorbereiten, den fernen Rest freigeben.
    func sichtbar(mitte: Int, mediathek: FotoMediathek) {
        guard !mediathek.istDemo else { return }
        let neu = FotoRaster.cacheFenster(mitte: mitte, anzahl: mediathek.koepfe.count)
        if let alt = fenster, abs(alt.lowerBound - neu.lowerBound) < 20 { return }   // erst bei größerer Bewegung umstellen
        let (start, stopp) = FotoRaster.fensterwechsel(alt: fenster, neu: neu)
        for r in stopp { manager.stopCachingImages(for: mediathek.assets(in: r), targetSize: ziel, contentMode: .aspectFill, options: optionen) }
        for r in start { manager.startCachingImages(for: mediathek.assets(in: r), targetSize: ziel, contentMode: .aspectFill, options: optionen) }
        fenster = neu
    }

    func vergisstAlles() {
        manager.stopCachingImagesForAllAssets()
        fenster = nil
    }
}
