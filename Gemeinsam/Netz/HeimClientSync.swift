import Foundation

/// Die Routen des Dateien-Sync (SPEC 31) für die Datei-Anbieter-Erweiterung. Kennungen statt Pfade; `eltern` leer = Wurzel.
extension HeimClient {
    /// Änderungen seit `anker` (nil = alles). 410 (alter oder fremder Anker) kommt als `HeimFehler.abgelehnt(410)`, `SyncRegeln.fehlerArt` macht `syncAnchorExpired` daraus.
    /// `nurAnker`: schickt keinen Baum, nur den aktuellen Anker (`currentSyncAnchor`).
    func syncAenderungen(anker: String?, nurAnker: Bool = false) async throws -> SyncAenderungen {
        var abfrage: [(String, String)] = []
        if let anker { abfrage.append(("anker", anker)) }
        if nurAnker { abfrage.append(("kurz", "1")) }
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien/aenderungen", abfrage: abfrage))
        try Self.pruefe(status)
        return try dekodiere(SyncAenderungen.self, daten)
    }

    func syncKinder(id: String) async throws -> [SyncEintrag] {
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien/kinder", abfrage: [("id", id)]))
        try Self.pruefe(status)
        return try dekodiere([SyncEintrag].self, daten)
    }

    /// Ein Eintrag samt Pfad (für den Download).
    func syncEintrag(id: String) async throws -> SyncEintrag {
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien/eintrag", abfrage: [("id", id)]))
        try Self.pruefe(status)
        return try dekodiere(SyncEintrag.self, daten)
    }

    /// Neue Datei in einem Ordner; der Dienst überschreibt nie (` (2)`), der Eintrag nennt den Namen, unter dem sie jetzt liegt.
    func syncNeu(eltern: String, name: String, von quelle: URL) async throws -> SyncEintrag {
        do {
            var r = try anfrage("PUT", "/v1/dateien/neu", abfrage: [("eltern", eltern), ("name", name)])
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            r.timeoutInterval = 600
            let (daten, meta) = try await sitzung.upload(for: r, fromFile: quelle)
            guard let http = meta as? HTTPURLResponse else { throw HeimFehler.ungueltigeAntwort }
            try Self.pruefe(http.statusCode)
            return try dekodiere(SyncEintrag.self, daten)
        } catch let fehler as URLError {
            throw HeimFehler(urlFehler: fehler)
        }
    }

    /// Ordner anlegen; ist der Name vergeben, wirft das `HeimFehler.konflikt`.
    func syncOrdner(eltern: String, name: String) async throws -> SyncEintrag {
        let (daten, status) = try await json("/v1/dateien/ordner", ["eltern": eltern, "name": name])
        try Self.pruefe(status)
        return try dekodiere(SyncEintrag.self, daten)
    }

    /// Umbenennen und/oder verschieben (nil = unverändert). Ziel vergeben: `HeimFehler.konflikt`.
    func syncUmbenennen(id: String, eltern: String?, name: String?) async throws -> SyncEintrag {
        var k: [String: String] = ["id": id]
        if let eltern { k["eltern"] = eltern }
        if let name { k["name"] = name }
        let (daten, status) = try await json("/v1/dateien/umbenennen", k)
        try Self.pruefe(status)
        return try dekodiere(SyncEintrag.self, daten)
    }

    /// Ersetzt den Inhalt, nur wenn `fassung` noch die aktuelle am PC ist; sonst ändert sich nichts und `konflikt` nennt die Fassung des PCs.
    func syncErsetzen(id: String, fassung: String, von quelle: URL) async throws -> ErsetzenErgebnis {
        do {
            var r = try anfrage("PUT", "/v1/dateien/ersetzen", abfrage: [("id", id), ("fassung", fassung)])
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            r.timeoutInterval = 600
            let (daten, meta) = try await sitzung.upload(for: r, fromFile: quelle)
            guard let http = meta as? HTTPURLResponse else { throw HeimFehler.ungueltigeAntwort }
            if http.statusCode == 409 { return .konflikt(aktuell: try? dekodiere(SyncEintrag.self, daten)) }
            try Self.pruefe(http.statusCode)
            return .ersetzt(try dekodiere(SyncEintrag.self, daten))
        } catch let fehler as URLError {
            throw HeimFehler(urlFehler: fehler)
        }
    }

    /// In den Papierkorb am PC (nie endgültig). Mit `fassung`: nur wenn sie noch stimmt, sonst `HeimFehler.konflikt`.
    func syncPapierkorb(id: String, fassung: String?) async throws {
        var k: [String: String] = ["id": id]
        if let fassung { k["fassung"] = fassung }
        let (_, status) = try await json("/v1/dateien/papierkorb", k)
        try Self.pruefe(status)
    }

    private func json(_ pfad: String, _ koerper: [String: String]) async throws -> (Data, Int) {
        var r = try anfrage("POST", pfad)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await sende(r, daten: try JSONSerialization.data(withJSONObject: koerper))
    }
}
