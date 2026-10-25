import Foundation
import Photos
import Synchronization

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

/// Setzt eine Fortsetzung genau einmal fort: wer zuerst kommt (Abschluss von PhotoKit oder Abbruch), gewinnt.
final class EinmalFortsetzung<T: Sendable>: Sendable {
    private let box = Mutex<CheckedContinuation<T, any Error>?>(nil)

    func setze(_ c: CheckedContinuation<T, any Error>) { box.withLock { $0 = c } }
    func liefere(_ wert: T) { nimm()?.resume(returning: wert) }
    func wirf(_ fehler: any Error) { nimm()?.resume(throwing: fehler) }

    private func nimm() -> CheckedContinuation<T, any Error>? {
        box.withLock { b in
            let c = b
            b = nil
            return c
        }
    }
}

/// Liest die Mediathek. Ändert und löscht nie etwas.
struct FotoQuelleLive: FotoQuelle {
    /// Unter dieser Grenze freien Speichers wird nichts mehr exportiert.
    static let mindestFrei: Int64 = 1_000_000_000

    @concurrent
    func plane(stand: FotoStand, hoechstens: Int, nur: [String]?, uebersprungen: Set<String>) async -> FotoPlan.Ergebnis {
        let treffer = nur.map { PHAsset.fetchAssets(withLocalIdentifiers: $0, options: nil) } ?? FotoBibliothek.abfrage()
        var koepfe: [FotoKopf] = []
        var stelle: [String: Int] = [:]
        koepfe.reserveCapacity(treffer.count)
        treffer.enumerateObjects { asset, i, _ in
            let k = FotoRegeln.kopf(assetId: asset.localIdentifier)
            koepfe.append(k)
            stelle[k.kennung] = i
        }
        return FotoPlan.plane(koepfe: koepfe, stand: stand, uebersprungen: uebersprungen, hoechstens: hoechstens, zaehleAlles: true) { kopf in
            guard let i = stelle[kopf.kennung] else { return [] }
            return FotoBibliothek.ressourcen(treffer.object(at: i)).map(\.ressource)
        }
    }

    /// Schreibt die Datei Stück für Stück in eine Temp-Datei (`requestData`, anders als `writeData` mit Abbruch).
    @concurrent
    func exportiere(_ r: FotoRessource, iCloud: Bool) async throws -> URL {
        let frei = (try? FotoTemp.ordner.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        if let frei, frei < Self.mindestFrei { throw FotoFehler.speicherKnapp }
        try Task.checkCancellation()
        let treffer = PHAsset.fetchAssets(withLocalIdentifiers: [r.assetId], options: nil)
        guard let asset = treffer.firstObject,
              let objekt = FotoBibliothek.ressourcen(asset).first(where: { $0.ressource.name == r.name })?.objekt else { throw FotoFehler.nichtGefunden }
        let ziel = FotoTemp.ordner.appending(path: "\(UUID().uuidString)-\(r.name)")
        guard FileManager.default.createFile(atPath: ziel.path, contents: nil) else { throw FotoFehler.speicherKnapp }
        let optionen = PHAssetResourceRequestOptions()
        optionen.isNetworkAccessAllowed = iCloud
        do {
            let datei = try FileHandle(forWritingTo: ziel)
            defer { try? datei.close() }
            try await Self.schreibe(objekt, in: datei, optionen: optionen)
        } catch {
            try? FileManager.default.removeItem(at: ziel)
            if Task.isCancelled { throw CancellationError() }
            // Ist das Laden aus iCloud aus, heißt jeder Fehler hier: das Original liegt nicht auf dem Handy.
            throw iCloud ? error : FotoFehler.nurInICloud
        }
        return ziel
    }

    private static func schreibe(_ objekt: PHAssetResource, in datei: FileHandle, optionen: PHAssetResourceRequestOptions) async throws {
        let manager = PHAssetResourceManager.default()
        let fortsetzung = EinmalFortsetzung<Void>()
        let anfrage = Mutex<PHAssetResourceDataRequestID?>(nil)
        let zu = Mutex(false)
        let schreibFehler = Mutex<(any Error)?>(nil)
        defer { zu.withLock { $0 = true } }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                fortsetzung.setze(c)
                let id = manager.requestData(for: objekt, options: optionen, dataReceivedHandler: { daten in
                    guard !zu.withLock({ $0 }) else { return }
                    do { try datei.write(contentsOf: daten) } catch { schreibFehler.withLock { $0 = error } }
                }, completionHandler: { fehler in
                    let grund = schreibFehler.withLock { $0 } ?? fehler
                    if let grund { fortsetzung.wirf(grund) } else { fortsetzung.liefere(Void()) }
                })
                anfrage.withLock { $0 = id }
                if Task.isCancelled {
                    manager.cancelDataRequest(id)
                    fortsetzung.wirf(CancellationError())
                }
            }
        } onCancel: {
            if let id = anfrage.withLock({ $0 }) { manager.cancelDataRequest(id) }
            fortsetzung.wirf(CancellationError())
        }
    }
}
