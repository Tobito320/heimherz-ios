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

/// Erfundene Dateien für Screenshots (`-heimherzDemo YES`): Ordner mit Anzahl, PDFs, Bilder, Videos.
enum DateienDemo {
    private static func vor(_ tage: Double) -> String { Zeit.iso(Date(timeIntervalSinceNow: -tage * 86_400)) }

    static func liste(ordner: [String]) -> [DateiInfo] {
        if ordner.isEmpty {
            return [
                DateiInfo(name: "Büro", ordner: true, groesse: 0, geaendert: vor(2), anzahl: 12),
                DateiInfo(name: "Fitness", ordner: true, groesse: 0, geaendert: vor(9), anzahl: 8),
                DateiInfo(name: "Scans", ordner: true, groesse: 0, geaendert: vor(30), anzahl: 24),
                DateiInfo(name: "Videos", ordner: true, groesse: 0, geaendert: vor(70), anzahl: 3),
                DateiInfo(name: "Mietvertrag.pdf", ordner: false, groesse: 482_000, geaendert: vor(5)),
                DateiInfo(name: "Rechnung Strom Oktober.pdf", ordner: false, groesse: 96_000, geaendert: vor(3)),
                DateiInfo(name: "Urlaub Strand.jpg", ordner: false, groesse: 3_400_000, geaendert: vor(40)),
                DateiInfo(name: "Grillabend.jpg", ordner: false, groesse: 2_100_000, geaendert: vor(12)),
                DateiInfo(name: "Wanderung Film.mp4", ordner: false, groesse: 58_000_000, geaendert: vor(20)),
                DateiInfo(name: "Budget 2026.xlsx", ordner: false, groesse: 31_000, geaendert: vor(1)),
                DateiInfo(name: "Notizen.txt", ordner: false, groesse: 1_200, geaendert: vor(8)),
            ]
        }
        return [
            DateiInfo(name: "Rechnung Internet.pdf", ordner: false, groesse: 120_000, geaendert: vor(6)),
            DateiInfo(name: "Rechnung Versicherung.pdf", ordner: false, groesse: 210_000, geaendert: vor(15)),
            DateiInfo(name: "Kündigung Fitnessstudio.pdf", ordner: false, groesse: 64_000, geaendert: vor(50)),
            DateiInfo(name: "Steuerbescheid 2025.pdf", ordner: false, groesse: 340_000, geaendert: vor(90)),
        ]
    }

    /// Alles, was die Demo-Suche kennt (Pfade relativ zur Wurzel), Ordner zuerst.
    static let treffer: [SuchTreffer] = {
        let wurzel = liste(ordner: [])
        let unten = liste(ordner: ["Büro"])
        return wurzel.filter(\.ordner).map { SuchTreffer(pfad: $0.name, name: $0.name, ordner: true, groesse: 0, geaendert: $0.geaendert) }
            + unten.map { SuchTreffer(pfad: "Büro/\($0.name)", name: $0.name, ordner: false, groesse: $0.groesse, geaendert: $0.geaendert) }
            + wurzel.filter { !$0.ordner }.map { SuchTreffer(pfad: $0.name, name: $0.name, ordner: false, groesse: $0.groesse, geaendert: $0.geaendert) }
    }()
}
