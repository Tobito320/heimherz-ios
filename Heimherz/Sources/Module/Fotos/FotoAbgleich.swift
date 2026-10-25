import Foundation

/// Die Fotos-Seite des Handys (PhotoKit); Attrappe im Test.
protocol FotoQuelle: Sendable {
    /// Zählt alles (neueste zuerst) und plant das nächste Stück mit höchstens `hoechstens` Dateien (`FotoPlan.plane`).
    /// `nur`: nur diese Assets (`localIdentifier`), Zahlen dann nur für sie. `uebersprungen`: Schlüssel, die in diesem Lauf nicht gingen.
    func plane(stand: FotoStand, hoechstens: Int, nur: [String]?, uebersprungen: Set<String>) async -> FotoPlan.Ergebnis
    /// Schreibt die Datei in eine Temp-Datei und gibt deren Adresse zurück. Bricht sofort ab, wenn die Aufgabe abgebrochen wird.
    /// `iCloud`: ein Original, das nur in iCloud liegt, darf geladen werden.
    func exportiere(_ r: FotoRessource, iCloud: Bool) async throws -> URL
}

/// Die Sende-Seite (Hintergrund-URLSession); Attrappe im Test.
protocol FotoSender: Sendable {
    /// Schickt die Datei und kehrt nach dem Ende des Transfers zurück. Wirft `HeimFehler`; bei Abbruch der Aufgabe wird der Transfer abgebrochen.
    func sende(datei: URL, anfrage: URLRequest) async throws
}

/// Der Netzweg des Handys; Attrappe im Test.
protocol Netzart: Sendable {
    func istWLAN() async -> Bool
}

/// Was die Oberfläche während und nach einem Lauf zeigt.
struct FotoAnzeige: Sendable, Equatable {
    var zahlen: FotoZahlen?
    /// Klartext zum aktuellen Schritt, nil wenn nichts läuft.
    var schritt: String?
    /// 0...1: Anteil der Mediathek, der am PC liegt.
    var fortschritt: Double?
    var laeuft = false
    /// Der Nutzer (oder das System) hat den Lauf angehalten; er macht beim nächsten Start dort weiter.
    var angehalten = false
    /// Kennungen der Assets, die vollständig am PC liegen.
    var fertig: Set<String> = []
    /// Kennungen der Assets, von denen gerade eine Datei geladen oder gesendet wird.
    var laufend: Set<String> = []
    /// Fehler dieses Laufs je Kennung, in Klartext.
    var fehler: [String: String] = [:]
    /// Dateiname der Datei, die zuletzt angefangen wurde.
    var datei: String?
    var bytesProSekunde: Double?
    var restSekunden: Double?
    /// Fotos, die in diesem Lauf vollständig am PC angekommen sind (Grundlage der Mitteilung "N Fotos gesichert").
    var gesichert = 0
    /// Fotos und Videos getrennt gezählt (erst Fotos, dann Videos); nil, bis das erste Mal gezählt wurde.
    var phasen: FotoPhasen?
}

/// Zählt Plätze für gleichzeitige Uploads. Wer wartet, wird der Reihe nach bedient; ein Abbruch weckt ihn mit `CancellationError`.
actor UploadSchranke {
    private var frei: Int
    private var wartende: [(id: UUID, fortsetzung: CheckedContinuation<Void, any Error>)] = []

    init(plaetze: Int) { frei = max(1, plaetze) }

    func hole() async throws {
        try Task.checkCancellation()
        if frei > 0 {
            frei -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                wartende.append((id, c))
            }
        } onCancel: {
            Task { await self.abbruch(id) }
        }
    }

    func gib() {
        if wartende.isEmpty { frei += 1 } else { wartende.removeFirst().fortsetzung.resume() }
    }

    private func abbruch(_ id: UUID) {
        guard let i = wartende.firstIndex(where: { $0.id == id }) else { return }
        wartende.remove(at: i).fortsetzung.resume(throwing: CancellationError())
    }
}

/// Ein Abgleich: Liste vom PC holen, planen (neueste zuerst, in Stücken zu `stueck` Dateien), jede Datei exportieren und senden. Die Stücke sind nur
/// Planungsgrößen: das nächste wird geplant, solange noch Uploads laufen, es gibt keine Sperre an den Grenzen (`sendeDurchgang`). Den Stand sichert
/// der Abgleich alle 20 Dateien oder alle 10 s. Abbruch der Aufgabe hält an: fertige Dateien zählen (der Server kennt sie), laufende Übertragungen
/// und halbe Exporte werden verworfen, der nächste Lauf macht dort weiter.
/// Bis zu `gleichzeitig` Dateien gehen zugleich hoch (6 im WLAN, 2 mobil); bis zu `voraus` weitere sind schon exportiert oder werden es gerade,
/// damit der nächste Upload ohne Wartezeit beginnt, solange diese Warteschlange unter `pufferGrenze` Bytes bleibt. Es liegen also nie mehr als
/// `gleichzeitig + voraus` Temp-Dateien da. Gestartet wird in der Reihenfolge der Mediathek, abgeschlossen wird, wie es kommt (grob neueste zuerst).
/// Eine Datei geht nie zweimal: jeder Schlüssel steht genau einmal in der Stückliste.
/// Zwei Durchgänge: erst alles, was lokal auf dem Handy liegt (Export ohne Netz; scheitert er, wird die Datei zurückgestellt), danach die iCloud-Originale
/// (nur mit "Originale aus iCloud laden"), dabei höchstens `iCloudParallel` Downloads zugleich. So kommt erst alles Schnelle durch.
/// Der Server ist die Wahrheit: schlägt hier etwas fehl, steht die Datei beim nächsten Lauf wieder in der Liste.
actor FotoAbgleich {
    static let stueckGroesse = 60
    /// Gleichzeitige Uploads (Messung am Gerät: nacheinander nur 2,6 MB/s bei 1 Gbit/s am PC, der Engpass war das Nacheinander).
    static let wlanParallel = 6
    static let mobilParallel = 2
    static let iCloudParallel = 4
    /// Bis zu so viele fertig exportierte Dateien warten auf einen freien Upload-Platz, und nur bis zu so vielen Bytes.
    static let standardVoraus = 12
    static let standardPuffer: Int64 = 1_000_000_000

    private let client: HeimClient
    private let quelle: any FotoQuelle
    private let sender: any FotoSender
    private let netz: any Netzart
    private let ablage: FotoStandAblage
    private let melde: @Sendable (FotoAnzeige) -> Void
    private let jetzt: @Sendable () -> Date
    /// nil: richtet sich nach dem Netz (WLAN `wlanParallel`, sonst `mobilParallel`), vor jedem Stück neu.
    private let festeParallelitaet: Int?
    private var gleichzeitig: Int
    private let stueck: Int
    private let voraus: Int
    private let pufferGrenze: Int64
    private var schranke: UploadSchranke
    /// Nur im iCloud-Durchgang: begrenzt die Downloads.
    private var ladeSchranke: UploadSchranke?
    /// Bytes der fertig exportierten Dateien, die noch auf einen Upload-Platz warten.
    private var puffer: Int64 = 0
    private var zurueckgestellt: Set<String> = []
    private var inICloudPhase = false
    /// Warteschlange des laufenden Durchgangs (`sendeDurchgang`): alles Geplante in Reihenfolge, `naechsteStelle` ist die nächste noch nicht gestartete.
    private var warteschlange: [FotoRessource] = []
    private var naechsteStelle = 0
    private var geplant: Set<String> = []
    private var erschoepft = false
    /// Stand sichern alle 20 bestätigten Dateien oder alle 10 s, nie als Sperre.
    private var seitSicherung = 0
    private var letzteSicherung = Date.distantPast
    /// Für die Messung (`FotoMessung`): laufende Uploads und Exporte in diesem Moment.
    private var aktiveUploads = 0
    private var aktiveExporte = 0
    /// In diesem Lauf in den iCloud-Durchgang zurückgestellt und vom `Stillstand` abgebrochen (gehen als Messung mit, `X-Heim-Aufgeschoben`, `X-Heim-Haenger`).
    private var aufgeschoben = 0
    private var haenger = 0

    private var stand = FotoStand()
    private var anzeige = FotoAnzeige()
    private var tempo = FotoTempo(start: Date())
    private var erledigt = 0
    private var gescheitert = 0
    private var wartetAufWLAN = 0
    /// Grund der letzten übersprungenen Datei (Export oder Server), für den Abschlusstext.
    private var exportFehler: String?
    private var abbruch: HeimFehler?
    private var wlanStop = false
    /// Nur ein Zähllauf (Tab geöffnet) zeigt nie "läuft": die Oberfläche soll dabei Start anbieten, nicht Anhalten.
    private var sendet = false
    /// Schlüssel, die in diesem Lauf nicht gingen: das nächste Stück überspringt sie, sonst käme der Lauf nie zum Ende.
    private var uebersprungen: Set<String> = []
    private var fehlend: [String: Int] = [:]
    private var gesendet: [String: Int] = [:]
    private var imFlug: [String: Int] = [:]

    init(client: HeimClient, quelle: any FotoQuelle, sender: any FotoSender, netz: any Netzart, ablage: FotoStandAblage,
         gleichzeitig: Int? = nil, voraus: Int = FotoAbgleich.standardVoraus, pufferGrenze: Int64 = FotoAbgleich.standardPuffer,
         stueck: Int = FotoAbgleich.stueckGroesse, jetzt: @escaping @Sendable () -> Date = { Date() },
         melde: @escaping @Sendable (FotoAnzeige) -> Void) {
        self.client = client
        self.quelle = quelle
        self.sender = sender
        self.netz = netz
        self.ablage = ablage
        self.festeParallelitaet = gleichzeitig.map { max(1, $0) }
        self.gleichzeitig = max(1, gleichzeitig ?? Self.wlanParallel)
        self.voraus = max(0, voraus)
        self.pufferGrenze = pufferGrenze
        self.schranke = UploadSchranke(plaetze: max(1, gleichzeitig ?? Self.wlanParallel))
        self.stueck = max(1, stueck)
        self.jetzt = jetzt
        self.melde = melde
    }

    private func zeige(schritt: String?, laeuft: Bool = true) {
        anzeige.schritt = schritt
        anzeige.laeuft = laeuft && sendet
        anzeige.laufend = Set(imFlug.keys)
        anzeige.fertig = stand.fertig
        let t = jetzt()
        anzeige.bytesProSekunde = laeuft ? tempo.bytesProSekunde(jetzt: t) : nil
        anzeige.restSekunden = laeuft ? anzeige.zahlen.flatMap { tempo.restSekunden(offen: $0.offen, jetzt: t) } : nil
        anzeige.fortschritt = anzeige.zahlen.flatMap { $0.gesamt > 0 ? Double($0.amPC) / Double($0.gesamt) : nil }
        melde(anzeige)
    }

    /// Nur zählen, was am PC liegt (Tab öffnen), nichts senden.
    func zaehle() async { await lauf(nur: nil, senden: false) }

    /// Sendet alles Offene, oder nur die Assets in `nur` (`localIdentifier`, Einzel-Upload).
    func abgleichen(nur: [String]? = nil) async { await lauf(nur: nur, senden: true) }

    private func lauf(nur: [String]?, senden: Bool) async {
        stand = ablage.lade()
        sendet = senden
        // Die Zahl für Tempo und Restzeit soll auch weiterlaufen, wenn lange nichts fertig wird (eine große Datei): alle 2 Sekunden neu rechnen.
        let takt = Task { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if sendet, anzeige.laeuft { zeige(schritt: anzeige.schritt) }
            }
        }
        defer { takt.cancel() }
        erledigt = 0; gescheitert = 0; wartetAufWLAN = 0; exportFehler = nil; abbruch = nil; wlanStop = false
        uebersprungen = []; fehlend = [:]; gesendet = [:]; imFlug = [:]
        zurueckgestellt = []; inICloudPhase = false; ladeSchranke = nil; puffer = 0; aufgeschoben = 0; haenger = 0
        tempo = FotoTempo(start: jetzt())
        letzteSicherung = jetzt(); seitSicherung = 0
        // Zahlen vom letzten Mal, damit Überschrift und Balken beim Start nicht verschwinden (auch beim Einzel-Upload, der nicht neu zählt).
        anzeige = FotoAnzeige(zahlen: stand.gesamt.map { FotoZahlen(gesamt: $0, amPC: stand.fertig.count) })
        zeige(schritt: "Frage den PC, was schon da ist …")
        do {
            stand.uebernimm(bekannt: try await client.fotosBekannt())
        } catch {
            // Anhalten schon in dieser Phase ist kein Fehler.
            if Task.isCancelled { abschliessen(senden: senden); return }
            stand.fehler = (error as? HeimFehler)?.nutzerText ?? HeimFehler.nichtErreichbar.nutzerText
            sichere()
            zeige(schritt: nil, laeuft: false)
            return
        }
        while !Task.isCancelled, abbruch == nil, !wlanStop {
            aktualisiereEinstellungen()
            zeige(schritt: senden ? "Suche die nächsten Dateien …" : "Zähle die Fotos …")
            let plan = await quelle.plane(stand: stand, hoechstens: senden ? stueck : 0, nur: nur, uebersprungen: uebersprungen)
            stand.fertig.formUnion(plan.neuFertig)
            stand.raeumeAuf()
            fehlend = plan.fehlend
            gesendet = [:]
            if nur == nil {
                stand.gesamt = plan.zahlen.gesamt
                anzeige.zahlen = plan.zahlen
                anzeige.phasen = plan.phasen
            }
            sichere()
            if !senden { break }
            if plan.offen.isEmpty {
                if wechsleInICloud() { continue }
                break
            }
            let vorher = erledigt + uebersprungen.count
            await waehleParallelitaet()
            await sendeDurchgang(plan.offen, nur: nur, iCloud: inICloudPhase)
            sichere()
            if erledigt + uebersprungen.count == vorher {   // kein Fortschritt: nicht endlos planen
                if wechsleInICloud() { continue }
                break
            }
        }
        abschliessen(senden: senden)
    }

    /// Alles Lokale ist durch: jetzt die zurückgestellten Dateien, die nur in iCloud liegen (nur wenn der Schalter an ist).
    private func wechsleInICloud() -> Bool {
        guard !inICloudPhase, !zurueckgestellt.isEmpty, !Task.isCancelled, abbruch == nil, !wlanStop else { return false }
        inICloudPhase = true
        uebersprungen.subtract(zurueckgestellt)
        zurueckgestellt = []
        ladeSchranke = UploadSchranke(plaetze: Self.iCloudParallel)
        return true
    }

    /// Vor jedem Stück (dann läuft kein Upload mehr): 6 im WLAN, 2 mobil, außer die Zahl ist fest vorgegeben.
    private func waehleParallelitaet() async {
        let n: Int
        if let fest = festeParallelitaet { n = fest } else { n = await netz.istWLAN() ? Self.wlanParallel : Self.mobilParallel }
        guard n != gleichzeitig else { return }
        gleichzeitig = n
        schranke = UploadSchranke(plaetze: n)
    }

    private func abschliessen(senden: Bool) {
        let vomNutzer = Task.isCancelled && abbruch == nil
        if senden { stand.fehler = vomNutzer ? nil : abschlussText() }
        anzeige.angehalten = vomNutzer
        anzeige.datei = nil
        imFlug = [:]
        sichere()
        zeige(schritt: nil, laeuft: false)
    }

    private func abschlussText() -> String? {
        if let abbruch { return abbruch.nutzerText }
        var teile: [String] = []
        if gescheitert > 0 {
            let grund = exportFehler.map { " (\($0))" } ?? ""
            teile.append(gescheitert == 1 ? "1 Datei konnte nicht übertragen werden\(grund)." : "\(gescheitert.formatted()) Dateien konnten nicht übertragen werden\(grund).")
        }
        if wartetAufWLAN > 0 { teile.append(wartetAufWLAN == 1 ? "1 Datei wartet auf WLAN." : "\(wartetAufWLAN.formatted()) Dateien warten auf WLAN.") }
        return teile.isEmpty ? nil : teile.joined(separator: " ")
    }

    // MARK: Stand

    /// Schreibt nur, was dieser Lauf kennt. Schalter (WLAN, iCloud) und Jobs der Erweiterung bleiben, wie sie auf der Platte stehen:
    /// Der Nutzer darf sie mitten im Lauf umlegen, und die Erweiterung schreibt gleichzeitig.
    private func sichere() {
        seitSicherung = 0
        letzteSicherung = jetzt()
        ablage.aendere { platte in
            platte.fertig.formUnion(stand.fertig)
            platte.teil.formUnion(stand.teil)
            platte.raeumeAuf()
            platte.letzteUebertragung = stand.letzteUebertragung ?? platte.letzteUebertragung
            platte.fehler = stand.fehler
            platte.gesamt = stand.gesamt ?? platte.gesamt
        }
    }

    private func aktualisiereEinstellungen() {
        let platte = ablage.lade()
        stand.nurWLAN = platte.nurWLAN
        stand.iCloudLaden = platte.iCloudLaden
        stand.eingereicht = platte.eingereicht
    }

    // MARK: Senden

    private enum Ausgang: Sendable {
        case gesendet(FotoRessource, Int64), wartetAufWLAN(FotoRessource), nichtLesbar(FotoRessource, String), nachICloud(FotoRessource)
        case nichtUebertragen(FotoRessource, String), stop(HeimFehler), abgebrochen(FotoRessource)
    }

    /// Eine durchgehende Pipeline je Durchgang: immer `gleichzeitig` Dateien in Arbeit, dazu bis zu `voraus` schon exportierte. Das nächste Stück wird
    /// geplant, solange noch Dateien in der Warteschlange und Uploads unterwegs sind (`fuelleNach`), nie erst, wenn alles leer ist. So gibt es an
    /// Stückgrenzen keinen Leerlauf. Gestartet wird in der Reihenfolge der Planung, abgeschlossen, wie es kommt.
    private func sendeDurchgang(_ erste: [FotoRessource], nur: [String]?, iCloud: Bool) async {
        geplant = []; warteschlange = []; naechsteStelle = 0; erschoepft = false
        nimmAuf(erste)
        await withTaskGroup(of: Ausgang.self) { gruppe in
            var laufend = 0
            while true {
                if warteschlange.count - naechsteStelle < gleichzeitig + voraus { await fuelleNach(nur: nur) }
                // Immer `gleichzeitig` Dateien in Arbeit; darüber hinaus nur, solange die Warteschlange nicht voll ist (Anzahl und Bytes).
                while laufend < gleichzeitig || (laufend < gleichzeitig + voraus && puffer < pufferGrenze),
                      abbruch == nil, !wlanStop, !Task.isCancelled, naechsteStelle < warteschlange.count {
                    let r = warteschlange[naechsteStelle]
                    naechsteStelle += 1
                    gruppe.addTask { await self.bearbeite(r, iCloud: iCloud) }
                    laufend += 1
                }
                guard laufend > 0, let ausgang = await gruppe.next() else { break }
                laufend -= 1
                verbuche(ausgang)
                if abbruch != nil || wlanStop { gruppe.cancelAll() }
            }
        }
    }

    /// Jede Datei steht in diesem Durchgang genau einmal in der Warteschlange (sonst 409 am PC). Gibt zurück, wie viele neu waren.
    @discardableResult
    private func nimmAuf(_ liste: [FotoRessource]) -> Int {
        var n = 0
        for r in liste where geplant.insert(r.schluessel).inserted {
            warteschlange.append(r)
            n += 1
        }
        return n
    }

    /// Das nächste Stück planen, während Uploads laufen. Die Quelle liest die Mediathek je Lauf nur einmal (`PlanSpeicher`), das hier ist billig.
    /// Zahlen und Phasen der Anzeige bleiben, wie sie sind: `verbuche` zählt mit, ein Plan von jetzt wäre schon wieder überholt.
    private func fuelleNach(nur: [String]?) async {
        guard !erschoepft, abbruch == nil, !wlanStop, !Task.isCancelled else { return }
        aktualisiereEinstellungen()   // Schalter, die der Nutzer mitten im Lauf umlegt, gelten ab dem nächsten Stück
        let plan = await quelle.plane(stand: stand, hoechstens: stueck, nur: nur, uebersprungen: uebersprungen.union(geplant))
        stand.fertig.formUnion(plan.neuFertig)
        // Fehlt einem Asset schon eine Datei weniger als beim ersten Blick (sie ging inzwischen durch), bleibt die größere Zahl: `gesendet` zählt den ganzen Durchgang.
        for (kennung, n) in plan.fehlend { fehlend[kennung] = max(fehlend[kennung] ?? 0, n) }
        if nimmAuf(plan.offen) == 0 { erschoepft = true }
    }

    private func verbuche(_ a: Ausgang) {
        switch a {
        case .gesendet(let r, let bytes):
            erledigt += 1
            tempo.buche(bytes: bytes, jetzt: jetzt())
            stand.teil.insert(r.schluessel)
            stand.letzteUebertragung = jetzt()
            gesendet[r.kennung, default: 0] += 1
            seitSicherung += 1
            // Die letzte fehlende Datei eines Assets ist da: sofort fertig, das Häkchen im Raster erscheint ohne auf das nächste Stück zu warten.
            if gesendet[r.kennung] == fehlend[r.kennung], stand.fertig.insert(r.kennung).inserted {
                anzeige.zahlen?.amPC += 1
                anzeige.gesichert += 1
                if r.assetIstVideo { anzeige.phasen?.videosAmPC += 1 } else { anzeige.phasen?.fotosAmPC += 1 }
            }
            if seitSicherung >= 20 || jetzt().timeIntervalSince(letzteSicherung) >= 10 { sichere() }
        case .wartetAufWLAN(let r):
            wartetAufWLAN += 1
            if stand.wlanNoetig { wlanStop = true } else { uebersprungen.insert(r.schluessel) }
        case .nichtLesbar(let r, let grund), .nichtUebertragen(let r, let grund):
            gescheitert += 1
            exportFehler = grund
            uebersprungen.insert(r.schluessel)
            anzeige.fehler[r.kennung] = grund
        case .stop(let f): abbruch = f
        case .abgebrochen(let r): uebersprungen.insert(r.schluessel)
        case .nachICloud(let r):
            aufgeschoben += 1
            zurueckgestellt.insert(r.schluessel)
            uebersprungen.insert(r.schluessel)
        }
        zeige(schritt: anzeige.schritt)
    }

    private func beginne(_ r: FotoRessource, iCloud: Bool) {
        imFlug[r.kennung, default: 0] += 1
        anzeige.fehler[r.kennung] = nil
        anzeige.datei = r.dateiname
        zeige(schritt: iCloud ? "Lade \(r.dateiname) aus iCloud …" : "Sende \(r.dateiname) …")
    }

    private func ende(_ r: FotoRessource) {
        imFlug[r.kennung, default: 1] -= 1
        if imFlug[r.kennung, default: 0] <= 0 { imFlug[r.kennung] = nil }
    }

    private func bearbeite(_ r: FotoRessource, iCloud: Bool) async -> Ausgang {
        if (stand.wlanNoetig || r.art.istVideo), !(await netz.istWLAN()) { return .wartetAufWLAN(r) }
        beginne(r, iCloud: iCloud)
        defer { ende(r) }
        let temp: URL, exportMs: Int
        do {
            let e = try await exportiere(r, iCloud: iCloud)
            temp = e.url
            exportMs = e.ms
        } catch is CancellationError {
            return .abgebrochen(r)
        } catch {
            if (error as? FotoFehler) == .haengt { haenger += 1 }
            // Erster Durchgang: liegt das Original nicht auf dem Handy (oder hing der Export), kommt es in den iCloud-Durchgang (falls erlaubt).
            if !iCloud, stand.iCloudErlaubt, [.nurInICloud, .haengt].contains(error as? FotoFehler) { return .nachICloud(r) }
            return .nichtLesbar(r, (error as? FotoFehler)?.nutzerText ?? "nicht lesbar")
        }
        let exportFertig = ContinuousClock.now
        defer { try? FileManager.default.removeItem(at: temp) }
        if Task.isCancelled { return .abgebrochen(r) }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        puffer += bytes
        var imPuffer = true
        defer { if imPuffer { puffer -= bytes } }
        do {
            var anfrage = try client.fotoHochladenAnfrage(kennung: r.kennung, ressource: r.name, aufnahme: r.aufnahme, dateiname: r.dateiname)
            anfrage.allowsCellularAccess = !(stand.wlanNoetig || r.art.istVideo)
            // Ein Platz für den Upload; der Export dieser Datei lief schon, während andere hochgingen.
            try await schranke.hole()
            puffer -= bytes
            imPuffer = false
            aktiveUploads += 1
            FotoMessung(exportMs: exportMs, warteMs: FotoMessung.ms(seit: exportFertig), aktiv: aktiveUploads, exporte: aktiveExporte, iCloud: iCloud,
                        aufgeschoben: aufgeschoben, haenger: haenger).setze(in: &anfrage)
            // Ein Anhalten kann den Platz und den Abbruch gleichzeitig bringen: dann nicht mehr senden.
            if Task.isCancelled {
                await gibPlatz()
                return .abgebrochen(r)
            }
            do { try await sender.sende(datei: temp, anfrage: anfrage) } catch {
                await gibPlatz()
                throw error
            }
            await gibPlatz()
            return .gesendet(r, bytes)
        } catch is CancellationError {
            return .abgebrochen(r)
        } catch HeimFehler.abgebrochen {
            return .abgebrochen(r)
        } catch let f as HeimFehler {
            // Nur was den ganzen Lauf betrifft hält ihn an: kein Zugang, Platte voll, PC nicht erreichbar.
            // Ein Serverfehler (5xx) oder eine Ablehnung (4xx) trifft diese eine Datei; sie bleibt offen, der Lauf geht weiter.
            switch f {
            case .nichtBerechtigt, .nichtGekoppelt, .speicherVoll, .nichtErreichbar, .zeitueberschreitung: return .stop(f)
            default: return .nichtUebertragen(r, Self.kurzGrund(f))
            }
        } catch {
            return .nichtUebertragen(r, "Übertragung fehlgeschlagen")
        }
    }

    private func gibPlatz() async {
        aktiveUploads -= 1
        await schranke.gib()
    }

    /// Export; im iCloud-Durchgang höchstens `iCloudParallel` Downloads zugleich. `ms`: Dauer des Exports selbst, ohne Warten auf einen Download-Platz.
    private func exportiere(_ r: FotoRessource, iCloud: Bool) async throws -> (url: URL, ms: Int) {
        let platz = iCloud ? ladeSchranke : nil
        if let platz { try await platz.hole() }
        let t0 = ContinuousClock.now
        aktiveExporte += 1
        do {
            let u = try await quelle.exportiere(r, iCloud: iCloud)
            aktiveExporte -= 1
            await platz?.gib()
            return (u, FotoMessung.ms(seit: t0))
        } catch {
            aktiveExporte -= 1
            await platz?.gib()
            throw error
        }
    }

    /// Kurzer Grund für den Abschlusstext ("1 Datei konnte nicht übertragen werden (Serverfehler 503)").
    private static func kurzGrund(_ f: HeimFehler) -> String {
        switch f {
        case .serverFehler(let n): return "Serverfehler \(n)"
        case .abgelehnt(let n): return "vom PC abgelehnt, Code \(n)"
        case .zuGross: return "zu groß für den PC-Dienst"
        case .verboten: return "vom PC nicht erlaubt"
        case .nichtGefunden: return "Pfad am PC unbekannt"
        case .konflikt: return "Konflikt am PC"
        default: return "Übertragung fehlgeschlagen"
        }
    }
}

/// Fehler beim Lesen aus der Mediathek.
enum FotoFehler: Error, Equatable {
    case speicherKnapp
    case nichtGefunden
    case nurInICloud
    /// PhotoKit lieferte zu lange keine Daten (`Stillstand`); die Datei kommt beim nächsten Lauf wieder dran.
    case haengt

    var nutzerText: String {
        switch self {
        case .speicherKnapp: return "zu wenig freier Speicher am Handy"
        case .nichtGefunden: return "nicht mehr in der Mediathek"
        case .nurInICloud: return "liegt nur in iCloud, und das Laden von iCloud ist aus"
        case .haengt: return "Laden hing, kommt beim nächsten Mal dran"
        }
    }
}
