import Foundation

/// Die Fotos-Seite des Handys (PhotoKit); Attrappe im Test.
protocol FotoQuelle: Sendable {
    /// Zählt und plant (`FotoPlan.plane` über alle Assets, neueste zuerst).
    func plane(stand: FotoStand) async -> FotoPlan.Ergebnis
    /// Schreibt die Datei in eine Temp-Datei und gibt deren Adresse zurück. `fortschritt` 0...1 (iCloud-Original wird dabei geladen).
    func exportiere(_ r: FotoRessource, fortschritt: @escaping @Sendable (Double) -> Void) async throws -> URL
}

/// Die Sende-Seite (Hintergrund-URLSession); Attrappe im Test.
protocol FotoSender: Sendable {
    /// Schickt die Datei und kehrt nach dem Ende des Transfers zurück. Wirft `HeimFehler`.
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
    /// 0...1 über alle offenen Dateien dieses Laufs.
    var fortschritt: Double?
    var laeuft = false
}

/// Ein Abgleich: Liste vom PC holen, zählen, jede offene Datei exportieren und senden. Läuft in der App im Vordergrund;
/// was schon unterwegs ist, setzt die Hintergrund-URLSession auch bei gesperrtem Handy fort.
/// Der Server ist die Wahrheit: schlägt hier etwas fehl, steht die Datei beim nächsten Lauf wieder in der Liste.
actor FotoAbgleich {
    private let client: HeimClient
    private let quelle: any FotoQuelle
    private let sender: any FotoSender
    private let netz: any Netzart
    private let ablage: FotoStandAblage
    private let melde: @Sendable (FotoAnzeige) -> Void
    private let jetzt: @Sendable () -> Date
    private let gleichzeitig: Int

    private var stand = FotoStand()
    private var anzeige = FotoAnzeige()
    private var erledigt = 0
    private var gesamtOffen = 0
    private var gescheitert = 0
    private var exportFehler: String?
    private var wartetAufWLAN = 0
    private var abbruch: HeimFehler?

    init(client: HeimClient, quelle: any FotoQuelle, sender: any FotoSender, netz: any Netzart, ablage: FotoStandAblage,
         gleichzeitig: Int = 2, jetzt: @escaping @Sendable () -> Date = { Date() }, melde: @escaping @Sendable (FotoAnzeige) -> Void) {
        self.client = client
        self.quelle = quelle
        self.sender = sender
        self.netz = netz
        self.ablage = ablage
        self.gleichzeitig = max(1, gleichzeitig)
        self.jetzt = jetzt
        self.melde = melde
    }

    private func zeige(schritt: String?, laeuft: Bool = true) {
        anzeige.schritt = schritt
        anzeige.laeuft = laeuft
        anzeige.fortschritt = gesamtOffen > 0 ? Double(erledigt + gescheitert + wartetAufWLAN) / Double(gesamtOffen) : nil
        melde(anzeige)
    }

    func abgleichen() async {
        stand = ablage.lade()
        erledigt = 0; gescheitert = 0; wartetAufWLAN = 0; gesamtOffen = 0; exportFehler = nil; abbruch = nil
        zeige(schritt: "Frage den PC, was schon da ist …")
        do {
            stand.uebernimm(bekannt: try await client.fotosBekannt())
        } catch {
            stand.fehler = (error as? HeimFehler)?.nutzerText ?? HeimFehler.nichtErreichbar.nutzerText
            ablage.speichere(stand)
            anzeige.zahlen = stand.gesamt.map { FotoZahlen(gesamt: $0, amPC: stand.fertig.count) } ?? anzeige.zahlen
            zeige(schritt: nil, laeuft: false)
            return
        }
        zeige(schritt: "Zähle die Fotos …")
        let plan = await quelle.plane(stand: stand)
        stand.fertig.formUnion(plan.neuFertig)
        stand.raeumeAuf()
        stand.gesamt = plan.zahlen.gesamt
        ablage.speichere(stand)
        anzeige.zahlen = plan.zahlen
        gesamtOffen = plan.offen.count
        zeige(schritt: plan.offen.isEmpty ? nil : "Noch \(plan.offen.count.formatted()) offen …")

        await sendeAlle(plan.offen)

        // Zum Schluss neu zählen: was jetzt vollständig am PC liegt, kommt in `fertig`.
        let danach = await quelle.plane(stand: stand)
        stand.fertig.formUnion(danach.neuFertig)
        stand.raeumeAuf()
        stand.gesamt = danach.zahlen.gesamt
        stand.fehler = abschlussText()
        ablage.speichere(stand)
        anzeige.zahlen = danach.zahlen
        gesamtOffen = 0
        zeige(schritt: nil, laeuft: false)
    }

    private func abschlussText() -> String? {
        if let abbruch { return abbruch.nutzerText }
        if Task.isCancelled { return "Abgebrochen. Beim nächsten Abgleich geht es weiter." }
        var teile: [String] = []
        if gescheitert > 0 {
            let grund = exportFehler.map { " (\($0))" } ?? ""
            teile.append(gescheitert == 1 ? "1 Datei konnte nicht übertragen werden\(grund)." : "\(gescheitert.formatted()) Dateien konnten nicht übertragen werden\(grund).")
        }
        if wartetAufWLAN > 0 { teile.append(wartetAufWLAN == 1 ? "1 Datei wartet auf WLAN." : "\(wartetAufWLAN.formatted()) Dateien warten auf WLAN.") }
        return teile.isEmpty ? nil : teile.joined(separator: " ")
    }

    // MARK: Senden

    private enum Ausgang: Sendable {
        case gesendet, wartetAufWLAN, nichtLesbar(String), nichtUebertragen, stop(HeimFehler), abgebrochen
    }

    private func sendeAlle(_ liste: [FotoRessource]) async {
        var naechste = liste.makeIterator()
        await withTaskGroup(of: Ausgang.self) { gruppe in
            var laufend = 0
            while true {
                while laufend < gleichzeitig, abbruch == nil, !Task.isCancelled, let r = naechste.next() {
                    gruppe.addTask { await self.bearbeite(r) }
                    laufend += 1
                }
                guard laufend > 0, let ausgang = await gruppe.next() else { break }
                laufend -= 1
                verbuche(ausgang)
                if abbruch != nil { gruppe.cancelAll() }
            }
        }
    }

    private func verbuche(_ a: Ausgang) {
        switch a {
        case .gesendet:
            erledigt += 1
            if erledigt % 25 == 0 { ablage.speichere(stand) }
        case .wartetAufWLAN: wartetAufWLAN += 1
        case .nichtLesbar(let grund): gescheitert += 1; exportFehler = grund
        case .nichtUebertragen: gescheitert += 1
        case .stop(let f): abbruch = f
        case .abgebrochen: break
        }
        zeige(schritt: "Noch \(max(0, gesamtOffen - erledigt - gescheitert - wartetAufWLAN).formatted()) offen …")
    }

    private func bearbeite(_ r: FotoRessource) async -> Ausgang {
        if (stand.wlanNoetig || r.art.istVideo), !(await netz.istWLAN()) { return .wartetAufWLAN }
        let temp: URL
        do {
            temp = try await quelle.exportiere(r) { _ in }
        } catch is CancellationError {
            return .abgebrochen
        } catch {
            return .nichtLesbar((error as? FotoFehler)?.nutzerText ?? "nicht lesbar")
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            var anfrage = try client.fotoHochladenAnfrage(kennung: r.kennung, ressource: r.name, aufnahme: r.aufnahme, dateiname: r.dateiname)
            anfrage.allowsCellularAccess = !(stand.wlanNoetig || r.art.istVideo)
            try await sender.sende(datei: temp, anfrage: anfrage)
            stand.teil.insert(r.schluessel)
            stand.letzteUebertragung = jetzt()
            return .gesendet
        } catch HeimFehler.abgebrochen {
            return .abgebrochen
        } catch let f as HeimFehler where f.istNetzproblem || f == .nichtBerechtigt || f == .nichtGekoppelt {
            return .stop(f)
        } catch {
            return .nichtUebertragen
        }
    }
}

/// Fehler beim Lesen aus der Mediathek.
enum FotoFehler: Error, Equatable {
    case speicherKnapp
    case nichtGefunden

    var nutzerText: String {
        switch self {
        case .speicherKnapp: return "zu wenig freier Speicher am Handy"
        case .nichtGefunden: return "nicht mehr in der Mediathek"
        }
    }
}
