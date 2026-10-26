import CryptoKit
import Foundation

/// Der Inhalt eines Koppel-Links: Adresse des PCs, Geräte-Token und Tresorschlüssel K (roh, 32 Byte).
struct KoppelDaten: Sendable, Equatable {
    let url: URL
    let token: String
    let schluessel: Data
}

enum KoppelFehler: Error, Equatable, LocalizedError {
    case keinKoppelLink
    case adresseFehlt
    case nurHttps
    case keinTailnet
    case tokenUngueltig
    case schluesselUngueltig

    var nutzerText: String {
        switch self {
        case .keinKoppelLink: return "Das ist kein Lumen-Cloud-Koppel-Link."
        case .adresseFehlt: return "Im Link fehlt die Adresse des PCs."
        case .nurHttps: return "Die Adresse muss mit https:// beginnen."
        case .keinTailnet: return "Die Adresse muss ein Tailscale-Name sein (endet auf .ts.net)."
        case .tokenUngueltig: return "Das Geräte-Token im Link ist ungültig."
        case .schluesselUngueltig: return "Der Schlüssel im Link ist ungültig."
        }
    }

    var errorDescription: String? { nutzerText }
}

/// `heimherz://koppeln?url=<prozentkodiert>&token=<b64url>&schluessel=<b64url>` (SPEC 7). Token und Schlüssel sind je 32 Byte, b64url ohne Füllzeichen.
enum KoppelLink {
    static func lese(_ text: String) throws -> KoppelDaten {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let teile = URLComponents(string: t), teile.scheme?.lowercased() == Kennungen.urlSchema,
              teile.host?.lowercased() == "koppeln" else { throw KoppelFehler.keinKoppelLink }
        let werte = Dictionary((teile.queryItems ?? []).compactMap { e in e.value.map { (e.name, $0) } }, uniquingKeysWith: { erster, _ in erster })
        guard let adresse = werte["url"], !adresse.isEmpty else { throw KoppelFehler.adresseFehlt }
        guard let url = URL(string: adresse), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            throw KoppelFehler.nurHttps
        }
        // Der Link enthält den Schlüssel zu allen Passwörtern: nur der eigene Tailnet-Name, nie eine fremde Adresse.
        guard host.lowercased().hasSuffix(".ts.net") else { throw KoppelFehler.keinTailnet }
        guard let token = werte["token"], base64url(token)?.count == 32 else { throw KoppelFehler.tokenUngueltig }
        guard let k = werte["schluessel"], let roh = base64url(k), roh.count == 32 else { throw KoppelFehler.schluesselUngueltig }
        return KoppelDaten(url: url, token: token, schluessel: roh)
    }

    /// b64url ohne Füllzeichen; andere Zeichen (auch `+`, `/`, `=`) sind ungültig.
    static func base64url(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }) else { return nil }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

enum Koppeln {
    /// Prüft den Link, fragt den PC (`GET /v1/status`) und speichert Schlüssel, URL und Token erst, wenn das klappt.
    static func koppeln(link: String, bund: Schluesselbund, sitzung: URLSession = .shared) async throws -> ServerStatus {
        let daten = try KoppelLink.lese(link)
        let status = try await HeimClient(basis: daten.url, token: daten.token, sitzung: sitzung).status()
        try bund.speichereSchluessel(try TresorSchluessel.aus(daten.schluessel))
        try bund.speichereGeraet(Geraet(url: daten.url, token: daten.token))
        return status
    }
}
