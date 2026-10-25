import AuthenticationServices
import SwiftUI
import UIKit

/// Die AutoFill-Erweiterung (SPEC 10). Dieser Controller übersetzt nur zwischen dem System und `AutoFillModell`; der Ablauf liegt in `Gemeinsam/AutoFill`.
/// Quellen (Apple-Doku, Stand 25.10.2026): ASCredentialProviderViewController, ASCredentialProviderExtensionContext, ASSavePasswordRequest,
/// ASGeneratePasswordsRequest, ASGeneratedPassword (alles AuthenticationServices; Speichern und Erzeugen ab iOS 26.2),
/// ASPasskeyCredentialRequest, ASPasskeyCredentialRequestParameters, ASPasskeyAssertionCredential, ASPasskeyRegistrationCredential (Passkeys, SPEC 24).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var modell: AutoFillModell?
    private var hosting: UIHostingController<AutoFillWurzel>?
    /// Face ID darf erst starten, wenn der Auftrag gesetzt ist und die Ansicht wirklich sichtbar ist (sonst -25308); die Reihenfolge der beiden ist nicht garantiert.
    private var sichtbar = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sichtbar = true
        if let modell { Task { await modell.ansichtIstAktiv() } }
    }

    // MARK: Passwörter und Einmalcodes

    /// Liste: Konten passend zur Domain zuerst, Suche über alle.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        zeige(.liste(hosts: EintragSuche.hosts(von: serviceIdentifiers), codes: false))
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        zeige(.liste(hosts: EintragSuche.hosts(von: serviceIdentifiers), codes: true))
    }

    /// Aus der Vorschlagsleiste ohne Blatt, nur bei offenem Entsperr-Fenster (SPEC 10) und wenn der Host der Identität zum Konto passt.
    /// Sonst `userInteractionRequired`: iOS zeigt dann das Blatt mit Face ID. Der Schlüssel K selbst bleibt hinter Face ID (`.userPresence`).
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        if let p = credentialRequest as? ASPasskeyCredentialRequest {
            guard let anfrage = Self.anfrage(p), let sitzung = try? AutoFillSitzung.live() else { return meldeFehler(.userInteractionRequired) }
            return starteStill(.passkey(anfrage), sitzung: sitzung)
        }
        let identitaet = credentialRequest.credentialIdentity
        let codes = credentialRequest is ASOneTimeCodeCredentialRequest
        guard let id = identitaet.recordIdentifier, codes || credentialRequest is ASPasswordCredentialRequest,
              let host = EintragSuche.host(von: identitaet.serviceIdentifier),   // `.app` ohne Host: Blatt
              let sitzung = try? AutoFillSitzung.live() else { return meldeFehler(.userInteractionRequired) }
        starteStill(.anfrage(id: id, codes: codes, host: host), sitzung: sitzung)
    }

    private func starteStill(_ auftrag: AutoFillAuftrag, sitzung: AutoFillSitzung) {
        let still = AutoFillModell(auftrag: auftrag, sitzung: sitzung)
        still.abschluss = { [weak self] ergebnis in self?.beenden(ergebnis) }
        Task { await still.starteOhneAbfrage() }
    }

    /// Ein Konto aus der Vorschlagsleiste: einmal Face ID, dann das Passwort oder den Einmalcode liefern.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        if let p = credentialRequest as? ASPasskeyCredentialRequest {
            guard let anfrage = Self.anfrage(p) else { return meldeFehler(.credentialIdentityNotFound) }
            return zeige(.passkey(anfrage))
        }
        guard let id = credentialRequest.credentialIdentity.recordIdentifier else { return meldeFehler(.credentialIdentityNotFound) }
        let host = EintragSuche.host(von: credentialRequest.credentialIdentity.serviceIdentifier)
        if credentialRequest is ASOneTimeCodeCredentialRequest {
            zeige(.anfrage(id: id, codes: true, host: host))
        } else if credentialRequest is ASPasswordCredentialRequest {
            zeige(.anfrage(id: id, codes: false, host: host))
        } else {
            meldeFehler(.failed)
        }
    }

    // MARK: Passkeys (SPEC 24)

    /// Liste für eine Passkey-Anmeldung ("Andere Optionen"): ein Passkey = sofort nach Face ID, mehrere = Auswahl, keiner = Passwörter der Seite.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier], requestParameters: ASPasskeyCredentialRequestParameters) {
        zeige(.passkey(PasskeyAnfrage(rpId: requestParameters.relyingPartyIdentifier, clientDataHash: requestParameters.clientDataHash,
                                      erlaubt: requestParameters.allowedCredentials)))
    }

    /// Die Seite will einen neuen Passkey; iOS hat schon gefragt, ob er in Heim gesichert werden soll. Nur ES256 (P-256).
    override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        guard let p = registrationRequest as? ASPasskeyCredentialRequest, let i = p.credentialIdentity as? ASPasskeyCredentialIdentity,
              p.supportedAlgorithms.isEmpty || p.supportedAlgorithms.contains(.ES256) else { return meldeFehler(.failed) }
        zeige(.passkeyNeu(PasskeyRegistrierung(rpId: i.relyingPartyIdentifier, userName: i.userName, userHandle: i.userHandle,
                                               clientDataHash: p.clientDataHash, ausgeschlossen: (p.excludedCredentials ?? []).map(\.credentialID))))
    }

    /// Anmelden mit genau dem Passkey der gewählten Identität.
    private static func anfrage(_ p: ASPasskeyCredentialRequest) -> PasskeyAnfrage? {
        guard let i = p.credentialIdentity as? ASPasskeyCredentialIdentity else { return nil }
        return PasskeyAnfrage(rpId: i.relyingPartyIdentifier, clientDataHash: p.clientDataHash, credentialID: i.credentialID)
    }

    // MARK: Speichern und Erzeugen (iOS 26.2)

    @available(iOS 26.2, *)
    override func performWithoutUserInteractionIfPossible(savePasswordRequest: ASSavePasswordRequest) {
        meldeFehler(.userInteractionRequired)
    }

    @available(iOS 26.2, *)
    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        let dienst = savePasswordRequest.serviceIdentifier
        let host = EintragSuche.host(von: dienst)
        let name = savePasswordRequest.title ?? dienst.displayName ?? host ?? dienst.identifier
        zeige(.speichern(SpeicherAnfrage(host: host, name: name, benutzer: savePasswordRequest.credential.user,
                                         passwort: savePasswordRequest.credential.password,
                                         sofort: savePasswordRequest.event == .userInitiated)))
    }

    /// Passwort-Vorschläge brauchen keinen Schlüssel und keine Oberfläche (`SupportsGeneratePasswordCredentialsWithUI` = false in der Info.plist).
    @available(iOS 26.2, *)
    override func performWithoutUserInteraction(generatePasswordsRequest: ASGeneratePasswordsRequest) {
        var zufall = SystemRandomNumberGenerator()
        let vorschlaege = PasswortVorschlaege.erzeuge(
            regeln: [generatePasswordsRequest.passwordFieldPasswordRules, generatePasswordsRequest.passwordRulesFromQuirks], mit: &zufall)
        let ergebnisse = vorschlaege.map { v -> ASGeneratedPassword in
            let art: ASGeneratedPassword.Kind
            switch v.art {
            case .stark: art = .strong
            case .alphanumerisch: art = .alphanumeric
            case .wortgruppe: art = .passphrase
            }
            return ASGeneratedPassword(kind: art, value: v.wert)
        }
        extensionContext.completeGeneratePasswordRequest(results: ergebnisse, completionHandler: nil)
    }

    // MARK: Einstellungen

    /// Kommt nach dem Einschalten in den Einstellungen (Info.plist `ShowsConfigurationUI`).
    override func prepareInterfaceForExtensionConfiguration() {
        zeige(.konfiguration)
    }

    // MARK: Oberfläche

    private func zeige(_ auftrag: AutoFillAuftrag) {
        var sitzung: AutoFillSitzung?
        var startFehler: String?
        do {
            sitzung = try AutoFillSitzung.live()
        } catch {
            startFehler = FehlerText.von(error)
        }
        modell?.abschluss = { _ in }   // ein ersetztes Modell darf nichts mehr ans System melden
        let neu = AutoFillModell(auftrag: auftrag, sitzung: sitzung, startFehler: startFehler)
        neu.abschluss = { [weak self] ergebnis in self?.beenden(ergebnis) }
        modell = neu
        if sichtbar {
            Task { await neu.ansichtIstAktiv() }
        } else {
            // Falls viewDidAppear nie kommt: sonst bliebe die Oberfläche tot. Das -25308-Nachholen im Modell fängt zu frühes Starten ab.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if let self, self.modell === neu { await neu.ansichtIstAktiv() }
            }
        }
        entferneOberflaeche()
        let controller = UIHostingController(rootView: AutoFillWurzel(modell: neu))
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        hosting = controller
    }

    private func entferneOberflaeche() {
        guard let alt = hosting else { return }
        alt.willMove(toParent: nil)
        alt.view.removeFromSuperview()
        alt.removeFromParent()
        hosting = nil
    }

    // MARK: Antworten

    private func beenden(_ ergebnis: AutoFillErgebnis) {
        switch ergebnis {
        case .passwort(let benutzer, let passwort):
            extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: benutzer, password: passwort), completionHandler: nil)
        case .code(let code):
            extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code), completionHandler: nil)
        case .gespeichert:
            if #available(iOS 26.2, *) { extensionContext.completeSavePasswordRequest(completionHandler: nil) }
        case .konfigurationFertig:
            extensionContext.completeExtensionConfigurationRequest()
        case .abgebrochen:
            meldeFehler(.userCanceled)
        case .nichtGefunden:
            meldeFehler(.credentialIdentityNotFound)
        case .fehlgeschlagen:
            meldeFehler(.failed)
        case .abfrageNoetig:
            meldeFehler(.userInteractionRequired)
        case .passkeyAnmeldung(let a):
            let antwort = ASPasskeyAssertionCredential(userHandle: a.userHandle, relyingParty: a.rpId, signature: a.signatur,
                                                       clientDataHash: a.clientDataHash, authenticatorData: a.authenticatorData, credentialID: a.credentialID)
            extensionContext.completeAssertionRequest(using: antwort, completionHandler: nil)
        case .passkeyAngelegt(let a):
            let antwort = ASPasskeyRegistrationCredential(relyingParty: a.rpId, clientDataHash: a.clientDataHash, credentialID: a.credentialID,
                                                          attestationObject: a.attestation)
            extensionContext.completeRegistrationRequest(using: antwort, completionHandler: nil)
        case .passkeySchonDa:
            meldeFehler(.matchedExcludedCredential)
        }
    }

    private func meldeFehler(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}
