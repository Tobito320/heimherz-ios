import CryptoKit
import Foundation

/// Das gespeicherte Ergebnis zu einem Eintrag: nur ob sein Passwort in einem Datenleck steckt und welcher Stand (`geaendert`) geprüft wurde.
/// Kein Hash, kein Passwort. Ändert sich der Eintrag, passt `geaendert` nicht mehr und er wird neu geprüft.
struct LeckStand: Codable, Equatable, Sendable {
    var geaendert: String
    var gefunden: Bool
}

/// Die Ergebnisse der Leck-Prüfung lokal in der App Group (UserDefaults): id → `LeckStand`, dazu der letzte vollständige Lauf.
struct LeckSpeicher {
    let speicher: UserDefaults
    private static let staendeSchluessel = "leck.staende"
    private static let laufSchluessel = "leck.letzterLauf"

    init(speicher: UserDefaults? = UserDefaults(suiteName: Kennungen.appGruppe)) {
        self.speicher = speicher ?? .standard
    }

    var staende: [String: LeckStand] {
        get { speicher.data(forKey: Self.staendeSchluessel).flatMap { try? JSONDecoder().decode([String: LeckStand].self, from: $0) } ?? [:] }
        nonmutating set {
            if let daten = try? JSONEncoder().encode(newValue) { speicher.set(daten, forKey: Self.staendeSchluessel) }
        }
    }

    /// Wann zuletzt alle Passwörter erfolgreich geprüft wurden (Grundlage für "höchstens einmal am Tag").
    var letzterLauf: Date? {
        get { (speicher.object(forKey: Self.laufSchluessel) as? Double).map { Date(timeIntervalSince1970: $0) } }
        nonmutating set {
            if let wert = newValue { speicher.set(wert.timeIntervalSince1970, forKey: Self.laufSchluessel) } else { speicher.removeObject(forKey: Self.laufSchluessel) }
        }
    }

    /// Entkoppelt: alles weg.
    func vergiss() {
        speicher.removeObject(forKey: Self.staendeSchluessel)
        speicher.removeObject(forKey: Self.laufSchluessel)
    }
}

/// Die Abfrage bei Pwned Passwords (Have I Been Pwned), `GET /range/<die ersten 5 Zeichen des SHA-1>`: k-Anonymität, zurück kommen alle
/// Suffixe zu diesem Anfang, verglichen wird auf dem Handy. `Add-Padding: true` füllt die Antwort mit Scheineinträgen (Anzahl 0) auf,
/// damit die Antwortlänge nichts verrät; sie zählen nicht als Treffer. Kein Schlüssel, kein Login, kein Bearer: nie das Gerätetoken des PC senden.
struct LeckAbfrage: Sendable {
    let sitzung: URLSession
    let basis: URL

    init(sitzung: URLSession = LeckAbfrage.standardSitzung, basis: URL = URL(string: "https://api.pwnedpasswords.com") ?? URL(fileURLWithPath: "/")) {
        self.sitzung = sitzung
        self.basis = basis
    }

    /// Eigene Sitzung ohne Cache und Cookies, kurze Wartezeit: kein Netz heißt schnell aufgeben.
    static let standardSitzung: URLSession = {
        let k = URLSessionConfiguration.ephemeral
        k.timeoutIntervalForRequest = 10
        k.timeoutIntervalForResource = 20
        k.urlCache = nil
        k.httpCookieStorage = nil
        k.waitsForConnectivity = false
        return URLSession(configuration: k)
    }()

    struct Fehler: Error, Equatable { let status: Int }

    /// Alle Suffixe (35 Zeichen, groß) mit Anzahl über 0 zu diesem Anfang. Wirft bei Netzfehler oder Status außer 200.
    func suffixe(vorwahl: String) async throws -> Set<String> {
        var anfrage = URLRequest(url: basis.appending(path: "range/\(vorwahl)"))
        anfrage.httpMethod = "GET"
        anfrage.setValue("true", forHTTPHeaderField: "Add-Padding")
        anfrage.setValue("Lumen Cloud", forHTTPHeaderField: "User-Agent")
        let (daten, antwort) = try await sitzung.data(for: anfrage)
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Fehler(status: status) }
        return Self.lese(String(decoding: daten, as: UTF8.self))
    }

    /// Zeilen `SUFFIX:ANZAHL` (CRLF oder LF). Anzahl 0 ist Füllung und zählt nicht.
    static func lese(_ text: String) -> Set<String> {
        var treffer = Set<String>()
        for zeile in text.split(whereSeparator: \.isNewline) {
            let teile = zeile.split(separator: ":", maxSplits: 1)
            guard teile.count == 2, let anzahl = Int(teile[1].trimmingCharacters(in: .whitespaces)), anzahl > 0 else { continue }
            treffer.insert(teile[0].trimmingCharacters(in: .whitespaces).uppercased())
        }
        return treffer
    }
}

/// Die Logik der Leck-Prüfung: wer geprüft werden muss und wie geprüft wird. Das Passwort verlässt das Handy nie, nur die ersten 5 Zeichen seines SHA-1.
enum LeckPruefung {
    /// Höchstens einmal am Tag alle, dazwischen nur neue oder geänderte Einträge.
    static let abstand: TimeInterval = 86_400

    /// SHA-1 in Großbuchstaben, 40 Zeichen. SHA-1 ist hier nur das Format des Dienstes, kein Schutz.
    static func sha1(_ text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    /// Lebendige Logins mit Passwort, deren Stand fehlt oder nicht zum Eintrag passt. Nach `abstand` seit dem letzten vollständigen Lauf alle.
    static func faellig(_ eintraege: [Eintrag], staende: [String: LeckStand], letzterLauf: Date?, jetzt: Date) -> (eintraege: [Eintrag], alle: Bool) {
        let logins = eintraege.filter { !$0.geloescht && $0.art == Eintrag.artLogin && !$0.passwort.isEmpty }
        let alle = letzterLauf.map { jetzt.timeIntervalSince($0) >= abstand } ?? true
        return (alle ? logins : logins.filter { staende[$0.id]?.geaendert != $0.geaendert }, alle)
    }

    /// Die ids mit gültigem Treffer: nur lebendige Einträge, deren Stand zum Eintrag passt.
    static func lecks(_ eintraege: [Eintrag], staende: [String: LeckStand]) -> Set<String> {
        Set(eintraege.compactMap { e in
            guard !e.geloescht, let s = staende[e.id], s.gefunden, s.geaendert == e.geaendert else { return nil }
            return e.id
        })
    }

    struct Lauf: Sendable, Equatable {
        /// id → gefunden, nur für Einträge, die wirklich beantwortet wurden.
        var ergebnisse: [String: Bool] = [:]
        /// false, sobald eine Anfrage scheiterte (Netz weg, Fehlerstatus, abgebrochen): der Rest bleibt wie er war.
        var vollstaendig = true
    }

    /// Fragt je verschiedenem 5er-Anfang einmal und vergleicht die Suffixe hier. Bei der ersten Störung ist Schluss, nichts wird geraten.
    static func pruefe(_ kandidaten: [(id: String, passwort: String)], abfrage: LeckAbfrage) async -> Lauf {
        var lauf = Lauf()
        let gehasht = kandidaten.map { (id: $0.id, hash: sha1($0.passwort)) }
        let nachVorwahl = Dictionary(grouping: gehasht) { String($0.hash.prefix(5)) }
        for vorwahl in nachVorwahl.keys.sorted() {
            if Task.isCancelled {
                lauf.vollstaendig = false
                break
            }
            do {
                let treffer = try await abfrage.suffixe(vorwahl: vorwahl)
                for k in nachVorwahl[vorwahl] ?? [] { lauf.ergebnisse[k.id] = treffer.contains(String(k.hash.dropFirst(5))) }
            } catch {
                lauf.vollstaendig = false
                break
            }
        }
        return lauf
    }
}
