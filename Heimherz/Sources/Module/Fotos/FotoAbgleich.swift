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
}

/// Ein Abgleich in kleinen Stücken (`stueck` Dateien): Liste vom PC holen, das nächste Stück planen (neueste zuerst), jede Datei exportieren
/// und senden, Stand sichern, nächstes Stück. Abbruch der Aufgabe hält an: fertige Dateien zählen (der Server kennt sie), laufende Übertragungen
/// und halbe Exporte werden verworfen, der nächste Lauf macht dort weiter. Es liegen nie mehr als `gleichzeitig` Temp-Dateien da.
/// Der Server ist die Wahrheit: schlägt hier etwas fehl, steht die Datei beim nächsten Lauf wieder in der Liste.
actor FotoAbgleich {
    static let stueckGroesse = 20

    private let client: HeimClient
    private let quelle: any FotoQuelle
    private let sender: any FotoSender
    private let netz: any Netzart
    private let ablage: FotoStandAblage
    private let melde: @Sendable (FotoAnzeige) -> Void
    private let jetzt: @Sendable () -> Date
    private let gleichzeitig: Int
    private let stueck: Int

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
         gleichzeitig: Int = 2, stueck: Int = FotoAbgleich.stueckGroesse, jetzt: @escaping @Sendable () -> Date = { Date() },
         melde: @escaping @Sendable (FotoAnzeige) -> Void) {
        self.client = client
        self.quelle = quelle
        self.sender = sender
        self.netz = netz
        self.ablage = ablage
        self.gleichzeitig = max(1, gleichzeitig)
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
        erledigt = 0; gescheitert = 0; wartetAufWLAN = 0; exportFehler = nil; abbruch = nil; wlanStop = false
        uebersprungen = []; fehlend = [:]; gesendet = [:]; imFlug = [:]
        tempo = FotoTempo(start: jetzt())
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
            }
            sichere()
            if !senden || plan.offen.isEmpty { break }
            let vorher = erledigt + uebersprungen.count
            await sendeStueck(plan.offen)
            sichere()
            if erledigt + uebersprungen.count == vorher { break }   // kein Fortschritt: nicht endlos planen
        }
        abschliessen(senden: senden)
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
        case gesendet(FotoRessource, Int64), wartetAufWLAN(FotoRessource), nichtLesbar(FotoRessource, String)
        case nichtUebertragen(FotoRessource, String), stop(HeimFehler), abgebrochen(FotoRessource)
    }

    private func sendeStueck(_ liste: [FotoRessource]) async {
        var naechste = liste.makeIterator()
        await withTaskGroup(of: Ausgang.self) { gruppe in
            var laufend = 0
            while true {
                while laufend < gleichzeitig, abbruch == nil, !wlanStop, !Task.isCancelled, let r = naechste.next() {
                    gruppe.addTask { await self.bearbeite(r) }
                    laufend += 1
                }
                guard laufend > 0, let ausgang = await gruppe.next() else { break }
                laufend -= 1
                verbuche(ausgang)
                if abbruch != nil || wlanStop { gruppe.cancelAll() }
            }
        }
    }

    private func verbuche(_ a: Ausgang) {
        switch a {
        case .gesendet(let r, let bytes):
            erledigt += 1
            tempo.buche(bytes: bytes)
            stand.teil.insert(r.schluessel)
            stand.letzteUebertragung = jetzt()
            gesendet[r.kennung, default: 0] += 1
            // Die letzte fehlende Datei eines Assets ist da: sofort fertig, das Häkchen im Raster erscheint ohne auf das nächste Stück zu warten.
            if gesendet[r.kennung] == fehlend[r.kennung], stand.fertig.insert(r.kennung).inserted {
                anzeige.zahlen?.amPC += 1
                anzeige.gesichert += 1
            }
            if erledigt % 25 == 0 { sichere() }
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
        }
        zeige(schritt: anzeige.schritt)
    }

    private func beginne(_ r: FotoRessource) {
        imFlug[r.kennung, default: 0] += 1
        anzeige.fehler[r.kennung] = nil
        anzeige.datei = r.dateiname
        zeige(schritt: "Sende \(r.dateiname) …")
    }

    private func ende(_ r: FotoRessource) {
        imFlug[r.kennung, default: 1] -= 1
        if imFlug[r.kennung, default: 0] <= 0 { imFlug[r.kennung] = nil }
    }

    private func bearbeite(_ r: FotoRessource) async -> Ausgang {
        if (stand.wlanNoetig || r.art.istVideo), !(await netz.istWLAN()) { return .wartetAufWLAN(r) }
        beginne(r)
        defer { ende(r) }
        let temp: URL
        do {
            temp = try await quelle.exportiere(r, iCloud: stand.iCloudErlaubt)
        } catch is CancellationError {
            return .abgebrochen(r)
        } catch {
            return .nichtLesbar(r, (error as? FotoFehler)?.nutzerText ?? "nicht lesbar")
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        if Task.isCancelled { return .abgebrochen(r) }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        do {
            var anfrage = try client.fotoHochladenAnfrage(kennung: r.kennung, ressource: r.name, aufnahme: r.aufnahme, dateiname: r.dateiname)
            anfrage.allowsCellularAccess = !(stand.wlanNoetig || r.art.istVideo)
            try await sender.sende(datei: temp, anfrage: anfrage)
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

    var nutzerText: String {
        switch self {
        case .speicherKnapp: return "zu wenig freier Speicher am Handy"
        case .nichtGefunden: return "nicht mehr in der Mediathek"
        case .nurInICloud: return "liegt nur in iCloud, und das Laden von iCloud ist aus"
        }
    }
}
