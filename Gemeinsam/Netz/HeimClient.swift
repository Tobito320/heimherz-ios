import Foundation

/// Antwort von `GET /v1/status` (SPEC 6). `belegt` und `frei` sind Bytes.
struct ServerStatus: Codable, Sendable, Equatable {
    var version: String
    var rev: Int
    var fotos: Int
    var belegt: Int64?
    var frei: Int64?
}

/// Ein schon am PC liegendes Foto (Ressource) aus `GET /v1/fotos/bekannt`.
struct BekanntesFoto: Codable, Sendable, Hashable {
    var kennung: String
    var ressource: String
    var groesse: Int64
}

/// Ein Eintrag der Ordnerliste `GET /v1/dateien`.
struct DateiInfo: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var ordner: Bool
    var groesse: Int64
    /// ISO-Zeit (UTC); `datum` wandelt um.
    var geaendert: String
    /// Nur bei Ordnern: wie viele Einträge darin liegen ("12 Objekte"). Ältere Dienste schicken es nicht.
    var anzahl: Int? = nil
    var id: String { name }
    var datum: Date? { Zeit.millis(iso: geaendert).map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}

/// Ein Treffer der Suche `GET /v1/dateien/suche`. `pfad` ist relativ zur Wurzel und endet mit dem Namen.
struct SuchTreffer: Codable, Sendable, Hashable, Identifiable {
    var pfad: String
    var name: String
    var ordner: Bool
    var groesse: Int64
    var geaendert: String
    var id: String { pfad }
    var datum: Date? { Zeit.millis(iso: geaendert).map { Date(timeIntervalSince1970: Double($0) / 1000) } }

    /// Als Eintrag der Ordnerliste (für Zeilen, Menü und Papierkorb).
    var info: DateiInfo { DateiInfo(name: name, ordner: ordner, groesse: groesse, geaendert: geaendert) }
    /// Die Ordner, in denen der Treffer liegt ("A/B/c.pdf" gibt ["A", "B"]).
    var uebergeordnet: [String] { pfad.split(separator: "/").dropLast().map(String.init) }
}

/// Ergebnis von `PUT /v1/tresor`.
enum TresorSchreiben: Sendable, Equatable {
    /// 200: der gespeicherte Umschlag, mit der vom Server vergebenen neuen `rev`.
    case gespeichert(Umschlag)
    /// 409: die `rev` stimmte nicht. `aktuell` ist der Umschlag des Servers (nil, wenn der Server keinen schickte).
    case konflikt(aktuell: Umschlag?)
}

/// Fehler im Umgang mit dem PC-Dienst, mit deutschen Texten für die Oberfläche.
enum HeimFehler: Error, Equatable, LocalizedError {
    case nichtGekoppelt
    case ungueltigeAdresse
    case nichtErreichbar
    case zeitueberschreitung
    case nichtBerechtigt
    case verboten
    case nichtGefunden
    case konflikt
    case zuGross
    case speicherVoll
    case ungueltigeAntwort
    case serverFehler(Int)
    case abgelehnt(Int)
    case zuVieleKonflikte
    case abgebrochen

    init(urlFehler: URLError) {
        switch urlFehler.code {
        case .timedOut: self = .zeitueberschreitung
        case .cancelled: self = .abgebrochen
        default: self = .nichtErreichbar
        }
    }

    /// Fehler, bei denen die App mit dem lokalen Stand weiterarbeitet (PC aus, kein Tailscale, Dienst hängt).
    var istNetzproblem: Bool {
        switch self {
        case .nichtErreichbar, .zeitueberschreitung, .serverFehler: return true
        default: return false
        }
    }

    var nutzerText: String {
        switch self {
        case .nichtGekoppelt: return "Das Handy ist noch nicht mit dem PC gekoppelt."
        case .ungueltigeAdresse: return "Die Adresse des PCs ist ungültig. Bitte neu koppeln."
        case .nichtErreichbar: return "Der PC ist gerade nicht erreichbar. Läuft Tailscale, und ist der PC an?"
        case .zeitueberschreitung: return "Der PC antwortet nicht rechtzeitig."
        case .nichtBerechtigt: return "Der PC kennt dieses Handy nicht mehr. Bitte neu koppeln."
        case .verboten: return "Dieser Pfad ist nicht erlaubt."
        case .nichtGefunden: return "Das gibt es auf dem PC nicht (mehr)."
        case .konflikt: return "Das läuft auf dem PC schon, oder es wurde gleichzeitig geändert."
        case .zuGross: return "Die Datei ist zu groß für den PC-Dienst."
        case .speicherVoll: return "Die Platte am PC ist voll. Der Abgleich hält an, bis dort wieder Platz ist."
        case .ungueltigeAntwort: return "Die Antwort vom PC ist unverständlich."
        case .serverFehler(let n): return "Der PC-Dienst meldet einen Fehler (\(n))."
        case .abgelehnt(let n): return "Der PC hat die Anfrage abgelehnt (\(n))."
        case .zuVieleKonflikte: return "Der Tresor wurde mehrmals gleichzeitig geändert. Bitte noch einmal versuchen."
        case .abgebrochen: return "Abgebrochen."
        }
    }

    var errorDescription: String? { nutzerText }

    /// Wandelt einen HTTP-Status (nicht 2xx) in einen Fehler.
    static func aus(status: Int) -> HeimFehler {
        switch status {
        case 401: return .nichtBerechtigt
        case 403: return .verboten
        case 404: return .nichtGefunden
        case 409: return .konflikt
        case 413: return .zuGross
        case 507: return .speicherVoll
        case 500...599: return .serverFehler(status)
        default: return .abgelehnt(status)
        }
    }
}

extension CharacterSet {
    /// Unreserviert nach RFC 3986: alles andere wird prozentkodiert (auch `+` und `&`, sonst liest der Server falsch).
    static let heimherzUnreserviert = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

/// Alle Routen des PC-Dienstes (SPEC 6) als typisierte async-Funktionen. `URLSession` ist austauschbar (Tests: `URLProtocol`-Attrappe).
/// Jede Anfrage trägt `Authorization: Bearer <Token>`.
struct HeimClient: Sendable {
    let basis: URL
    let token: String
    let sitzung: URLSession

    init(basis: URL, token: String, sitzung: URLSession = .shared) {
        self.basis = basis
        self.token = token
        self.sitzung = sitzung
    }

    /// Aus dem Schlüsselbund; wirft `nichtGekoppelt`, wenn dort nichts liegt.
    static func aus(_ bund: Schluesselbund, sitzung: URLSession = .shared) throws -> HeimClient {
        guard let g = try bund.ladeGeraet() else { throw HeimFehler.nichtGekoppelt }
        return HeimClient(basis: g.url, token: g.token, sitzung: sitzung)
    }

    // MARK: Anfragen bauen

    static func kodiere(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .heimherzUnreserviert) ?? text
    }

    /// Eine Anfrage mit Token. `abfrage` wird selbst kodiert.
    func anfrage(_ methode: String, _ pfad: String, abfrage: [(String, String)] = []) throws -> URLRequest {
        guard var teile = URLComponents(url: basis, resolvingAgainstBaseURL: false), teile.scheme == "https" || teile.scheme == "http" else {
            throw HeimFehler.ungueltigeAdresse
        }
        let wurzel = teile.path.hasSuffix("/") ? String(teile.path.dropLast()) : teile.path
        teile.path = wurzel + pfad
        if !abfrage.isEmpty {
            teile.percentEncodedQuery = abfrage.map { Self.kodiere($0.0) + "=" + Self.kodiere($0.1) }.joined(separator: "&")
        }
        guard let url = teile.url else { throw HeimFehler.ungueltigeAdresse }
        var r = URLRequest(url: url)
        r.httpMethod = methode
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 30
        return r
    }

    /// Die Anfrage für einen Foto-Upload (`PUT /v1/fotos/<kennung>/<ressource>`), für den Hintergrund-`URLSession`-Upload der App
    /// (`uploadTask(fromFile:)`, setzt Content-Length) und für den Upload-Job der Foto-Erweiterung (`PHAssetResourceUploadJobChangeRequest`).
    /// `kennung` und `ressource` nur `[A-Za-z0-9_-]{1,128}` (Server prüft gleich).
    func fotoHochladenAnfrage(kennung: String, ressource: String, aufnahme: Date?, dateiname: String) throws -> URLRequest {
        guard Self.istKennung(kennung), Self.istKennung(ressource) else { throw HeimFehler.ungueltigeAdresse }
        var r = try anfrage("PUT", "/v1/fotos/\(kennung)/\(ressource)")
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let aufnahme { r.setValue(Zeit.iso(aufnahme), forHTTPHeaderField: "X-Aufnahme") }
        r.setValue(Self.kodiere(dateiname), forHTTPHeaderField: "X-Dateiname")
        return r
    }

    static func istKennung(_ text: String) -> Bool {
        (1...128).contains(text.utf8.count) && text.utf8.allSatisfy { b in
            (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 95
        }
    }

    // MARK: Senden

    private func sende(_ r: URLRequest, daten: Data? = nil) async throws -> (Data, Int) {
        do {
            let antwort: Data
            let meta: URLResponse
            if let daten {
                (antwort, meta) = try await sitzung.upload(for: r, from: daten)
            } else {
                (antwort, meta) = try await sitzung.data(for: r)
            }
            guard let http = meta as? HTTPURLResponse else { throw HeimFehler.ungueltigeAntwort }
            return (antwort, http.statusCode)
        } catch let fehler as URLError {
            throw HeimFehler(urlFehler: fehler)
        }
    }

    private func dekodiere<T: Decodable>(_ typ: T.Type, _ daten: Data) throws -> T {
        do { return try JSONDecoder().decode(typ, from: daten) } catch { throw HeimFehler.ungueltigeAntwort }
    }

    private static func pruefe(_ status: Int) throws {
        guard (200...299).contains(status) else { throw HeimFehler.aus(status: status) }
    }

    // MARK: Routen

    func status() async throws -> ServerStatus {
        let (daten, status) = try await sende(anfrage("GET", "/v1/status"))
        try Self.pruefe(status)
        return try dekodiere(ServerStatus.self, daten)
    }

    /// nil, wenn der Server noch keinen Tresor hat (404).
    func tresorHolen() async throws -> Umschlag? {
        let (daten, status) = try await sende(anfrage("GET", "/v1/tresor"))
        if status == 404 { return nil }
        try Self.pruefe(status)
        let u = try dekodiere(Umschlag.self, daten)
        guard u.istGueltigeForm else { throw HeimFehler.ungueltigeAntwort }
        return u
    }

    /// `PUT /v1/tresor` mit `If-Match: <rev>` (immer, auch `0` beim ersten Mal; sonst 428). Der Server vergibt die neue `rev` selbst.
    func tresorSchreiben(_ umschlag: Umschlag, ifMatch rev: Int) async throws -> TresorSchreiben {
        var r = try anfrage("PUT", "/v1/tresor")
        r.setValue(String(rev), forHTTPHeaderField: "If-Match")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let (daten, status) = try await sende(r, daten: try encoder.encode(umschlag))
        if status == 409 { return .konflikt(aktuell: try? dekodiere(Umschlag.self, daten)) }
        try Self.pruefe(status)
        return .gespeichert(try dekodiere(Umschlag.self, daten))
    }

    /// Das Symbol einer Webseite (`GET /v1/symbol?host=`), vom PC bei der Seite selbst geholt. nil, wenn die Seite keins hat (404) oder der Name nicht gilt (400).
    func symbolHolen(host: String) async throws -> Data? {
        let (daten, status) = try await sende(anfrage("GET", "/v1/symbol", abfrage: [("host", host)]))
        if status == 404 || status == 400 { return nil }
        try Self.pruefe(status)
        return daten
    }

    func fotosBekannt() async throws -> [BekanntesFoto] {
        let (daten, status) = try await sende(anfrage("GET", "/v1/fotos/bekannt"))
        try Self.pruefe(status)
        return try dekodiere([BekanntesFoto].self, daten)
    }

    /// Ordnerliste; `pfad` relativ zu `~/Heimherz/Dateien`, leer für die Wurzel.
    func dateienListe(pfad: String = "") async throws -> [DateiInfo] {
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien", abfrage: [("pfad", pfad)]))
        try Self.pruefe(status)
        return try dekodiere([DateiInfo].self, daten)
    }

    /// Suche im Namen, rekursiv ab `pfad` (leer = alles). Höchstens 200 Treffer, Ordner zuerst.
    func dateienSuche(q: String, pfad: String = "") async throws -> [SuchTreffer] {
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien/suche", abfrage: [("q", q), ("pfad", pfad)]))
        try Self.pruefe(status)
        return try dekodiere([SuchTreffer].self, daten)
    }

    /// Kleines JPEG zu einer Datei (`px` 120 bis 600). nil, wenn der PC keins machen kann (404: anderer Typ oder kaputte Datei).
    func dateiVorschau(pfad: String, px: Int) async throws -> Data? {
        let (daten, status) = try await sende(anfrage("GET", "/v1/dateien/vorschau", abfrage: [("pfad", pfad), ("px", String(px))]))
        if status == 404 { return nil }
        try Self.pruefe(status)
        return daten
    }

    /// Lädt eine Datei in `ziel` (ersetzt eine vorhandene). Der Server unterstützt `Range`; hier wird alles geladen.
    func dateiLaden(pfad: String, nach ziel: URL) async throws {
        do {
            let (temp, meta) = try await sitzung.download(for: anfrage("GET", "/v1/datei", abfrage: [("pfad", pfad)]))
            guard let http = meta as? HTTPURLResponse else { throw HeimFehler.ungueltigeAntwort }
            try Self.pruefe(http.statusCode)
            if FileManager.default.fileExists(atPath: ziel.path) { try FileManager.default.removeItem(at: ziel) }
            try FileManager.default.moveItem(at: temp, to: ziel)
        } catch let fehler as URLError {
            throw HeimFehler(urlFehler: fehler)
        }
    }

    /// Lädt eine Datei hoch (`pfad` = Zielpfad samt Namen; der Elternordner muss am PC existieren). Der Server überschreibt nie:
    /// bei gleichem Namen hängt er ` (2)` an. Rückgabe ist der Name, unter dem die Datei jetzt liegt.
    @discardableResult
    func dateiHochladen(pfad: String, von quelle: URL) async throws -> String {
        struct Antwort: Decodable { let name: String }
        do {
            var r = try anfrage("PUT", "/v1/datei", abfrage: [("pfad", pfad)])
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            r.timeoutInterval = 600
            let (daten, meta) = try await sitzung.upload(for: r, fromFile: quelle)
            guard let http = meta as? HTTPURLResponse else { throw HeimFehler.ungueltigeAntwort }
            try Self.pruefe(http.statusCode)
            return try dekodiere(Antwort.self, daten).name
        } catch let fehler as URLError {
            throw HeimFehler(urlFehler: fehler)
        }
    }

    /// Legt eine Datei oder einen Ordner am PC in den Papierkorb (nie endgültig löschen).
    func inPapierkorb(pfad: String) async throws {
        var r = try anfrage("POST", "/v1/datei/papierkorb")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, status) = try await sende(r, daten: JSONSerialization.data(withJSONObject: ["pfad": pfad]))
        try Self.pruefe(status)
    }
}
