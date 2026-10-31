import FileProvider
import Foundation

/// Die Domain "Lumen Cloud" der Dateien-App (SPEC 31): wird angelegt, sobald das Handy gekoppelt ist, und beim Entkoppeln entfernt
/// (iOS löscht dabei die lokalen Kopien; am PC bleibt alles). Die Erweiterung `HeimherzDateien` liefert den Inhalt.
enum DateienDomain {
    private static func neueDomain() -> NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(rawValue: DomainAktion.kennung), displayName: DomainAktion.anzeigename)
    }

    private static func vorhandene() async -> NSFileProviderDomain? {
        let alle = (try? await NSFileProviderManager.domains()) ?? []
        return alle.first { $0.identifier.rawValue == DomainAktion.kennung }
    }

    /// Beim Start und bei jedem Wechsel der Kopplung. Fehler (Erweiterung noch nicht bekannt, Simulator ohne Unterstützung) bleiben still: nächster Start versucht es wieder.
    static func abgleichen(gekoppelt: Bool) async {
        guard !AppUmgebung.istTestHost else { return }
        let da = await vorhandene()
        switch DomainAktion.bestimme(gekoppelt: gekoppelt, vorhanden: da != nil) {
        case .hinzufuegen: try? await NSFileProviderManager.add(neueDomain())
        case .entfernen: if let da { try? await NSFileProviderManager.remove(da) }
        case .nichts: break
        }
    }

    /// Sagt der Dateien-App, dass sie nach Änderungen am PC fragen soll. Ohne eigenen Push ist das der Weg: die App meldet es beim Öffnen
    /// (Apple: `signalEnumerator`); wann iOS sonst von selbst nachfragt, entscheidet iOS.
    static func melde() async {
        guard !AppUmgebung.istTestHost, let da = await vorhandene(), let manager = NSFileProviderManager(for: da) else { return }
        try? await manager.signalEnumerator(for: .workingSet)
    }
}
