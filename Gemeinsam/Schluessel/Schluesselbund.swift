import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Reicht einen `LAContext` an Hintergrund-Aufgaben weiter. Die AutoFill-Erweiterung legt einen Kontext an, entsperrt einmal
/// und liest damit mehrere Schlüsselbund-Einträge, ohne mehrfach nach Face ID zu fragen.
/// shortcut: `LAContext` ist nicht als Sendable markiert; Apple nutzt ihn aus beliebigen Threads, wir geben ihn nur weiter und lesen nie gleichzeitig. Bei einem Compilerfehler nach SDK-Wechsel prüfen.
struct EntsperrKontext: @unchecked Sendable {
    let kontext: LAContext
    init(_ kontext: LAContext = LAContext()) { self.kontext = kontext }
}

enum SchluesselbundFehler: Error, Equatable, LocalizedError {
    case speichern(Int32)
    case lesen(Int32)
    case loeschen(Int32)
    /// Face ID oder Code abgebrochen oder abgelehnt.
    case entsperrenAbgebrochen
    /// -25308 (`errSecInteractionNotAllowed`): iOS darf die Abfrage gerade nicht zeigen (die Oberfläche der Erweiterung ist noch nicht aktiv). Nie als Text zeigen, nachholen.
    case abfrageNochNichtMoeglich

    var nutzerText: String {
        switch self {
        case .entsperrenAbgebrochen: return "Entsperren abgebrochen."
        case .abfrageNochNichtMoeglich: return "Heimcloud ist gesperrt."
        case .speichern(let s), .lesen(let s), .loeschen(let s): return "Der Schlüsselbund meldet einen Fehler (\(s))."
        }
    }

    var errorDescription: String? { nutzerText }
}

/// Wie ein Eintrag geschützt ist.
enum KeychainSchutz: Sendable, Equatable {
    /// `.userPresence` (Face ID oder Code) und `WhenUnlockedThisDeviceOnly`.
    case abfrage
    /// `AfterFirstUnlockThisDeviceOnly` ohne Abfrage (Token und URL).
    case nachErstemEntsperren
    /// `WhenUnlockedThisDeviceOnly` ohne Abfrage (die Fenster-Kopie von K, nur lesbar bei entsperrtem Handy).
    case entsperrt
}

/// Der Zugriff auf den Schlüsselbund hinter einer kleinen Schnittstelle, damit Tests eine Attrappe im Speicher nehmen
/// (im ungesignierten Testlauf liefert der echte Schlüsselbund Fehler -34018).
protocol KeychainSpeicher: Sendable {
    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data?
    func schreiben(_ konto: String, daten: Data, schutz: KeychainSchutz) throws
    func loeschen(_ konto: String) throws
}

/// Der echte Schlüsselbund (generisches Passwort). Ohne `kSecAttrAccessGroup`: Der Eintrag landet in der ersten Gruppe der
/// Entitlements, und das ist in App und beiden Erweiterungen `$(AppIdentifierPrefix)com.onlyus.heimherz`.
struct SecItemSpeicher: KeychainSpeicher {
    let dienst: String

    private func basis(_ konto: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst, kSecAttrAccount as String: konto]
    }

    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data? {
        var q = basis(konto)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        if let kontext { q[kSecUseAuthenticationContext as String] = kontext.kontext }
        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &ergebnis)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed { throw SchluesselbundFehler.entsperrenAbgebrochen }
        if status == errSecInteractionNotAllowed { throw SchluesselbundFehler.abfrageNochNichtMoeglich }
        guard status == errSecSuccess, let daten = ergebnis as? Data else { throw SchluesselbundFehler.lesen(status) }
        return daten
    }

    func schreiben(_ konto: String, daten: Data, schutz: KeychainSchutz) throws {
        var q = basis(konto)
        q[kSecValueData as String] = daten
        switch schutz {
        case .abfrage:
            var fehler: Unmanaged<CFError>?
            guard let zugriff = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &fehler) else {
                throw SchluesselbundFehler.speichern(errSecParam)
            }
            q[kSecAttrAccessControl as String] = zugriff
        case .nachErstemEntsperren:
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .entsperrt:
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try loeschen(konto)
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SchluesselbundFehler.speichern(status) }
    }

    func loeschen(_ konto: String) throws {
        let status = SecItemDelete(basis(konto) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SchluesselbundFehler.loeschen(status) }
    }
}

/// Server-Adresse und Geräte-Token dieses Handys (aus dem Koppeln).
struct Geraet: Sendable, Equatable {
    let url: URL
    let token: String
}

/// Tresorschlüssel K, Geräte-Token und Server-URL im Schlüsselbund (SPEC 8).
/// K braucht Face ID oder Code (`.userPresence`, nur dieses Gerät, nur entsperrt); Token und URL nicht, damit App und Erweiterungen
/// ohne Abfrage wissen, ob und wohin gekoppelt ist. Beim Laden von K kann ein `EntsperrKontext` übergeben werden.
///
/// Entsperr-Fenster (SPEC 2, 10): Nach einem erfolgreichen Face ID liegt eine zweite Kopie von K ohne `.userPresence` im Schlüsselbund
/// (`WhenUnlockedThisDeviceOnly`, gleiche Zugriffsgruppe, also auch für die Erweiterung lesbar). Mit ihr sind K und damit der Tresor
/// `entsperrDauer` lang ohne neue Abfrage nutzbar, in App und Erweiterung. Die Kopie trägt den Zeitpunkt des Öffnens (nicht des Ablaufs):
/// Gelesen wird sie nur, wenn dieser höchstens so weit zurückliegt wie die jetzige Dauer. Eine verkürzte Dauer, `.aus`, eine zurückgestellte Uhr
/// oder ein kaputter Inhalt löschen sie beim nächsten Lesen.
struct Schluesselbund: Sendable {
    static let kontoSchluessel = "tresorschluessel"
    static let kontoFenster = "tresorschluessel-fenster"
    static let kontoToken = "geraetetoken"
    static let kontoURL = "serverurl"

    /// Der echte Schlüsselbund dieser App-Gruppe.
    static let live = Schluesselbund(speicher: SecItemSpeicher(dienst: Kennungen.schluesselbundDienst))

    let speicher: any KeychainSpeicher
    /// Wie lange ein Face ID reicht. Wird bei jedem Aufruf neu gelesen (die Einstellungen ändern sich zur Laufzeit).
    var dauer: @Sendable () -> EntsperrDauer = { GeteilteEinstellungen().entsperrDauer }
    var jetzt: @Sendable () -> Date = { Date() }

    func speichereSchluessel(_ schluessel: SymmetricKey) throws {
        schliesseFenster()   // neues K: die Kopie des alten darf nicht weiterleben
        try speicher.schreiben(Self.kontoSchluessel, daten: schluessel.withUnsafeBytes { Data($0) }, schutz: .abfrage)
    }

    /// Lädt K. Ist das Entsperr-Fenster offen, kommt K ohne Abfrage daher. Sonst fragt das (je nach Kontext) nach Face ID oder Code
    /// und blockiert dabei: läuft darum abseits des Hauptthreads. Nach einem Erfolg der Abfrage öffnet sich das Fenster.
    /// nil, wenn nie gekoppelt wurde.
    @concurrent
    func ladeSchluessel(kontext: EntsperrKontext? = nil) async throws -> SymmetricKey? {
        if let k = fensterSchluessel() { return k }
        guard let roh = try speicher.lesen(Self.kontoSchluessel, kontext: kontext) else { return nil }
        let k = try TresorSchluessel.aus(roh)
        oeffneFenster(k)
        return k
    }

    // MARK: Entsperr-Fenster

    /// K aus der Fenster-Kopie, ohne Abfrage. nil, wenn kein gültiges Fenster offen ist (dann ist die Kopie auch gelöscht).
    func fensterSchluessel() -> SymmetricKey? {
        let erlaubt = dauer()
        guard erlaubt != .aus else {
            schliesseFenster()
            return nil
        }
        // Ein Lesefehler (z. B. Handy gesperrt) heißt nur: jetzt kein Fenster. Gelöscht wird nur, was wirklich ungültig ist.
        guard let roh = try? speicher.lesen(Self.kontoFenster, kontext: nil) else { return nil }
        let bits = roh.count > 8 ? roh.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } : 0
        let geoeffnet = Date(timeIntervalSince1970: Double(bitPattern: UInt64(bigEndian: bits)))
        let alter = jetzt().timeIntervalSince(geoeffnet)
        guard roh.count > 8, alter >= 0, alter < erlaubt.sekunden, let k = try? TresorSchluessel.aus(Data(roh.dropFirst(8))) else {
            schliesseFenster()
            return nil
        }
        return k
    }

    var fensterOffen: Bool { fensterSchluessel() != nil }

    /// Legt die Kopie von K an (Zeitpunkt + K). Bei `.aus` stattdessen schließen. Fehler schlucken: ohne Kopie fragt es eben wieder nach Face ID.
    func oeffneFenster(_ k: SymmetricKey) {
        guard dauer() != .aus else { return schliesseFenster() }
        var daten = withUnsafeBytes(of: jetzt().timeIntervalSince1970.bitPattern.bigEndian) { Data($0) }
        daten.append(k.withUnsafeBytes { Data($0) })
        try? speicher.schreiben(Self.kontoFenster, daten: daten, schutz: .entsperrt)
    }

    /// Kopie löschen: beim Sperren, Entkoppeln, Neu-Koppeln und wenn sie ungültig ist.
    func schliesseFenster() { try? speicher.loeschen(Self.kontoFenster) }

    func speichereGeraet(_ geraet: Geraet) throws {
        try speicher.schreiben(Self.kontoURL, daten: Data(geraet.url.absoluteString.utf8), schutz: .nachErstemEntsperren)
        try speicher.schreiben(Self.kontoToken, daten: Data(geraet.token.utf8), schutz: .nachErstemEntsperren)
    }

    /// nil, wenn nicht gekoppelt. Ohne Abfrage.
    func ladeGeraet() throws -> Geraet? {
        guard let u = try speicher.lesen(Self.kontoURL, kontext: nil), let t = try speicher.lesen(Self.kontoToken, kontext: nil),
              let url = URL(string: String(decoding: u, as: UTF8.self)) else { return nil }
        return Geraet(url: url, token: String(decoding: t, as: UTF8.self))
    }

    /// Entkoppeln: K (samt Fenster-Kopie), Token und URL weg. Der Tresor am PC bleibt unberührt.
    /// Versucht alle und meldet den ersten Fehler erst danach, damit nichts halb gelöscht stehen bleibt, nur weil ein Eintrag klemmt.
    func vergiss() throws {
        var erster: Error?
        for konto in [Self.kontoFenster, Self.kontoSchluessel, Self.kontoToken, Self.kontoURL] {
            do { try speicher.loeschen(konto) } catch { erster = erster ?? error }
        }
        if let erster { throw erster }
    }
}
