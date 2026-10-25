import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// Was von Apple Passwörter angekommen ist und noch in den Tresor soll (Credential Exchange, iOS 26).
struct ImportPaket: Equatable, Sendable {
    let konten: [ImportKonto]
    let uebersprungen: Int
}

/// Nimmt den Start der App durch "Daten an andere App exportieren" an: das System startet die App mit einer `NSUserActivity`, aus der kommt ein
/// Token, mit dem `ASCredentialImportManager.importCredentials(token:)` die Daten liefert. Die Daten liegen nur im Speicher, bis der Tresor entsperrt
/// ist; dann mischt `TresorStore.importiere` sie ein (Klartext nie auf Platte, nie im Log).
@MainActor @Observable
final class ImportPostfach {
    static let geteilt = ImportPostfach()

    private(set) var paket: ImportPaket?
    private(set) var ergebnis: ImportZaehler?
    private(set) var fehler: String?
    private(set) var holt = false
    @ObservationIgnored private var letzterToken: UUID?

    init() {}

    /// Ein Token wird nur einmal angenommen (die Aktivität kann doppelt ankommen).
    func empfange(token: UUID) {
        guard token != letzterToken else { return }
        letzterToken = token
        holt = true
        fehler = nil
        Task { await hole(token: token) }
    }

    private func hole(token: UUID) async {
        defer { holt = false }
        do {
            let daten = try await ASCredentialImportManager().importCredentials(token: token)
            let gelesen = CredentialImportAdapter.konten(aus: daten)
            paket = ImportPaket(konten: gelesen.konten, uebersprungen: gelesen.uebersprungen)
        } catch {
            fehler = "Der Import von Apple Passwörter hat nicht geklappt. Bitte versuche es noch einmal."
        }
    }

    /// Gibt das Paket genau einmal heraus.
    func nimm() -> ImportPaket? {
        defer { paket = nil }
        return paket
    }

    func zeige(_ z: ImportZaehler) { ergebnis = z }
    func zeigeFehler(_ text: String) { fehler = text }
    func schliesseErgebnis() { ergebnis = nil }
    func schliesseFehler() { fehler = nil }

    /// Alles verwerfen (entkoppelt oder gesperrt zu lange).
    func verwerfe() { paket = nil }
}

extension View {
    /// Hört auf den Start durch den Export aus Apple Passwörter. Die Konstanten sind die der Apple-Dokumentation (`ASCredentialExchangeActivity`, `ASCredentialImportToken`).
    func heimherzImportAnnahme() -> some View {
        onContinueUserActivity(ASCredentialExchangeActivity) { aktivitaet in
            guard let token = aktivitaet.userInfo?[ASCredentialImportToken] as? UUID else { return }
            Task { @MainActor in ImportPostfach.geteilt.empfange(token: token) }
        }
    }
}
