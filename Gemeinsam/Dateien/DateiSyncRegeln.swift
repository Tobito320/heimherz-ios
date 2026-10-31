import Foundation

/// Ein Eintrag der Dateien-Sync-Routen (SPEC 31): `id` ist die stabile Kennung am PC, `eltern` leer für die Wurzel.
/// `pfad` kommt nur von `GET /v1/dateien/eintrag` und führt zu `GET /v1/datei?pfad=`.
struct SyncEintrag: Codable, Sendable, Hashable {
    var id: String
    var eltern: String
    var name: String
    var ordner: Bool
    var groesse: Int64
    /// ISO-Zeit (UTC).
    var geaendert: String
    /// `<mtimeMs>-<Größe>`; für Ordner nur die Zeit. Der Dienst vergleicht damit beim Ersetzen und Löschen.
    var fassung: String
    var pfad: String? = nil

    var datum: Date? { Zeit.millis(iso: geaendert).map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}

/// Antwort von `GET /v1/dateien/aenderungen`.
struct SyncAenderungen: Codable, Sendable, Equatable {
    var anker: String
    var voll: Bool
    var eintraege: [SyncEintrag]
    var weg: [String]
}

/// Ergebnis von `PUT /v1/dateien/ersetzen`.
enum ErsetzenErgebnis: Sendable, Equatable {
    case ersetzt(SyncEintrag)
    /// 409: der PC hat die Datei inzwischen geändert; `aktuell` ist seine Fassung.
    case konflikt(aktuell: SyncEintrag?)
}

/// Welche Art Fehler die Dateien-App sehen soll; die Erweiterung macht daraus `NSFileProviderError`. Hier ohne FileProvider, damit es testbar bleibt.
enum SyncFehlerArt: Equatable, Sendable {
    /// PC aus, Tailscale aus, Dienst hängt: iOS versucht es später selbst wieder.
    case serverUnreachable
    case notAuthenticated
    case noSuchItem
    /// Der Anker ist zu alt oder gehört zu einem neu gestarteten Dienst: alles neu lesen.
    case syncAnchorExpired
    case insufficientQuota
    case cannotSynchronize
    case abgebrochen
    /// 409 (Name vergeben, Fassung veraltet)
    case konflikt
}

/// Reine Regeln der Datei-Anbieter-Erweiterung "Lumen Cloud" (SPEC 31). Liegen in `Gemeinsam/`, damit die Tests sie sehen.
enum SyncRegeln {
    static func fehlerArt(_ fehler: Error) -> SyncFehlerArt {
        if fehler is CancellationError { return .abgebrochen }
        if let u = fehler as? URLError { return u.code == .cancelled ? .abgebrochen : .serverUnreachable }
        guard let f = fehler as? HeimFehler else { return .cannotSynchronize }
        if f.istNetzproblem { return .serverUnreachable }
        switch f {
        case .nichtGekoppelt, .nichtBerechtigt, .ungueltigeAdresse: return .notAuthenticated
        case .nichtGefunden: return .noSuchItem
        case .speicherVoll: return .insufficientQuota
        case .abgelehnt(410): return .syncAnchorExpired
        case .konflikt: return .konflikt
        case .abgebrochen: return .abgebrochen
        default: return .cannotSynchronize
        }
    }

    /// Freie Namen, falls beim Umbenennen oder Verschieben am PC schon einer vergeben ist: "a.txt" gibt "a (2).txt", "a (3).txt" …
    /// (wie der Dienst beim Hochladen). Ohne Namen bleibt es leer.
    static func alternativeNamen(zu name: String, anzahl: Int = 5) -> [String] {
        guard !name.isEmpty, anzahl > 0 else { return [] }
        let ns = name as NSString
        let endung = ns.pathExtension
        let basis = ns.deletingPathExtension
        return (2..<(anzahl + 2)).map { endung.isEmpty ? "\(basis) (\($0))" : "\(basis) (\($0)).\(endung)" }
    }

    /// Die Fassung, die der Dienst als `contentVersion` erwartet, aus den Daten der Version, die iOS als Basis nennt. Leer oder unlesbar: nil.
    static func fassung(ausVersion daten: Data) -> String? {
        guard !daten.isEmpty, let s = String(data: daten, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// Versionen für iOS: Inhalt = Fassung, Metadaten = Fassung, Name und Ort (ändert sich eines, ist es eine neue Metadaten-Version).
    static func inhaltsVersion(_ e: SyncEintrag) -> Data { Data(e.fassung.utf8) }
    static func metadatenVersion(_ e: SyncEintrag) -> Data { Data("\(e.fassung)|\(e.name)|\(e.eltern)".utf8) }
}

/// Was die App mit der Domain "Lumen Cloud" der Dateien-App tun muss.
enum DomainAktion: Equatable, Sendable {
    case hinzufuegen, entfernen, nichts

    static let kennung = "lumen-cloud"
    static let anzeigename = "Lumen Cloud"

    /// Gekoppelt und noch keine Domain: anlegen. Entkoppelt und Domain da: entfernen (iOS löscht dabei die lokalen Kopien).
    static func bestimme(gekoppelt: Bool, vorhanden: Bool) -> DomainAktion {
        switch (gekoppelt, vorhanden) {
        case (true, false): return .hinzufuegen
        case (false, true): return .entfernen
        default: return .nichts
        }
    }
}
