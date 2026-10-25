import AuthenticationServices
import SwiftUI
import UIKit

/// Die AutoFill-Erweiterung (SPEC 10). Dieser Controller übersetzt nur zwischen dem System und `AutoFillModell`; der Ablauf liegt in `Gemeinsam/AutoFill`.
/// Quellen (Apple-Doku, Stand 25.10.2026): ASCredentialProviderViewController, ASCredentialProviderExtensionContext, ASSavePasswordRequest,
/// ASGeneratePasswordsRequest, ASGeneratedPassword (alles AuthenticationServices; Speichern und Erzeugen ab iOS 26.2).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var modell: AutoFillModell?
    private var hosting: UIHostingController<AutoFillWurzel>?

    // MARK: Passwörter und Einmalcodes

    /// Liste: Konten passend zur Domain zuerst, Suche über alle.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        zeige(.liste(hosts: EintragSuche.hosts(von: serviceIdentifiers), codes: false))
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        zeige(.liste(hosts: EintragSuche.hosts(von: serviceIdentifiers), codes: true))
    }

    /// Der Schlüssel K liegt hinter Face ID (`.userPresence`): ohne Abfrage geht es nie, also immer über die Oberfläche.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        meldeFehler(.userInteractionRequired)
    }

    /// Ein Konto aus der Vorschlagsleiste: einmal Face ID, dann das Passwort oder den Einmalcode liefern.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard let id = credentialRequest.credentialIdentity.recordIdentifier else { return meldeFehler(.credentialIdentityNotFound) }
        if credentialRequest is ASOneTimeCodeCredentialRequest {
            zeige(.anfrage(id: id, codes: true))
        } else if credentialRequest is ASPasswordCredentialRequest {
            zeige(.anfrage(id: id, codes: false))
        } else {
            meldeFehler(.failed)   // Passkeys gibt es erst in Phase 2
        }
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
        }
    }

    private func meldeFehler(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}
