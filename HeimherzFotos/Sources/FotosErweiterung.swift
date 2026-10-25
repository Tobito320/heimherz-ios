import ExtensionFoundation
import Foundation
import Photos
import Synchronization

/// Foto-Upload im Hintergrund (SPEC 11). iOS ruft `process()`, wenn es passt (Netz, Strom, Ruhe); die Erweiterung legt Upload-Jobs an,
/// die iOS selbst ausführt (auch bei gesperrtem Handy), quittiert fertige und versucht fehlgeschlagene noch einmal.
/// iOS 26.1 kennt nur dieses synchrone Protokoll; `PHBackgroundResourceUploadJobExtension` (async) gibt es erst mit iOS 27.
/// Quelle: developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background und die Seiten zu
/// `PHBackgroundResourceUploadExtension`, `PHAssetResourceUploadJob`, `PHAssetResourceUploadJobChangeRequest`.
/// Kein Netz in der Erweiterung: was schon am PC liegt, steht im `FotoStand` der App Group (die App schreibt ihn bei jedem Abgleich).
@main
final class FotosErweiterung: PHBackgroundResourceUploadExtension {
    private let beendet = Mutex(false)

    required init() {}

    func process() -> PHBackgroundResourceUploadProcessingResult {
        beendet.withLock { $0 = false }
        guard let ablage = FotoStandAblage.appGruppe() else { return .failure }
        let ergebnis = Self.arbeite(ablage: ablage, beendet: { self.beendet.withLock { $0 } })
        return ergebnis
    }

    func notifyTermination() {
        beendet.withLock { $0 = true }
    }

    // MARK: Ablauf

    /// Erst fertige quittieren und Fehlgeschlagene wiederholen, dann neue Jobs bis zum Limit anlegen.
    private static func arbeite(ablage: FotoStandAblage, beendet: () -> Bool) -> PHBackgroundResourceUploadProcessingResult {
        guard let geraet = try? Schluesselbund.live.ladeGeraet() else { return .completed } // nicht gekoppelt: nichts zu tun
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            ablage.aendere { $0.fehler = "Die Foto-Erweiterung braucht den Zugriff auf alle Fotos." }
            return .completed
        }
        // Apple prüft jede Anfrage gegen `BackgroundUploadURLBase` im Info.plist. Weicht das Ziel des Koppelns ab, würde es still scheitern.
        guard let basisText = Bundle.main.object(forInfoDictionaryKey: "BackgroundUploadURLBase") as? String,
              let basis = URL(string: basisText), basis.host != nil, basis.host == geraet.url.host, basis.scheme == geraet.url.scheme else {
            ablage.aendere { $0.fehler = "Die Adresse des PCs passt nicht zu dieser Version der App. Hochladen im Hintergrund ist aus." }
            return .completed
        }
        let client = HeimClient(basis: basis, token: geraet.token)
        let bib = PHPhotoLibrary.shared()

        do {
            try wiederhole(bib, ablage: ablage)
            try quittiere(bib, ablage: ablage)
            if beendet() { return .processing }
            let angelegt = try legeJobsAn(bib, client: client, ablage: ablage, beendet: beendet)
            // Limit erreicht oder noch mehr offen: iOS soll wiederkommen, sobald Jobs fertig sind.
            return angelegt.limit || angelegt.nochMehr ? .processing : .completed
        } catch {
            ablage.aendere { $0.fehler = "Hintergrund-Upload: \(error.localizedDescription)" }
            return .failure
        }
    }

    /// `PHAssetResourceUploadJob.error` gibt es erst ab iOS 26.4 (laut Compiler, die Doku nennt es nicht); davor wird immer wiederholt.
    private static func fehlerCode(_ job: PHAssetResourceUploadJob) -> URLError.Code? {
        if #available(iOS 26.4, *) { return (job.error as? URLError)?.code }
        return nil
    }

    /// Fehlgeschlagene Jobs noch einmal; dauerhafte Fehler (falsche Antwort, Token abgelehnt) werden quittiert und gemeldet.
    private static func wiederhole(_ bib: PHPhotoLibrary, ablage: FotoStandAblage) throws {
        let jobs = PHAssetResourceUploadJob.fetchJobs(action: .retry, options: nil)
        for i in 0..<jobs.count {
            let job = jobs.object(at: i)
            if let code = fehlerCode(job), code == .badServerResponse || code == .userAuthenticationRequired {
                let grund = code == .userAuthenticationRequired ? "Der PC kennt dieses Handy nicht mehr. Bitte neu koppeln." : "Der PC hat einen Upload abgelehnt."
                ablage.aendere { $0.fehler = grund }
                try bib.performChangesAndWait {
                    guard let r = PHAssetResourceUploadJobChangeRequest(for: job) else { return }
                    r.acknowledge()
                }
            } else {
                try bib.performChangesAndWait {
                    guard let r = PHAssetResourceUploadJobChangeRequest(for: job) else { return }
                    r.retry(destination: nil)
                }
            }
        }
    }

    /// Erfolgreiche Jobs im Stand vermerken, dann quittieren; das schafft Platz im Job-Limit.
    private static func quittiere(_ bib: PHPhotoLibrary, ablage: FotoStandAblage) throws {
        let jobs = PHAssetResourceUploadJob.fetchJobs(action: .acknowledge, options: nil)
        for i in 0..<jobs.count {
            let job = jobs.object(at: i)
            if let k = job.destination.url.flatMap({ FotoRegeln.schluessel(pfad: $0.path) }) { ablage.aendere { $0.eingereicht?[k] = nil } }
            if job.state == .succeeded, let schluessel = job.destination.url.flatMap({ FotoRegeln.schluessel(pfad: $0.path) }) {
                ablage.aendere { $0.teil.insert(schluessel); $0.letzteUebertragung = Date(); $0.fehler = nil }
            } else if job.state == .failed {
                // Die Datei kommt beim nächsten Durchgang wieder in die Liste; der Grund steht in der App.
                let code = fehlerCode(job).map { " (\($0.rawValue))" } ?? ""
                ablage.aendere { $0.fehler = "Ein Upload im Hintergrund ist fehlgeschlagen\(code). Heimcloud versucht es später noch einmal." }
            }
            try bib.performChangesAndWait {
                guard let r = PHAssetResourceUploadJobChangeRequest(for: job) else { return }
                r.acknowledge()
            }
        }
    }

    /// Legt Jobs für noch fehlende Dateien an (neueste zuerst), bis iOS `limitExceeded` meldet oder nichts mehr offen ist.
    private static func legeJobsAn(_ bib: PHPhotoLibrary, client: HeimClient, ablage: FotoStandAblage, beendet: () -> Bool) throws -> (neu: Int, limit: Bool, nochMehr: Bool) {
        var stand = ablage.lade()
        let unterwegs = schluesselUnterwegs(stand: stand)
        let treffer = FotoBibliothek.abfrage()
        var stelle: [String: Int] = [:]
        var koepfe: [FotoKopf] = []
        koepfe.reserveCapacity(treffer.count)
        treffer.enumerateObjects { asset, i, _ in
            let k = FotoRegeln.kopf(assetId: asset.localIdentifier)
            koepfe.append(k)
            stelle[k.kennung] = i
        }
        var objekte: [String: PHAssetResource] = [:]
        let plan = FotoPlan.plane(koepfe: koepfe, stand: stand, uebersprungen: unterwegs, hoechstens: max(1, PHAssetResourceUploadJob.jobLimit)) { kopf in
            guard let i = stelle[kopf.kennung] else { return [] }
            return FotoBibliothek.ressourcen(treffer.object(at: i)).map { paar in
                objekte[paar.ressource.schluessel] = paar.objekt
                return paar.ressource
            }
        }
        stand.fertig.formUnion(plan.neuFertig)
        stand.raeumeAuf()
        ablage.speichere(stand)

        var neu = 0
        for r in plan.offen {
            if beendet() { return (neu, false, true) }
            guard let objekt = objekte[r.schluessel] else { continue }
            var anfrage = try client.fotoHochladenAnfrage(kennung: r.kennung, ressource: r.name, aufnahme: r.aufnahme, dateiname: r.dateiname)
            anfrage.allowsCellularAccess = !(stand.wlanNoetig || r.art.istVideo)
            let huelle = RessourceHuelle(objekt: objekt)
            let fertigeAnfrage = anfrage
            do {
                try bib.performChangesAndWait { legeJobAn(fertigeAnfrage, huelle.objekt) }
                neu += 1
                ablage.aendere { $0.eingereicht = ($0.eingereicht ?? [:]).merging([r.schluessel: Date()]) { _, neuer in neuer } }
            } catch let e as PHPhotosError where e.code == .limitExceeded {
                return (neu, true, true)
            }
        }
        return (neu, false, plan.offen.count >= max(1, PHAssetResourceUploadJob.jobLimit))
    }

    private static func legeJobAn(_ anfrage: URLRequest, _ objekt: PHAssetResource) {
        // `creationRequestForJob` gibt es ab iOS 26.4; `createJob` ist dort veraltet, aber das Mindestziel ist 26.1.
        if #available(iOS 26.4, *) {
            _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(destination: anfrage, resource: objekt)
        } else {
            PHAssetResourceUploadJobChangeRequest.createJob(destination: anfrage, resource: objekt)
        }
    }

    /// Dateien, für die schon ein Job läuft oder wartet, damit sie nicht doppelt angelegt werden. Laufende Jobs listet iOS erst ab 26.5
    /// (`Action.process`); davor merkt sich der `FotoStand` (`eingereicht`), was die Erweiterung selbst angelegt hat.
    private static func schluesselUnterwegs(stand: FotoStand) -> Set<String> {
        var menge = stand.unterwegs(jetzt: Date())
        var aktionen = [PHAssetResourceUploadJob.Action.retry, .acknowledge]
        if #available(iOS 26.5, *) { aktionen.append(.process) }
        for aktion in aktionen {
            let jobs = PHAssetResourceUploadJob.fetchJobs(action: aktion, options: nil)
            for i in 0..<jobs.count {
                if let s = jobs.object(at: i).destination.url.flatMap({ FotoRegeln.schluessel(pfad: $0.path) }) { menge.insert(s) }
            }
        }
        return menge
    }
}

/// shortcut: `PHAssetResource` ist nicht als Sendable markiert; der Änderungsblock läuft sofort und im selben Aufruf (`performChangesAndWait`). Bei Compilerfehler nach SDK-Wechsel prüfen.
private struct RessourceHuelle: @unchecked Sendable {
    let objekt: PHAssetResource
}
