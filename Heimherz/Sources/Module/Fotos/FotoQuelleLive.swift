import Foundation
import Photos

/// Temp-Dateien der Exporte. Liegen außerhalb von `tmp/`, weil der Hintergrund-Upload sie noch lesen muss, wenn die App längst schläft.
enum FotoTemp {
    static var ordner: URL {
        var u = URL.applicationSupportDirectory.appending(path: "Heimherz/FotosUpload", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var werte = URLResourceValues()
        werte.isExcludedFromBackup = true
        try? u.setResourceValues(werte)
        return u
    }

    /// Löscht Reste früherer Läufe, die kein laufender Upload mehr braucht.
    static func raeumeAuf(behalte: Set<String>) {
        let fm = FileManager.default
        for datei in (try? fm.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? [] where !behalte.contains(datei.path) {
            try? fm.removeItem(at: datei)
        }
    }
}

/// Liest die Mediathek. Ändert und löscht nie etwas.
struct FotoQuelleLive: FotoQuelle {
    /// Unter dieser Grenze freien Speichers wird nichts mehr exportiert.
    static let mindestFrei: Int64 = 1_000_000_000

    @concurrent
    func plane(stand: FotoStand) async -> FotoPlan.Ergebnis {
        let treffer = FotoBibliothek.abfrage()
        var koepfe: [FotoKopf] = []
        var stelle: [String: Int] = [:]
        koepfe.reserveCapacity(treffer.count)
        treffer.enumerateObjects { asset, i, _ in
            let k = FotoRegeln.kopf(assetId: asset.localIdentifier)
            koepfe.append(k)
            stelle[k.kennung] = i
        }
        return FotoPlan.plane(koepfe: koepfe, stand: stand) { kopf in
            guard let i = stelle[kopf.kennung] else { return [] }
            return FotoBibliothek.ressourcen(treffer.object(at: i)).map(\.ressource)
        }
    }

    @concurrent
    func exportiere(_ r: FotoRessource, fortschritt: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let frei = (try? FotoTemp.ordner.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        if let frei, frei < Self.mindestFrei { throw FotoFehler.speicherKnapp }
        let treffer = PHAsset.fetchAssets(withLocalIdentifiers: [r.assetId], options: nil)
        guard let asset = treffer.firstObject,
              let objekt = FotoBibliothek.ressourcen(asset).first(where: { $0.ressource.name == r.name })?.objekt else { throw FotoFehler.nichtGefunden }
        let ziel = FotoTemp.ordner.appending(path: "\(UUID().uuidString)-\(r.name)")
        let optionen = PHAssetResourceRequestOptions()
        optionen.isNetworkAccessAllowed = true
        optionen.progressHandler = { fortschritt($0) }
        do {
            try await PHAssetResourceManager.default().writeData(for: objekt, toFile: ziel, options: optionen)
        } catch {
            try? FileManager.default.removeItem(at: ziel)
            throw error
        }
        return ziel
    }
}
