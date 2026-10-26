import Foundation
import Observation

/// Zustand eines Ordners im Dateien-Tab: Liste, Laden, Hochladen, Papierkorb. Jeder Ordner auf dem Navigationsstapel hat sein eigenes Modell.
/// Alles geht über `HeimClient`; in Demo und Test-Host nie ins Netz.
@MainActor @Observable
final class DateienModell {
    enum Zustand: Equatable {
        case laedt, bereit
        /// `offline`: der PC antwortet nicht (aus, kein Tailscale); die letzte Liste bleibt sichtbar.
        case fehler(String, offline: Bool)
    }

    /// Wo dieses Modell steht, relativ zur Wurzel (`[]` = Wurzel).
    let ordner: [String]
    private(set) var eintraege: [DateiInfo] = []
    private(set) var zustand = Zustand.laedt
    /// Ergebnis des letzten Hochladens oder Papierkorbs, einmal anzeigen.
    private(set) var meldung: String?
    private(set) var meldungIstFehler = false
    private(set) var uebertragungen = 0

    let istDemo: Bool
    private let holeClient: @MainActor () throws -> HeimClient
    private var ladeNummer = 0

    init(ordner: [String] = [], istDemo: Bool, holeClient: @escaping @MainActor () throws -> HeimClient) {
        self.ordner = ordner
        self.istDemo = istDemo
        self.holeClient = holeClient
        if istDemo {
            eintraege = DateienDemo.liste(ordner: ordner)
            zustand = .bereit
        }
    }

    var pfad: String { ordner.joined(separator: "/") }

    // MARK: Liste

    func lade() async {
        guard !istDemo else { return }
        ladeNummer += 1
        let nr = ladeNummer
        if eintraege.isEmpty { zustand = .laedt }
        do {
            let liste = try await holeClient().dateienListe(pfad: pfad)
            guard nr == ladeNummer else { return }
            eintraege = liste
            zustand = .bereit
        } catch {
            guard nr == ladeNummer, !Self.istAbbruch(error) else { return }
            zustand = Self.fehlerZustand(error)
        }
    }

    func quittiereMeldung() { meldung = nil }

    /// Ein Fehler aus der Oberfläche (Datei laden, Teilen), einmal anzeigen.
    func meldeFehler(_ error: Error) {
        meldung = (error as? HeimFehler)?.nutzerText ?? "Das hat nicht geklappt."
        meldungIstFehler = true
    }

    // MARK: Laden zur Vorschau

    /// Lädt die Datei in den Cache und gibt ihre Adresse zurück (Vorschau, Teilen). Wirft `HeimFehler`.
    func laden(pfad: String, name: String) async throws -> URL {
        let client = try holeClient()
        let ziel = VorschauCache.ziel(wurzel: VorschauCache.wurzel, pfad: pfad, name: name)
        try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await client.dateiLaden(pfad: pfad, nach: ziel)
        return ziel
    }

    func laden(_ e: DateiInfo) async throws -> URL {
        try await laden(pfad: DateiPfad.zusammen(ordner, e.name), name: e.name)
    }

    // MARK: Hochladen

    /// Lädt lokale Dateien in diesen Ordner. Die Dateien werden danach nicht angefasst (Aufrufer räumt Temp-Dateien auf).
    func hochladen(_ dateien: [(url: URL, name: String)]) async {
        guard !istDemo, !dateien.isEmpty else { return }
        uebertragungen += dateien.count
        defer { uebertragungen -= dateien.count }
        var ok = 0
        var letzterFehler: String?
        do {
            let client = try holeClient()
            for d in dateien {
                do {
                    try await client.dateiHochladen(pfad: DateiPfad.zusammen(ordner, d.name), von: d.url)
                    ok += 1
                } catch let f as HeimFehler where f.istNetzproblem || f == .nichtBerechtigt || f == .speicherVoll {
                    letzterFehler = f.nutzerText
                    break
                } catch {
                    letzterFehler = (error as? HeimFehler)?.nutzerText ?? "„\(d.name)“ konnte nicht hochgeladen werden."
                }
            }
        } catch {
            letzterFehler = (error as? HeimFehler)?.nutzerText ?? HeimFehler.nichtErreichbar.nutzerText
        }
        melde(ok: ok, von: dateien.count, fehler: letzterFehler)
        if ok > 0 { await lade() }
    }

    nonisolated static func ergebnisText(ok: Int, von: Int, fehler: String?) -> (text: String, istFehler: Bool) {
        if let fehler { return (ok > 0 ? "\(ok) von \(von) hochgeladen. \(fehler)" : fehler, true) }
        return (ok == 1 ? "1 Datei hochgeladen." : "\(ok) Dateien hochgeladen.", false)
    }

    private func melde(ok: Int, von: Int, fehler: String?) {
        let e = Self.ergebnisText(ok: ok, von: von, fehler: fehler)
        meldung = e.text
        meldungIstFehler = e.istFehler
    }

    // MARK: Papierkorb

    /// Legt am PC eine Datei oder einen Ordner in den Papierkorb (nie endgültig löschen). true bei Erfolg.
    /// `pfad` ist der ganze Pfad (Treffer der Suche liegen nicht in diesem Ordner).
    @discardableResult
    func inPapierkorb(pfad: String, name: String) async -> Bool {
        guard !istDemo else { return false }
        do {
            try await holeClient().inPapierkorb(pfad: pfad)
            meldung = "„\(name)“ liegt jetzt im Papierkorb am PC."
            meldungIstFehler = false
            await lade()
            return true
        } catch {
            meldung = (error as? HeimFehler)?.nutzerText ?? "Das hat nicht geklappt."
            meldungIstFehler = true
            return false
        }
    }

    @discardableResult
    func inPapierkorb(_ e: DateiInfo) async -> Bool {
        await inPapierkorb(pfad: DateiPfad.zusammen(ordner, e.name), name: e.name)
    }

    // MARK: Hilfen

    static func fehlerZustand(_ error: Error) -> Zustand {
        guard let f = error as? HeimFehler else { return .fehler(HeimFehler.nichtErreichbar.nutzerText, offline: true) }
        return .fehler(f.nutzerText, offline: f.istNetzproblem)
    }

    /// Ein abgebrochener Aufruf (neuer Aufruf, Ansicht weg) ist kein Fehler und zeigt nie "offline".
    nonisolated static func istAbbruch(_ error: Error) -> Bool {
        error is CancellationError || (error as? HeimFehler) == .abgebrochen
    }
}

/// Die Suche eines Ordners: wartet nach dem letzten Tastendruck kurz (`entprellung`), bricht ältere Anfragen ab und merkt nur die jüngste Antwort.
@MainActor @Observable
final class DateienSucheModell {
    enum Zustand: Equatable {
        case leer, laedt, bereit
        case fehler(String)
    }

    private(set) var treffer: [SuchTreffer] = []
    private(set) var zustand = Zustand.leer

    private let holeClient: @MainActor () throws -> HeimClient
    private let demo: [SuchTreffer]?
    private let entprellung: Duration
    @ObservationIgnored private var aufgabe: Task<Void, Never>?
    @ObservationIgnored private var letzte: (text: String, pfad: String)?

    /// `demo`: in Demo und Screenshots wird in dieser Liste gesucht, nie im Netz.
    init(demo: [SuchTreffer]? = nil, entprellung: Duration = .milliseconds(300), holeClient: @escaping @MainActor () throws -> HeimClient) {
        self.demo = demo
        self.entprellung = entprellung
        self.holeClient = holeClient
    }

    func suche(text: String, pfad: String) {
        aufgabe?.cancel()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        letzte = (q, pfad)
        guard !q.isEmpty else {
            treffer = []
            zustand = .leer
            return
        }
        if let demo {
            let w = DateiSuche.woerter(q)
            treffer = demo.filter { t in
                (pfad.isEmpty || t.pfad.hasPrefix(pfad + "/")) && DateiSuche.passt(name: t.name, woerter: w)
            }
            zustand = .bereit
            return
        }
        zustand = .laedt
        let wartezeit = entprellung
        aufgabe = Task { [self] in
            do {
                try await Task.sleep(for: wartezeit)
                let liste = try await holeClient().dateienSuche(q: q, pfad: pfad)
                guard !Task.isCancelled else { return }
                treffer = liste
                zustand = .bereit
            } catch {
                guard !Task.isCancelled, !DateienModell.istAbbruch(error) else { return }
                zustand = .fehler((error as? HeimFehler)?.nutzerText ?? HeimFehler.nichtErreichbar.nutzerText)
            }
        }
    }

    /// Dieselbe Suche noch einmal (nach dem Papierkorb), ohne Wartezeit zu verlieren.
    func wiederhole() {
        if let letzte { suche(text: letzte.text, pfad: letzte.pfad) }
    }

    /// Wartet, bis die laufende Suche fertig ist (Tests).
    func warteAufEnde() async { await aufgabe?.value }
}

/// Erfundene Dateien für Screenshots (`-heimherzDemo YES`) in derselben Ordnung wie am PC: Bürokratie, Projekte, Weitere, dazu Aboherz in der Wurzel.
enum DateienDemo {
    private static func vor(_ tage: Double) -> String { Zeit.iso(Date(timeIntervalSinceNow: -tage * 86_400)) }

    private static func ordner(_ name: String, _ anzahl: Int, _ tage: Double) -> DateiInfo {
        DateiInfo(name: name, ordner: true, groesse: 0, geaendert: vor(tage), anzahl: anzahl)
    }

    private static func datei(_ name: String, _ groesse: Int64, _ tage: Double) -> DateiInfo {
        DateiInfo(name: name, ordner: false, groesse: groesse, geaendert: vor(tage))
    }

    /// Inhalt eines Ordners; `[]` ist die Wurzel. Unbekannte Ordner sind leer.
    static func liste(ordner pfad: [String]) -> [DateiInfo] {
        switch pfad.joined(separator: "/") {
        case "":
            return [ordner("Bürokratie", 9, 2), ordner("Projekte", 3, 6), ordner("Weitere", 3, 9), ordner("Aboherz", 2, 1)]
        case "Bürokratie":
            return [
                ordner("4 Geld", 6, 2), ordner("2 Jobcenter", 55, 3), ordner("_Archiv", 7, 30),
                ordner("1 Ausweise", 5, 40), ordner("6 Gesundheit", 3, 12), ordner("7 Schule & Arbeit", 8, 20),
                ordner("5 Wohnen", 5, 5), ordner("3 Behörden", 7, 8), ordner("_Alt vor 17.09.2026", 40, 70),
            ]
        case "Projekte":
            return [ordner("Coding", 14, 1), ordner("Money Machine – Claude Business", 9, 4), ordner("Videos", 3, 70)]
        case "Weitere":
            return [ordner("Fitness", 8, 9), ordner("Sonstiges", 11, 3), ordner("iCloud Drive", 24, 30)]
        case "Bürokratie/4 Geld":
            return [
                datei("Rechnung Internet.pdf", 120_000, 6), datei("Rechnung Strom Oktober.pdf", 96_000, 3),
                datei("Rechnung Versicherung.pdf", 210_000, 15), datei("Kündigung Fitnessstudio.pdf", 64_000, 50),
                datei("Budget 2026.xlsx", 31_000, 1), datei("Steuerbescheid 2025.pdf", 340_000, 90),
            ]
        case "Bürokratie/2 Jobcenter":
            return [
                datei("Bescheid Oktober.pdf", 182_000, 4), datei("Mietvertrag.pdf", 482_000, 5),
                datei("Weiterbewilligungsantrag.pdf", 240_000, 20), datei("Notizen.txt", 1_200, 8),
            ]
        case "Weitere/Sonstiges":
            return [
                datei("Urlaub Strand.jpg", 3_400_000, 40), datei("Grillabend.jpg", 2_100_000, 12),
                datei("Wanderung Film.mp4", 58_000_000, 20), datei("Notizen.txt", 1_200, 8),
            ]
        default:
            return []
        }
    }

    /// Die Startseite der Demo, gebaut wie am PC aus Wurzel und Kategorie-Ordnern.
    static let abschnitte: [StartAbschnitt] = DateienStart.bilde(
        wurzel: liste(ordner: []),
        inhalte: Dictionary(uniqueKeysWithValues: DateiKategorie.allCases.map { ($0, liste(ordner: [$0.ordnerName])) })
    )

    /// Alles, was die Demo-Suche kennt (Pfade relativ zur Wurzel): die Ordner der Startseite, dann die Dateien der Demo-Ordner.
    static let treffer: [SuchTreffer] = {
        func als(_ e: DateiInfo, _ pfad: String) -> SuchTreffer { SuchTreffer(pfad: pfad, name: e.name, ordner: e.ordner, groesse: e.groesse, geaendert: e.geaendert) }
        let ordnerZeilen = abschnitte.flatMap(\.zeilen).map { als($0.info, $0.pfad) }
        let dateien = ["Bürokratie/4 Geld", "Bürokratie/2 Jobcenter", "Weitere/Sonstiges"].flatMap { pfad in
            liste(ordner: DateiPfad.teile(pfad)).map { als($0, "\(pfad)/\($0.name)") }
        }
        return ordnerZeilen + dateien
    }()
}
