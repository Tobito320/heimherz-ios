import AuthenticationServices
import Foundation

/// Übersetzt die Apple-Typen des Credential Exchange (iOS 26, `ASExportedCredentialData`) in `ImportKonto`. Nur Lesen und Umformen, kein Speichern.
/// Belegt in der Apple-Dokumentation: `ASImportableAccount.items`, `ASImportableItem.title/subtitle/favorite/scope/credentials`,
/// `ASImportableCredential` (`basicAuthentication`, `totp`, `passkey`, `note`), `ASImportableEditableField.value`.
enum CredentialImportAdapter {
    static func konten(aus daten: ASExportedCredentialData) -> (konten: [ImportKonto], uebersprungen: Int) {
        var konten: [ImportKonto] = []
        var uebersprungen = 0
        for konto in daten.accounts {
            for item in konto.items {
                if let k = umwandeln(item) { konten.append(k) } else { uebersprungen += 1 }
            }
        }
        return (konten, uebersprungen)
    }

    /// nil für alles, was Heim nicht kennt (WLAN, Karten, Ausweise, SSH-Schlüssel, API-Schlüssel) oder was leer ist.
    private static func umwandeln(_ item: ASImportableItem) -> ImportKonto? {
        var k = ImportKonto(titel: item.title, favorit: item.favorite)
        var hatBasis = false
        var notizen: [String] = []
        var benutzerTotp = ""
        for credential in item.credentials {
            switch credential {
            case .basicAuthentication(let b):
                if !hatBasis {
                    hatBasis = true
                    k.benutzer = b.userName?.value ?? ""
                    k.passwort = b.password?.value ?? ""
                }
            case .totp(let t):
                if k.totp.isEmpty, !t.secret.isEmpty {
                    benutzerTotp = t.userName ?? ""
                    k.totp = ImportAbbildung.totpURI(geheim: t.secret, periode: Int(t.period), stellen: Int(t.digits), algorithmus: algorithmus(t.algorithm),
                                                     aussteller: t.issuer, benutzer: t.userName)
                }
            case .passkey(let p):
                k.passkeys.append(ImportPasskey(credentialId: ImportAbbildung.base64url(p.credentialID), rpId: p.relyingPartyIdentifier, userName: p.userName,
                                                userDisplayName: p.userDisplayName, userHandle: ImportAbbildung.base64url(p.userHandle),
                                                schluessel: ImportAbbildung.base64url(p.key)))
            case .note(let n):
                if !n.content.value.isEmpty { notizen.append(n.content.value) }
            default:
                break
            }
        }
        k.urls = (item.scope?.urls ?? []).map(\.absoluteString)
        k.notiz = notizen.joined(separator: "\n\n")
        if k.benutzer.isEmpty { k.benutzer = k.passkeys.first?.userName ?? benutzerTotp }
        if hatBasis || !k.passkeys.isEmpty || !k.totp.isEmpty { return k }
        if !k.notiz.isEmpty {
            k.art = Eintrag.artNotiz
            return k
        }
        return nil
    }

    private static func algorithmus(_ a: ASImportableCredential.TOTP.Algorithm) -> String {
        switch a {
        case .sha256: return "SHA256"
        case .sha512: return "SHA512"
        default: return "SHA1"
        }
    }
}
