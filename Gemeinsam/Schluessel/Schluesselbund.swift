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

    var nutzerText: String {
        switch self {
        case .entsperrenAbgebrochen: return "Entsperren abgebrochen."
        case .speichern(let s), .lesen(let s), .loeschen(let s): return "Der Schlüsselbund meldet einen Fehler (\(s))."
        }
    }

    var errorDescription: String? { nutzerText }
}

/// Der Zugriff auf den Schlüsselbund hinter einer kleinen Schnittstelle, damit Tests eine Attrappe im Speicher nehmen
/// (im ungesignierten Testlauf liefert der echte Schlüsselbund Fehler -34018).
protocol KeychainSpeicher: Sendable {
    func lesen(_ konto: String, kontext: EntsperrKontext?) throws -> Data?
    /// `mitAbfrage`: Zugriff `.userPresence` (Face ID oder Code) und `WhenUnlockedThisDeviceOnly`; sonst `AfterFirstUnlockThisDeviceOnly` ohne Abfrage.
    func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws
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
        guard status == errSecSuccess, let daten = ergebnis as? Data else { throw SchluesselbundFehler.lesen(status) }
        return daten
    }

    func schreiben(_ konto: String, daten: Data, mitAbfrage: Bool) throws {
        var q = basis(konto)
        q[kSecValueData as String] = daten
        if mitAbfrage {
            var fehler: Unmanaged<CFError>?
            guard let zugriff = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &fehler) else {
                throw SchluesselbundFehler.speichern(errSecParam)
            }
            q[kSecAttrAccessControl as String] = zugriff
        } else {
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
struct Schluesselbund: Sendable {
    static let kontoSchluessel = "tresorschluessel"
    static let kontoToken = "geraetetoken"
    static let kontoURL = "serverurl"

    /// Der echte Schlüsselbund dieser App-Gruppe.
    static let live = Schluesselbund(speicher: SecItemSpeicher(dienst: Kennungen.schluesselbundDienst))

    let speicher: any KeychainSpeicher

    func speichereSchluessel(_ schluessel: SymmetricKey) throws {
        try speicher.schreiben(Self.kontoSchluessel, daten: schluessel.withUnsafeBytes { Data($0) }, mitAbfrage: true)
    }

    /// Lädt K. Fragt (je nach Kontext) nach Face ID oder Code und blockiert dabei: läuft darum abseits des Hauptthreads.
    /// nil, wenn nie gekoppelt wurde.
    @concurrent
    func ladeSchluessel(kontext: EntsperrKontext? = nil) async throws -> SymmetricKey? {
        guard let roh = try speicher.lesen(Self.kontoSchluessel, kontext: kontext) else { return nil }
        return try TresorSchluessel.aus(roh)
    }

    func speichereGeraet(_ geraet: Geraet) throws {
        try speicher.schreiben(Self.kontoURL, daten: Data(geraet.url.absoluteString.utf8), mitAbfrage: false)
        try speicher.schreiben(Self.kontoToken, daten: Data(geraet.token.utf8), mitAbfrage: false)
    }

    /// nil, wenn nicht gekoppelt. Ohne Abfrage.
    func ladeGeraet() throws -> Geraet? {
        guard let u = try speicher.lesen(Self.kontoURL, kontext: nil), let t = try speicher.lesen(Self.kontoToken, kontext: nil),
              let url = URL(string: String(decoding: u, as: UTF8.self)) else { return nil }
        return Geraet(url: url, token: String(decoding: t, as: UTF8.self))
    }

    /// Entkoppeln: K, Token und URL weg. Der Tresor am PC bleibt unberührt.
    func vergiss() throws {
        for konto in [Self.kontoSchluessel, Self.kontoToken, Self.kontoURL] { try speicher.loeschen(konto) }
    }
}
