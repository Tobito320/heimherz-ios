import CryptoKit
import Foundation
import Observation

/// Der Klartext-Tresor der laufenden App, nur im Speicher (SPEC 9). Beim Sperren der App wird alles geleert (`sperren()`).
/// Öffnen: Schlüssel K aus dem Schlüsselbund (Face ID), lokaler Stand sofort, danach Abgleich mit dem PC.
/// Jede Änderung wird erst lokal verschlüsselt gespeichert (geht auch ohne PC nicht verloren) und dann abgeglichen.
@MainActor @Observable
final class TresorStore {
    enum Zustand: Equatable {
        case leer
        case laedt
        case bereit
        case fehler(String)
    }

    private(set) var zustand: Zustand = .leer
    private(set) var tresor: Tresor?
    /// Wann der PC zuletzt erfolgreich abgeglichen wurde (auch nach Neustart der App bekannt).
    private(set) var zuletzt: Date?
    /// Gesetzt, wenn der PC beim letzten Abgleich nicht erreichbar war: kein Fehler, die Änderungen warten.
    private(set) var offlineText: String?
    /// Ein Fehler beim Abgleich, der kein Netzproblem ist (z. B. PC kennt das Handy nicht mehr).
    private(set) var abgleichFehler: String?
    private(set) var gleichtAb = false

    /// Ids, deren Passwort laut Leck-Prüfung in einem Datenleck steckt (nur Einträge mit passendem Stand, nur bei eingeschalteter Einstellung).
    /// Gespeichert statt berechnet, damit die Kachel "Sicherheit" sich ändert, sobald ein Ergebnis kommt.
    private(set) var leckIds: Set<String> = []

    private let umgebung: AppUmgebung
    private let identitaetenSetzen: @Sendable (Tresor) async -> Void
    private let spotlightSetzen: @Sendable (Tresor) async -> Void
    private let einstellungen: GeteilteEinstellungen
    private let leckSpeicher: LeckSpeicher
    /// nil = keine Netzabfrage (Tests ohne eigene Attrappe, Demo).
    private let leckAbfrage: LeckAbfrage?
    private let jetzt: @Sendable () -> Date
    private let merker: UserDefaults
    private var schluessel: SymmetricKey?
    private var abgleichNoetig = false
    private var abgleichTask: Task<Void, Never>?
    private var identitaetenTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?
    private var leckTask: Task<Void, Never>?
    /// Zählt Sperren hoch: Ergebnisse von Aufgaben, die vor einer Sperre starteten, werden verworfen (kein Klartext nach dem Sperren).
    private var sperrZaehler = 0

    static let merkerSchluessel = "heimherz.zuletztAbgeglichen"

    init(umgebung: AppUmgebung,
         identitaeten: (@Sendable (Tresor) async -> Void)? = nil,
         spotlight: (@Sendable (Tresor) async -> Void)? = nil,
         einstellungen: GeteilteEinstellungen = GeteilteEinstellungen(),
         leckSpeicher: LeckSpeicher = LeckSpeicher(),
         leckAbfrage: LeckAbfrage? = AppUmgebung.istTestHost ? nil : LeckAbfrage(),
         jetzt: @escaping @Sendable () -> Date = { Date() },
         merker: UserDefaults = .standard) {
        self.umgebung = umgebung
        self.identitaetenSetzen = identitaeten ?? Self.setzeImSystem
        self.spotlightSetzen = spotlight ?? Self.setzeSpotlight
        self.einstellungen = einstellungen
        self.leckSpeicher = leckSpeicher
        self.leckAbfrage = leckAbfrage
        self.jetzt = jetzt
        self.merker = merker
        let sekunden = merker.double(forKey: Self.merkerSchluessel)
        self.zuletzt = sekunden > 0 ? Date(timeIntervalSince1970: sekunden) : nil
    }

    // MARK: Lesen

    var eintraege: [Eintrag] { tresor?.lebendige ?? [] }

    func eintrag(_ id: String) -> Eintrag? {
        eintraege.first { $0.id == id }
    }

    /// Der Papierkorb ("Gelöscht"): Grabsteine mit Inhalt, höchstens 30 Tage alt.
    var geloeschte: [Eintrag] {
        guard let t = tresor else { return [] }
        return PasswoerterLogik.eintraege(.geloescht, in: t, jetzt: jetzt())
    }

    func geloeschterEintrag(_ id: String) -> Eintrag? {
        geloeschte.first { $0.id == id }
    }

    /// Die Zahlen der Kacheln der Startseite.
    var zaehler: [PasswoerterKategorie: Int] {
        guard let t = tresor else { return [:] }
        return PasswoerterLogik.zaehler(in: t, jetzt: jetzt(), lecks: leckIds)
    }

    /// Einmalcodes sind erst nach Face ID oder Code sichtbar, einmal je Öffnen der App (`sperren()` setzt es zurück).
    private(set) var codesFreigegeben = false

    func gebeCodesFrei() { codesFreigegeben = true }

    // MARK: Öffnen und Sperren

    /// Lädt K (Face ID), zeigt den lokalen Stand und gleicht danach mit dem PC ab. Ohne Netz bleibt der lokale Stand.
    func oeffnen() async {
        guard zustand != .laedt else { return }
        #if DEBUG
        if umgebung.istDemo {
            tresor = Self.demoTresor
            zuletzt = jetzt()
            codesFreigegeben = true   // Demo: nie Face ID, die Screenshots sollen Codes zeigen
            leckIds = Self.demoLecks   // Demo: nie Netz, ein erfundener Treffer für den Screenshot
            zustand = .bereit
            return
        }
        #endif
        guard umgebung.istGekoppelt, !umgebung.istDemo else { return }
        if schluessel == nil || tresor == nil {
            zustand = .laedt
            let zaehler = sperrZaehler
            do {
                guard let k = try await umgebung.bund.ladeSchluessel(kontext: umgebung.sperre.kontext) else {
                    zustand = .fehler("Auf diesem Handy liegt kein Tresorschlüssel. Bitte neu koppeln (Tab Einstellungen).")
                    return
                }
                let lokal = try await umgebung.tresorDienst().lokal(schluessel: k) ?? Tresor()
                guard zaehler == sperrZaehler else { return }
                schluessel = k
                tresor = lokal
                zustand = .bereit
                tresorStandGeaendert(lokal)
            } catch {
                if zaehler == sperrZaehler { zustand = .fehler(Self.text(error)) }
                return
            }
        }
        await abgleichen()
        await bereinigeGeloeschte()
    }

    /// Grabsteine, die länger als 30 Tage im Papierkorb liegen, verlieren ihre Felder (sonst blieben sie bis zum 90. Tag unsichtbar lesbar).
    private func bereinigeGeloeschte() async {
        guard let t = tresor, let bereinigt = PasswoerterLogik.bereinige(t, jetzt: jetzt()) else { return }
        await aendere { $0 = bereinigt }
    }

    /// App gesperrt, entkoppelt oder im Hintergrund zu lange: Klartext und Schlüssel aus dem Speicher.
    func sperren() {
        sperrZaehler += 1
        abgleichTask?.cancel()
        abgleichTask = nil
        tresor = nil
        schluessel = nil
        codesFreigegeben = false
        leckTask?.cancel()
        leckTask = nil
        leckIds = []
        zustand = .leer
        offlineText = nil
        abgleichFehler = nil
    }

    // MARK: Abgleich

    /// `GET` → entschlüsseln → zusammenführen → `PUT` über den `TresorDienst`. Läuft schon einer, wird danach noch einmal abgeglichen.
    func abgleichen() async {
        guard schluessel != nil, tresor != nil else { return }
        if gleichtAb {
            abgleichNoetig = true
            return
        }
        gleichtAb = true
        defer { gleichtAb = false }
        repeat {
            abgleichNoetig = false
            await uebernehmeDatei()
            guard let k = schluessel, let stand = tresor else { return }
            let zaehler = sperrZaehler
            do {
                let ergebnis = try await umgebung.tresorDienst().abgleichen(lokal: stand, schluessel: k)
                guard zaehler == sperrZaehler, let aktuell = tresor else { return }   // währenddessen gesperrt
                switch ergebnis {
                case .abgeglichen(let t, _):
                    tresor = Zusammenfuehren.zusammenfuehren(aktuell, t, jetzt: jetzt())
                    offlineText = nil
                    let wann = jetzt()
                    zuletzt = wann
                    merker.set(wann.timeIntervalSince1970, forKey: Self.merkerSchluessel)
                case .nurLokal(let t, _):
                    tresor = Zusammenfuehren.zusammenfuehren(aktuell, t, jetzt: jetzt())
                    offlineText = "Der PC ist gerade nicht erreichbar. Alles geht weiter, Änderungen warten bis zum nächsten Abgleich."
                }
                abgleichFehler = nil
                if let neu = tresor { tresorStandGeaendert(neu) }
            } catch {
                guard zaehler == sperrZaehler else { return }
                abgleichFehler = Self.text(error)
            }
        } while abgleichNoetig
    }

    /// Wartet auf einen im Hintergrund gestarteten Abgleich (Tests).
    func warteAufAbgleich() async {
        await abgleichTask?.value
    }

    private func starteAbgleich() {
        abgleichTask = Task { [weak self] in await self?.abgleichen() }
    }

    // MARK: Ändern

    /// Neuer oder geänderter Eintrag. Der Zeitstempel `geaendert` wird hier gesetzt.
    func speichere(_ eintrag: Eintrag) async {
        var e = eintrag
        e.geaendert = Zeit.iso(jetzt())
        await aendere { tresor in
            if let i = tresor.eintraege.firstIndex(where: { $0.id == e.id }) { tresor.eintraege[i] = e } else { tresor.eintraege.append(e) }
        }
    }

    /// Löschen als Grabstein mit Feldern ("Gelöscht", 30 Tage wiederherstellbar), damit die Löschung auf allen Geräten ankommt (SPEC 5).
    func loesche(id: String) async {
        await loesche(ids: [id])
    }

    /// Mehrere auf einmal: ein Speichern und ein Abgleich (Auswählen in der Liste).
    func loesche(ids: [String]) async {
        await aendereEintraege(ids) { $0.alsGrabstein(geaendert: $1) }
    }

    /// Aus "Gelöscht" zurück in die Liste, mit neuem Zeitstempel, damit der Merge auf allen Geräten die Wiederherstellung nimmt.
    func stelleWiederHer(ids: [String]) async {
        await aendereEintraege(ids) { $0.geloescht ? $0.wiederhergestellt(geaendert: $1) : $0 }
    }

    /// Leert die Felder sofort (der Grabstein bleibt, damit die Löschung ankommt). Am PC bleiben alte Fassungen im Verlauf des Tresors.
    func loescheEndgueltig(ids: [String]) async {
        await aendereEintraege(ids) { $0.endgueltigGeloescht(geaendert: $1) }
    }

    private func aendereEintraege(_ ids: [String], _ umwandeln: (Eintrag, String) -> Eintrag) async {
        let stempel = Zeit.iso(jetzt())
        let menge = Set(ids)
        await aendere { tresor in
            for i in tresor.eintraege.indices where menge.contains(tresor.eintraege[i].id) { tresor.eintraege[i] = umwandeln(tresor.eintraege[i], stempel) }
        }
    }

    func setzeFavorit(id: String, _ wert: Bool) async {
        guard var e = eintrag(id) else { return }
        e.favorit = wert
        await speichere(e)
    }

    /// Import aus Apple Passwörter: mischt die Konten ein, speichert einmal lokal und gleicht sofort mit dem PC ab. Nur Zahlen kommen zurück.
    func importiere(_ paket: ImportPaket) async -> ImportZaehler {
        var zaehler = ImportZaehler(uebersprungen: paket.uebersprungen)
        let stand = jetzt()
        await aendere { tresor in
            let r = ImportAbbildung.einarbeiten(tresor, paket.konten, uebersprungenVorher: paket.uebersprungen, jetzt: stand)
            tresor = r.tresor
            zaehler = r.zaehler
        }
        await warteAufAbgleich()
        return zaehler
    }

    /// Die AutoFill-Erweiterung kann den verschlüsselten Cache geändert haben, während die App offen war (neues Passwort aus Safari):
    /// vor jedem Schreiben und Abgleichen den Stand der Datei einmischen, sonst würde er überschrieben.
    private func uebernehmeDatei() async {
        guard let k = schluessel, tresor != nil else { return }
        let zaehler = sperrZaehler
        guard let datei = try? await umgebung.tresorDienst().lokal(schluessel: k), zaehler == sperrZaehler, let stand = tresor else { return }
        let gemischt = Zusammenfuehren.zusammenfuehren(stand, datei, jetzt: jetzt())
        if gemischt != stand { tresor = gemischt }
    }

    private func aendere(_ aenderung: (inout Tresor) -> Void) async {
        await uebernehmeDatei()
        guard var t = tresor, let k = schluessel else { return }
        aenderung(&t)
        tresor = t
        do {
            try await umgebung.tresorDienst().speichereLokal(t, schluessel: k)
            abgleichFehler = nil
        } catch {
            abgleichFehler = "Speichern auf dem Handy ist fehlgeschlagen: \(Self.text(error))"
            return
        }
        tresorStandGeaendert(t)
        starteAbgleich()
    }

    /// Nach jedem neuen Stand (Öffnen, Abgleich, Änderung): Identitäten für AutoFill, Spotlight-Index und Leck-Prüfung nachziehen.
    private func tresorStandGeaendert(_ t: Tresor) {
        guard !umgebung.istDemo else { return }
        let setzen = identitaetenSetzen
        let vorher = identitaetenTask
        // Nacheinander, damit ein älterer Stand nie einen neueren im System überschreibt.
        identitaetenTask = Task {
            await vorher?.value
            await setzen(t)
        }
        let spotlight = spotlightSetzen
        let vorherSpotlight = spotlightTask
        spotlightTask = Task {
            await vorherSpotlight?.value
            await spotlight(t)
        }
        starteLeckPruefung(t)
    }

    /// Wartet, bis die Identitäten im System gesetzt sind (Tests).
    func warteAufIdentitaeten() async {
        await identitaetenTask?.value
    }

    /// Wartet, bis der Spotlight-Index gesetzt ist (Tests).
    func warteAufSpotlight() async {
        await spotlightTask?.value
    }

    private nonisolated static func setzeImSystem(_ tresor: Tresor) async {
        _ = await AutoFillIdentitaeten.setze(tresor, nutzung: Nutzung().anzahl)
    }

    private nonisolated static func setzeSpotlight(_ tresor: Tresor) async {
        await SpotlightIndex.setze(SpotlightIndex.eintraege(aus: tresor))
    }

    // MARK: Datenlecks

    /// Prüft Passwörter gegen Pwned Passwords, aber nur mit eingeschalteter Einstellung, höchstens einmal am Tag alle und sonst nur neue oder
    /// geänderte Einträge (`LeckPruefung.faellig`). Gespeichert wird nur "gefunden ja/nein" je Eintrag. Ohne Netz ändert sich nichts.
    private func starteLeckPruefung(_ t: Tresor) {
        guard einstellungen.leckPruefung else {
            leckIds = []   // aus: keine Abfrage, kein Abschnitt, keine Zählung
            return
        }
        let staende = leckSpeicher.staende
        leckIds = LeckPruefung.lecks(t.lebendige, staende: staende)
        guard let abfrage = leckAbfrage, leckTask == nil else { return }
        let stand = jetzt()
        let faellig = LeckPruefung.faellig(t.lebendige, staende: staende, letzterLauf: leckSpeicher.letzterLauf, jetzt: stand)
        guard !faellig.eintraege.isEmpty else { return }
        let kandidaten = faellig.eintraege.map { (id: $0.id, passwort: $0.passwort) }
        let stempel = Dictionary(faellig.eintraege.map { ($0.id, $0.geaendert) }, uniquingKeysWith: { a, _ in a })
        let zaehler = sperrZaehler
        leckTask = Task { [weak self] in
            let lauf = await LeckPruefung.pruefe(kandidaten, abfrage: abfrage)
            guard let self, zaehler == self.sperrZaehler, !Task.isCancelled else { return }
            self.leckTask = nil
            guard !lauf.ergebnisse.isEmpty || lauf.vollstaendig else { return }
            var neu = staende
            for (id, gefunden) in lauf.ergebnisse {
                if let geaendert = stempel[id] { neu[id] = LeckStand(geaendert: geaendert, gefunden: gefunden) }
            }
            // Einträge, die es nicht mehr gibt, fliegen raus (klein halten, nichts Altes aufheben).
            let lebendig = Set(self.eintraege.map(\.id))
            neu = neu.filter { lebendig.contains($0.key) }
            self.leckSpeicher.staende = neu
            if lauf.vollstaendig, faellig.alle { self.leckSpeicher.letzterLauf = stand }
            self.leckIds = LeckPruefung.lecks(self.eintraege, staende: neu)
            // Währenddessen geänderte Einträge sofort nachholen; nur nach einem sauberen Lauf, sonst hämmert ein fehlendes Netz im Kreis.
            if lauf.vollstaendig, let aktuell = self.tresor { self.starteLeckPruefung(aktuell) }
        }
    }

    /// Wartet auf eine laufende Leck-Prüfung (Tests).
    func warteAufLeckPruefung() async {
        await leckTask?.value
    }

    nonisolated static func text(_ fehler: Error) -> String {
        FehlerText.von(fehler)
    }
}
