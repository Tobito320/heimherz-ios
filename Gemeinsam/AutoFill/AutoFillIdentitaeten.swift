import AuthenticationServices
import Foundation

/// Die Identitäten für iOS (QuickType-Leiste): nur Host, Benutzer und Eintrag-id, nie ein Passwort oder TOTP-Geheimnis (SPEC 9).
/// Das Passwort holt die Erweiterung erst beim Antippen aus dem verschlüsselten Cache.
enum AutoFillIdentitaeten {
    /// Pro lebendigem Login mit Benutzer und je Host der URLs eine Passwort-Identität; zusätzlich je Host eine Einmalcode-Identität,
    /// wenn der Eintrag ein lesbares TOTP hat. Notizen, Grabsteine und Einträge ohne Host kommen nicht vor.
    static func baue(aus tresor: Tresor) -> [any ASCredentialIdentity] {
        var liste: [any ASCredentialIdentity] = []
        for eintrag in tresor.lebendige where eintrag.art == Eintrag.artLogin {
            let hosts = EintragSuche.hosts(von: eintrag)
            let hatCode = TOTP.einstellung(aus: eintrag.totp) != nil
            for host in hosts {
                let dienst = ASCredentialServiceIdentifier(identifier: host, type: .domain)
                if !eintrag.benutzer.isEmpty {
                    let identitaet = ASPasswordCredentialIdentity(serviceIdentifier: dienst, user: eintrag.benutzer, recordIdentifier: eintrag.id)
                    identitaet.rank = eintrag.favorit ? 1 : 0
                    liste.append(identitaet)
                }
                if hatCode {
                    let name = eintrag.name.isEmpty ? host : eintrag.name
                    let label = eintrag.benutzer.isEmpty ? name : "\(name) (\(eintrag.benutzer))"
                    liste.append(ASOneTimeCodeCredentialIdentity(serviceIdentifier: dienst, label: label, recordIdentifier: eintrag.id))
                }
            }
        }
        return liste
    }

    /// Ersetzt die Identitäten im System durch die des Tresors. true = angenommen. false, wenn die Erweiterung in den Einstellungen
    /// (noch) aus ist: dann lehnt das System ab, das ist kein Fehler der App.
    /// Läuft abseits des Hauptthreads: das System ruft den Abschluss auf einer eigenen Warteschlange.
    @concurrent
    static func setze(_ tresor: Tresor) async -> Bool {
        let identitaeten = baue(aus: tresor)
        return await withCheckedContinuation { weiter in
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(identitaeten) { erfolg, _ in
                weiter.resume(returning: erfolg)
            }
        }
    }

    /// Entkoppeln: nichts mehr anbieten.
    @concurrent
    static func leeren() async {
        await withCheckedContinuation { (weiter: CheckedContinuation<Void, Never>) in
            ASCredentialIdentityStore.shared.removeAllCredentialIdentities { _, _ in weiter.resume() }
        }
    }
}
