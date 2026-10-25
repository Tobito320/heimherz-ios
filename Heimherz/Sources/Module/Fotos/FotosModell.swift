import BackgroundTasks
import Foundation
import Observation
import Photos

/// Zustand des Fotos-Tabs: Erlaubnis, Zahlen, Lauf. In Demo und Test-Host rührt er PhotoKit und das Netz nie an.
/// Es gibt genau einen Lauf zur Zeit (`geteilt`): Tab, Systemaufgabe im Hintergrund und Nachtlauf bedienen dasselbe Modell.
@MainActor @Observable
final class FotosModell {
    static let geteilt = FotosModell(istDemo: AppUmgebung.istTestHost)

    enum Erlaubnis: Equatable {
        case offen, verweigert, begrenzt, voll
    }

    private(set) var erlaubnis: Erlaubnis = .offen
    private(set) var anzeige = FotoAnzeige()
    private(set) var stand = FotoStand()
    private(set) var hintergrundAn = false

    let istDemo: Bool
    private let ablage: FotoStandAblage
    private let einstellungen: GeteilteEinstellungen
    private let mitteilung: any MitteilungsDienst
    /// Beobachtet den Strom der Anzeigen, wartet auf `arbeit` und räumt danach auf.
    private var lauf: Task<Void, Never>?
    private var arbeit: Task<Void, Never>?
    /// Die Systemaufgabe, die den Lauf im Hintergrund trägt (iOS 26), solange es sie gibt.
    private var fortsetzung: FotoHintergrund.AufgabenBox?
    private var gespiegelt = -1
    private var nutzerLauf = false
    /// Nach diesem Lauf darf nachts weitergemacht werden (Start per Knopf, Nachtlauf selbst); Einzel-Upload und Zählen planen nichts.
    private var plantNachts = false
    private var nutzerHatAngehalten = false
    /// "Abgleich starten" kam, während nur gezählt wurde: das Zählen bricht ab, danach startet der Abgleich.
    private var vorgemerkt: HeimClient?

    init(istDemo: Bool, ablage: FotoStandAblage? = nil, einstellungen: GeteilteEinstellungen = GeteilteEinstellungen(), mitteilung: any MitteilungsDienst = SystemMitteilungen()) {
        self.istDemo = istDemo
        self.einstellungen = einstellungen
        self.mitteilung = mitteilung
        let ordner = URL.applicationSupportDirectory.appending(path: "Heimherz", directoryHint: .isDirectory)
        self.ablage = ablage ?? FotoStandAblage.appGruppe() ?? FotoStandAblage(ordner: ordner)
        if istDemo {
            erlaubnis = .voll
            hintergrundAn = true
            stand = FotoStand(fertig: [], teil: [], letzteUebertragung: Date().addingTimeInterval(-3_600), fehler: nil, nurWLAN: true, gesamt: 8_312)
            anzeige = Self.demoAnzeige
        } else {
            stand = self.ablage.lade()
            anzeige.fertig = stand.fertig
            if let g = stand.gesamt { anzeige.zahlen = FotoZahlen(gesamt: g, amPC: stand.fertig.count) }
            erlaubnis = Self.lese(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            hintergrundAn = erlaubnis == .voll && PHPhotoLibrary.shared().uploadJobExtensionEnabled
        }
    }

    /// Erfundener Zwischenstand für Screenshots und Vorschau: ein Abgleich läuft; fast alle der ersten 40 Bilder liegen am PC, eines läuft, eines hat einen Fehler.
    static var demoAnzeige: FotoAnzeige {
        let koepfe = FotoMediathek.demoKoepfe
        return FotoAnzeige(
            zahlen: FotoZahlen(gesamt: 8_312, amPC: 1_234), schritt: "Sende IMG_4821.HEIC …", fortschritt: 1_234.0 / 8_312.0, laeuft: true,
            fertig: Set(koepfe.prefix(40).enumerated().filter { $0.offset != 5 && $0.offset != 6 }.map(\.element.kennung)),
            laufend: [koepfe[5].kennung], fehler: [koepfe[6].kennung: "vom PC abgelehnt, Code 400"],
            datei: "IMG_4821.HEIC", bytesProSekunde: 4_200_000, restSekunden: 5_400)
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
    var iCloudLaden: Bool { stand.iCloudErlaubt }

    func setzeNurWLAN(_ an: Bool) {
        stand.nurWLAN = an
        ablage.aendere { $0.nurWLAN = an }
    }

    func setzeICloudLaden(_ an: Bool) {
        stand.iCloudLaden = an
        ablage.aendere { $0.iCloudLaden = an }
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

    /// Nur lesen, was iOS gerade sagt (Einstellungen-Tab); schaltet nichts ein, anders als `lade`.
    func liesSystemStand() {
        guard !istDemo else { return }
        erlaubnis = Self.lese(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        hintergrundAn = erlaubnis == .voll && PHPhotoLibrary.shared().uploadJobExtensionEnabled
    }

    /// Beim Öffnen und bei jedem Wechsel der Kopplung: Stand neu lesen, Erweiterung einschalten (nur gekoppelt, sonst gäbe es Jobs ohne Zugang).
    /// Temp-Dateien räumt es nur auf, wenn kein Lauf eine davon braucht.
    func lade(gekoppelt: Bool) async {
        guard !istDemo else { return }
        if !gekoppelt { halteAn() }   // ein laufender Abgleich trägt noch das alte Token
        stand = ablage.lade()
        erlaubnis = Self.lese(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if erlaubnis == .voll {
            if gekoppelt { try? PHPhotoLibrary.shared().setUploadJobExtensionEnabled(true) }
            hintergrundAn = PHPhotoLibrary.shared().uploadJobExtensionEnabled
        }
        if lauf == nil {
            anzeige.fertig = stand.fertig
            await raeumeTempAuf()
        }
    }

    private func raeumeTempAuf() async {
        FotoTemp.raeumeAuf(behalte: await HintergrundUpload.geteilt.laufendeDateien())
    }

    // MARK: Lauf

    /// Zählt, was am PC liegt, und sendet nichts (beim Öffnen des Tabs).
    func aktualisiere(client: HeimClient) {
        guard kannStarten else { return }
        beginne(client: client, senden: false, nur: nil, vomNutzer: false, nachts: false)
    }

    /// "Abgleich starten": sendet alles Offene, neueste zuerst, und macht dort weiter, wo der letzte Lauf aufgehört hat.
    func starte(client: HeimClient) {
        guard !istDemo, erlaubnis == .voll else { return }
        if lauf != nil {
            guard !anzeige.laeuft else { return }
            vorgemerkt = client
            arbeit?.cancel()
            return
        }
        // Die erste Mitteilung braucht die Erlaubnis; der Start per Knopf ist der Moment, in dem der Nutzer sie versteht.
        if einstellungen.fotoMitteilung { Task { [mitteilung] in await mitteilung.erlaubnisFragen() } }
        beginne(client: client, senden: true, nur: nil, vomNutzer: true, nachts: true)
    }

    /// "Jetzt hochladen" für genau ein Bild (nur wenn kein Lauf geht, sonst käme derselbe Schlüssel doppelt an den PC).
    func ladeEinzeln(assetId: String, client: HeimClient) {
        guard kannStarten else { return }
        beginne(client: client, senden: true, nur: [assetId], vomNutzer: false, nachts: false)
    }

    private var kannStarten: Bool { !istDemo && erlaubnis == .voll && lauf == nil }

    private func beginne(client: HeimClient, senden: Bool, nur: [String]?, vomNutzer: Bool, nachts: Bool) {
        let ablage = ablage
        let (strom, weiter) = AsyncStream.makeStream(of: FotoAnzeige.self, bufferingPolicy: .bufferingNewest(1))
        let abgleich = FotoAbgleich(client: client, quelle: FotoQuelleLive(), sender: HintergrundUpload.geteilt, netz: NetzartLive.geteilt, ablage: ablage) { neu in
            weiter.yield(neu)
        }
        nutzerLauf = vomNutzer
        plantNachts = nachts
        nutzerHatAngehalten = false
        gespiegelt = -1
        anzeige.laeuft = senden
        anzeige.angehalten = false
        anzeige.schritt = senden ? "Starte …" : "Zähle die Fotos …"
        if vomNutzer { FotoHintergrund.reicheFortsetzungEin() }
        let arbeit = Task {
            if senden { await abgleich.abgleichen(nur: nur) } else { await abgleich.zaehle() }
            weiter.finish()
        }
        self.arbeit = arbeit
        lauf = Task {
            for await a in strom { self.uebernimm(a) }
            await arbeit.value
            await self.laufBeendet()
        }
    }

    /// "Anhalten": bricht den Lauf sauber ab. Fertige Dateien zählen, laufende Übertragungen und halbe Exporte werden verworfen,
    /// der nächste Start macht dort weiter. Der Nachtlauf wird abgesagt (`nachtAbsagen`), außer das System selbst beendet die Aufgabe.
    func halteAn(nachtAbsagen: Bool = true) {
        guard !istDemo else { return }
        arbeit?.cancel()
        if nachtAbsagen {
            nutzerHatAngehalten = true
            FotoHintergrund.sageNachtAb()
        }
    }

    private func uebernimm(_ a: FotoAnzeige) {
        anzeige = a
        spiegele(a)
    }

    private func laufBeendet() async {
        stand = ablage.lade()
        let a = anzeige
        let meldeLauf = plantNachts   // nur Knopf und Nachtlauf melden; Zählen und Einzel-Upload bleiben still
        let angehalten = nutzerHatAngehalten
        lauf = nil
        arbeit = nil
        anzeige.fertig = stand.fertig.union(a.fertig)
        if let box = fortsetzung {
            box.task.setTaskCompleted(success: !a.angehalten)
            fortsetzung = nil
        }
        // Der Rest geht nachts weiter, solange etwas offen ist und der Nutzer nicht angehalten hat (das System darf beenden).
        if plantNachts, !nutzerHatAngehalten, (a.zahlen?.offen ?? 0) > 0 { FotoHintergrund.planeNacht() }
        nutzerLauf = false
        plantNachts = false
        // Läuft noch im Lauf selbst: Der Nachtlauf wartet auf ihn, die Mitteilung geht raus, bevor iOS die Aufgabe schließt.
        if meldeLauf, !istDemo {
            await FotoMitteilung.meldeNachLauf(gesichert: a.gesichert, vomNutzerAngehalten: angehalten, einstellungen: einstellungen, dienst: mitteilung)
        }
        await raeumeTempAuf()
        if let c = vorgemerkt {
            vorgemerkt = nil
            starte(client: c)
        }
    }

    // MARK: Systemaufgaben

    /// Die Systemaufgabe (iOS 26) trägt den Lauf weiter, wenn die App in den Hintergrund geht. Sie besitzt die Arbeit nicht:
    /// Sie zeigt den Fortschritt, und läuft sie ab (Nutzer bricht in der Systemanzeige ab), hält der Abgleich an.
    func haengeAn(_ box: FotoHintergrund.AufgabenBox) {
        guard lauf != nil else {
            box.task.setTaskCompleted(success: true)
            return
        }
        fortsetzung = box
        box.task.expirationHandler = { Task { @MainActor in self.halteAn(nachtAbsagen: false) } }
        spiegele(anzeige)
    }

    private func spiegele(_ a: FotoAnzeige) {
        guard let c = fortsetzung?.task as? BGContinuedProcessingTask, let z = a.zahlen, z.amPC != gespiegelt else { return }
        gespiegelt = z.amPC
        c.progress.totalUnitCount = Int64(z.gesamt)
        c.progress.completedUnitCount = Int64(z.amPC)
        c.updateTitle("Fotos zum PC", subtitle: "\(z.amPC.formatted()) von \(z.gesamt.formatted()) am PC")
    }

    /// Nachts mit Strom und Netz (BGProcessingTask): macht den Rest, ohne dass die App offen ist.
    func nachtlauf(_ box: FotoHintergrund.AufgabenBox) async {
        if (anzeige.zahlen?.offen ?? 1) > 0 { FotoHintergrund.planeNacht() }   // gleich wieder einplanen, falls dieser Lauf nicht reicht (Apple); nichts mehr offen: Schluss
        guard kannStarten, let client = try? AppUmgebung.geteilt.client() else {
            box.task.setTaskCompleted(success: true)
            return
        }
        box.task.expirationHandler = { Task { @MainActor in self.halteAn(nachtAbsagen: false) } }
        beginne(client: client, senden: true, nur: nil, vomNutzer: false, nachts: true)
        await lauf?.value
        box.task.setTaskCompleted(success: !anzeige.angehalten)
    }
}
