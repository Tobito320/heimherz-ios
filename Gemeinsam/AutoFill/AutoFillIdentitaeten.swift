import AuthenticationServices
import Foundation

/// Die Identitäten für iOS (QuickType-Leiste): nur Host, Benutzer und Eintrag-id, nie ein Passwort oder TOTP-Geheimnis (SPEC 9).
/// Das Passwort holt die Erweiterung erst beim Antippen aus dem verschlüsselten Cache.
enum AutoFillIdentitaeten {
    /// Pro lebendigem Login mit Benutzer und je Host der URLs eine Passwort-Identität; zusätzlich je Host eine Einmalcode-Identität,
    /// wenn der Eintrag ein lesbares TOTP hat, und je lesbarem Passkey eine Passkey-Identität. Notizen und Grabsteine kommen nicht vor.
    /// Reihenfolge der Vorschläge (W-030): automatisch nach Nutzung. Je Benutzung 10 Punkte, dazu bis 9 für Frische (zuletzt in 7 Tagen 9,
    /// in 30 Tagen 5, sonst 0). Ein von Hand gesetzter Favorit gewinnt nur bei Gleichstand (+1). Höher = weiter vorn.
    static func rang(favorit: Bool, benutzungen: Int, zuletzt: Date? = nil, jetzt: Date = Date()) -> Int {
        let tage = zuletzt.map { jetzt.timeIntervalSince($0) / 86_400 }
        let frische = tage.map { $0 <= 7 ? 9 : ($0 <= 30 ? 5 : 0) } ?? 0
        return min(benutzungen, 9_999) * 10 + frische + (favorit ? 1 : 0)
    }

    /// Ein Eintrag zeigt eine Seite nur einmal: ist ein Host Unterdomain eines anderen Hosts desselben Eintrags, genügt der obere
    /// (iOS gleicht Unterdomains mit der Domain ab; sonst erschien ein Konto mit sso.web.x.de und web.x.de doppelt).
    static func ohneUnterdomains(_ hosts: [String]) -> [String] {
        hosts.filter { h in !hosts.contains { $0 != h && h.hasSuffix("." + $0) } }
    }

    static func baue(aus tresor: Tresor, nutzung: [String: Int] = [:], zuletzt: [String: Date] = [:]) -> [any ASCredentialIdentity] {
        var liste: [any ASCredentialIdentity] = []
        for eintrag in tresor.lebendige where eintrag.art == Eintrag.artLogin {
            let hosts = ohneUnterdomains(EintragSuche.hosts(von: eintrag))
            let rang = rang(favorit: eintrag.favorit, benutzungen: nutzung[eintrag.id] ?? 0, zuletzt: zuletzt[eintrag.id])
            let hatCode = TOTP.einstellung(aus: eintrag.totp) != nil
            for host in hosts {
                let dienst = ASCredentialServiceIdentifier(identifier: host, type: .domain)
                if !eintrag.benutzer.isEmpty {
                    let identitaet = ASPasswordCredentialIdentity(serviceIdentifier: dienst, user: eintrag.benutzer, recordIdentifier: eintrag.id)
                    identitaet.rank = rang
                    liste.append(identitaet)
                }
                if hatCode {
                    let name = eintrag.name.isEmpty ? host : eintrag.name
                    let label = eintrag.benutzer.isEmpty ? name : "\(name) (\(eintrag.benutzer))"
                    liste.append(ASOneTimeCodeCredentialIdentity(serviceIdentifier: dienst, label: label, recordIdentifier: eintrag.id))
                }
            }
            // Passkeys (SPEC 24): Kennung und Benutzer, nie der Schlüssel.
            for p in Passkeys.von(eintrag) {
                liste.append(ASPasskeyCredentialIdentity(relyingPartyIdentifier: p.rpId, userName: p.userName, credentialID: p.credentialID,
                                                         userHandle: p.userHandle, recordIdentifier: eintrag.id))
            }
        }
        return liste
    }

    /// Ersetzt die Identitäten im System durch die des Tresors. true = angenommen. false, wenn die Erweiterung in den Einstellungen
    /// (noch) aus ist: dann lehnt das System ab, das ist kein Fehler der App.
    /// Läuft abseits des Hauptthreads: das System ruft den Abschluss auf einer eigenen Warteschlange.
    @concurrent
    static func setze(_ tresor: Tresor, nutzung: [String: Int] = [:], zuletzt: [String: Date] = [:]) async -> Bool {
        let identitaeten = baue(aus: tresor, nutzung: nutzung, zuletzt: zuletzt)
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
