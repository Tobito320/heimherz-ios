import Foundation
import Observation

// Startseite des Dateien-Tabs wie "Durchsuchen" in Apple Dateien (T21, SPEC 12): drei Abschnitte aus den Ordnern am PC.

/// Die drei Abschnitte. Der Name ist zugleich der Ordnername in der Wurzel von `~/Heimherz/Dateien`.
enum DateiKategorie: String, CaseIterable, Sendable {
    case buerokratie = "Bürokratie"
    case projekte = "Projekte"
    case weitere = "Weitere"

    var titel: String { rawValue }
    var ordnerName: String { rawValue }
}

/// Eine Zeile der Startseite: direkter Eintrag eines Kategorie-Ordners oder etwas Fremdes aus der Wurzel.
struct StartZeile: Identifiable, Hashable, Sendable {
    let info: DateiInfo
    /// Die Ordner über dem Eintrag, ab der Wurzel (`["Bürokratie"]`, bei Fremdem aus der Wurzel `[]`).
    let ueber: [String]

    var pfad: String { DateiPfad.zusammen(ueber, info.name) }
    var id: String { pfad }
    var symbol: String { info.ordner ? DateiAnzeige.ordnerSymbol(name: info.name) : DateiAnzeige.symbol(name: info.name, ordner: false) }
}

struct StartAbschnitt: Identifiable, Hashable, Sendable {
    let kategorie: DateiKategorie
    let zeilen: [StartZeile]
    var id: String { kategorie.rawValue }
}

enum DateienStart {
    /// Welche Kategorie-Ordner die Wurzel hat (nur Ordner zählen; eine Datei namens "Projekte" ist keiner).
    static func vorhanden(in wurzel: [DateiInfo]) -> [DateiKategorie] {
        DateiKategorie.allCases.filter { k in wurzel.contains { $0.ordner && $0.name == k.ordnerName } }
    }

    /// Baut die Abschnitte in fester Reihenfolge. `inhalte` ist der Inhalt je Kategorie-Ordner. Abschnitte ohne Zeilen fehlen.
    /// Weitere sammelt zusätzlich alles aus der Wurzel, was keiner der drei Kategorie-Ordner ist (z. B. `Aboherz`).
    static func bilde(wurzel: [DateiInfo], inhalte: [DateiKategorie: [DateiInfo]]) -> [StartAbschnitt] {
        let da = vorhanden(in: wurzel)
        let fremde = wurzel.filter { e in !(e.ordner && DateiKategorie.allCases.contains { $0.ordnerName == e.name }) }
        return DateiKategorie.allCases.compactMap { k in
            var zeilen = da.contains(k) ? (inhalte[k] ?? []).map { StartZeile(info: $0, ueber: [k.ordnerName]) } : []
            if k == .weitere { zeilen += fremde.map { StartZeile(info: $0, ueber: []) } }
            return zeilen.isEmpty ? nil : StartAbschnitt(kategorie: k, zeilen: sortiere(zeilen))
        }
    }

    /// Ordner vor Dateien, Namen mit `_` (Archiv) zuletzt, sonst nach Namen wie in Dateien (1, 2, … 10).
    static func sortiere(_ zeilen: [StartZeile]) -> [StartZeile] {
        zeilen.sorted { a, b in
            if a.info.ordner != b.info.ordner { return a.info.ordner }
            let ua = a.info.name.hasPrefix("_"), ub = b.info.name.hasPrefix("_")
            if ua != ub { return ub }
            return a.info.name.localizedStandardCompare(b.info.name) == .orderedAscending
        }
    }
}

extension DateiAnzeige {
    /// Symbole der Ordner auf der Startseite. Der Schlüssel ist der Namensanfang ohne führende Ziffer, Leerzeichen und `_`, klein geschrieben.
    /// Das ist die eine Tabelle dafür; Unbekanntes ist ein einfacher Ordner.
    static let ordnerSymbole: [(anfang: String, symbol: String)] = [
        ("ausweise", "person.text.rectangle"), ("jobcenter", "building.2"), ("behörden", "building.columns"), ("geld", "eurosign.circle"),
        ("wohnen", "house"), ("gesundheit", "cross.case"), ("schule", "graduationcap"), ("archiv", "archivebox"), ("alt vor", "archivebox"),
        ("coding", "chevron.left.forwardslash.chevron.right"), ("videos", "film"), ("money machine", "briefcase"),
        ("fitness", "figure.run"), ("icloud", "icloud"),
    ]

    static func ordnerSymbol(name: String) -> String {
        let n = name.precomposedStringWithCanonicalMapping.lowercased().drop { $0.isNumber || $0 == "_" || $0.isWhitespace }
        return ordnerSymbole.first { n.hasPrefix($0.anfang) }?.symbol ?? "folder"
    }
}

/// Welche Abschnitte der Startseite eingeklappt sind. Als Text in `@AppStorage` gemerkt (Namen mit `|` getrennt).
struct EingeklappteAbschnitte: RawRepresentable, Equatable {
    private(set) var namen: Set<String>

    init(namen: Set<String> = []) { self.namen = namen }

    init?(rawValue: String) { namen = Set(rawValue.split(separator: "|").map(String.init)) }

    var rawValue: String { namen.sorted().joined(separator: "|") }

    func istEingeklappt(_ k: DateiKategorie) -> Bool { namen.contains(k.rawValue) }

    mutating func schalte(_ k: DateiKategorie) {
        if !namen.insert(k.rawValue).inserted { namen.remove(k.rawValue) }
    }
}

/// Lädt die Startseite: erst die Wurzel, dann gleichzeitig nur die Kategorie-Ordner, die es gibt. Fehler lassen die letzten Abschnitte stehen.
@MainActor @Observable
final class DateienStartModell {
    typealias Zustand = DateienModell.Zustand

    private(set) var abschnitte: [StartAbschnitt] = []
    private(set) var zustand = Zustand.laedt

    let istDemo: Bool
    private let holeClient: @MainActor () throws -> HeimClient
    private var ladeNummer = 0

    init(istDemo: Bool, holeClient: @escaping @MainActor () throws -> HeimClient) {
        self.istDemo = istDemo
        self.holeClient = holeClient
        if istDemo {
            abschnitte = DateienDemo.abschnitte
            zustand = .bereit
        }
    }

    func lade() async {
        guard !istDemo else { return }
        ladeNummer += 1
        let nr = ladeNummer
        if abschnitte.isEmpty { zustand = .laedt }
        do {
            let client = try holeClient()
            let wurzel = try await client.dateienListe(pfad: "")
            let da = DateienStart.vorhanden(in: wurzel)
            let inhalte = try await withThrowingTaskGroup(of: (DateiKategorie, [DateiInfo]).self, returning: [DateiKategorie: [DateiInfo]].self) { gruppe in
                for k in da { gruppe.addTask { (k, try await client.dateienListe(pfad: k.ordnerName)) } }
                var alle: [DateiKategorie: [DateiInfo]] = [:]
                for try await (k, liste) in gruppe { alle[k] = liste }
                return alle
            }
            guard nr == ladeNummer else { return }
            abschnitte = DateienStart.bilde(wurzel: wurzel, inhalte: inhalte)
            zustand = .bereit
        } catch {
            guard nr == ladeNummer, !DateienModell.istAbbruch(error) else { return }
            zustand = DateienModell.fehlerZustand(error)
        }
    }
}
