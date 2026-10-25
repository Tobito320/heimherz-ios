import CoreSpotlight
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Was Spotlight von einem Konto erfährt: nur die id (zum Öffnen), der Titel und der Host. Nie Benutzer, Passwort, Notiz oder Code.
struct SpotlightEintrag: Equatable, Sendable {
    let id: String
    let titel: String
    let host: String
}

/// Der Spotlight-Index der Konten (CoreSpotlight), damit die iPhone-Suche "GitHub" findet und die App beim Konto öffnet.
/// Nur Logins (Notizen bleiben draußen, ihre Titel können Privates verraten). Der Index wird nach jedem Abgleich und jeder Änderung neu aufgebaut,
/// beim Sperren bleibt er stehen, beim Entkoppeln geht er weg (`leeren()`).
enum SpotlightIndex {
    static let bereich = "com.onlyus.heimherz.konten"
    private static let name = "heimherz"

    /// Die Daten für den Index aus dem Tresor: lebendige Logins mit Titel oder Host.
    static func eintraege(aus tresor: Tresor) -> [SpotlightEintrag] {
        tresor.lebendige.compactMap { e in
            guard e.art == Eintrag.artLogin else { return nil }
            let host = EintragSuche.hosts(von: e).first ?? ""
            let titel = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titel.isEmpty || !host.isEmpty else { return nil }
            return SpotlightEintrag(id: e.id, titel: titel.isEmpty ? host : titel, host: host)
        }
    }

    /// Ersetzt den ganzen Index durch diese Konten. Fehler (Index nicht verfügbar) bleiben still: Spotlight ist Zugabe.
    nonisolated static func setze(_ konten: [SpotlightEintrag]) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let index = CSSearchableIndex(name: name, protectionClass: .complete)
        let items = konten.map { k -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = k.titel
            a.displayName = k.titel
            if !k.host.isEmpty {
                a.contentDescription = k.host
                a.keywords = [k.host]
            }
            let item = CSSearchableItem(uniqueIdentifier: k.id, domainIdentifier: bereich, attributeSet: a)
            item.expirationDate = .distantFuture   // sonst verfällt der Eintrag nach einem Monat ohne neuen Aufbau
            return item
        }
        try? await index.deleteSearchableItems(withDomainIdentifiers: [bereich])
        if !items.isEmpty { try? await index.indexSearchableItems(items) }
    }

    /// Entkoppelt: der Index ist leer.
    nonisolated static func leeren() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex(name: name, protectionClass: .complete).deleteSearchableItems(withDomainIdentifiers: [bereich])
    }
}

/// Wohin die App will, weil ein Treffer in der iPhone-Suche angetippt wurde: die Eintrags-id, bis der Tresor offen ist.
/// Wie `ImportPostfach`: das System startet oder weckt die App mit einer `NSUserActivity`, die App holt die id ab, sobald sie entsperrt ist.
@MainActor @Observable
final class SpotlightPostfach {
    static let geteilt = SpotlightPostfach()

    private(set) var angefragt: String?
    @ObservationIgnored private var seit = Date.distantPast
    /// So lange darf eine Anfrage auf das Entsperren warten.
    static let wartezeit: TimeInterval = 300

    init() {}

    func empfange(id: String, jetzt: Date = Date()) {
        angefragt = id
        seit = jetzt
    }

    /// Gibt die Anfrage genau einmal heraus; eine zu alte oder unbekannte (Eintrag weg) wird verworfen.
    func nimm(in store: TresorStore, jetzt: Date = Date()) -> String? {
        defer { angefragt = nil }
        guard let id = angefragt, jetzt.timeIntervalSince(seit) <= Self.wartezeit, store.eintrag(id) != nil else { return nil }
        return id
    }

    func verwerfe() { angefragt = nil }
}

extension View {
    /// Hört auf den Tipp auf ein Konto in der iPhone-Suche (`CSSearchableItemActionType`, die id steckt unter `CSSearchableItemActivityIdentifier`).
    func heimherzSpotlightAnnahme() -> some View {
        onContinueUserActivity(CSSearchableItemActionType) { aktivitaet in
            guard let id = aktivitaet.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            Task { @MainActor in SpotlightPostfach.geteilt.empfange(id: id) }
        }
    }
}
