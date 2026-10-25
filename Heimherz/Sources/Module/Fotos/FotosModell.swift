import Foundation
import Observation
import Photos

/// Zustand des Fotos-Tabs: Erlaubnis, Zahlen, Lauf. In Demo und Test-Host rührt er PhotoKit und das Netz nie an.
@MainActor @Observable
final class FotosModell {
    enum Erlaubnis: Equatable {
        case offen, verweigert, begrenzt, voll
    }

    private(set) var erlaubnis: Erlaubnis = .offen
    private(set) var anzeige = FotoAnzeige()
    private(set) var stand = FotoStand()
    private(set) var hintergrundAn = false

    let istDemo: Bool
    private let ablage: FotoStandAblage
    private var lauf: Task<Void, Never>?

    init(istDemo: Bool, ablage: FotoStandAblage? = nil) {
        self.istDemo = istDemo
        let ordner = URL.applicationSupportDirectory.appending(path: "Heimherz", directoryHint: .isDirectory)
        self.ablage = ablage ?? FotoStandAblage.appGruppe() ?? FotoStandAblage(ordner: ordner)
        if istDemo {
            erlaubnis = .voll
            hintergrundAn = true
            stand = FotoStand(fertig: [], teil: [], letzteUebertragung: Date().addingTimeInterval(-3_600), fehler: nil, nurWLAN: true, gesamt: 1_390)
            anzeige = FotoAnzeige(zahlen: FotoZahlen(gesamt: 1_390, amPC: 1_342))
        } else {
            stand = self.ablage.lade()
            if let g = stand.gesamt { anzeige.zahlen = FotoZahlen(gesamt: g, amPC: stand.fertig.count) }
            erlaubnis = Self.lese(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            hintergrundAn = erlaubnis == .voll && PHPhotoLibrary.shared().uploadJobExtensionEnabled
        }
    }

    private static func lese(_ s: PHAuthorizationStatus) -> Erlaubnis {
        switch s {
        case .authorized: return .voll
        case .limited: return .begrenzt
        case .denied, .restricted: return .verweigert
        default: return .offen
        }
    }

    var laeuft: Bool { anzeige.laeuft }
    var nurWLAN: Bool { stand.wlanNoetig }

    func setzeNurWLAN(_ an: Bool) {
        stand.nurWLAN = an
        ablage.aendere { $0.nurWLAN = an }
    }

    /// Fragt nach voller Erlaubnis und schaltet danach die Upload-Erweiterung ein (Apple verlangt volle Erlaubnis dafür).
    func erlaube() async {
        guard !istDemo else { return }
        erlaubnis = Self.lese(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        if erlaubnis == .voll { schalteHintergrund(true) }
    }

    func schalteHintergrund(_ an: Bool) {
        guard !istDemo, erlaubnis == .voll else { return }
        try? PHPhotoLibrary.shared().setUploadJobExtensionEnabled(an)
        hintergrundAn = PHPhotoLibrary.shared().uploadJobExtensionEnabled
    }

    /// Beim Öffnen und bei jedem Wechsel der Kopplung: Stand neu lesen, Erweiterung einschalten (nur gekoppelt, sonst gäbe es Jobs ohne Zugang), Reste aufräumen.
    func lade(gekoppelt: Bool) async {
        guard !istDemo else { return }
        if !gekoppelt { abbrechen() }   // ein laufender Abgleich trägt noch das alte Token
        stand = ablage.lade()
        erlaubnis = Self.lese(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if erlaubnis == .voll {
            if gekoppelt { try? PHPhotoLibrary.shared().setUploadJobExtensionEnabled(true) }
            hintergrundAn = PHPhotoLibrary.shared().uploadJobExtensionEnabled
        }
        FotoTemp.raeumeAuf(behalte: await HintergrundUpload.geteilt.laufendeDateien())
    }

    func abgleichen(client: HeimClient) {
        guard !istDemo, erlaubnis == .voll, lauf == nil else { return }
        let ablage = ablage
        let abgleich = FotoAbgleich(client: client, quelle: FotoQuelleLive(), sender: HintergrundUpload.geteilt, netz: NetzartLive.geteilt, ablage: ablage) { neu in
            Task { @MainActor in self.anzeige = neu }
        }
        anzeige.laeuft = true
        anzeige.schritt = "Starte …"
        lauf = Task {
            await abgleich.abgleichen()
            self.stand = ablage.lade()
            self.lauf = nil
        }
    }

    func abbrechen() { lauf?.cancel() }
}
