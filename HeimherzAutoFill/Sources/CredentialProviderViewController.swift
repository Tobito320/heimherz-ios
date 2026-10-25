import AuthenticationServices

/// Stub (T4): bricht jede Anfrage ab. Das Modul `ios-autofill` (T8) ersetzt diese Datei.
/// Die gemeinsame Logik liegt in `Gemeinsam/` (TresorDienst, Schluesselbund, TOTP).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
    }
}
