import Foundation

/// Feste Namen, die App und beide Erweiterungen teilen (SPEC 8). Müssen zu `project.yml` und den `.entitlements` passen.
enum Kennungen {
    static let appGruppe = "group.com.onlyus.heimherz"
    static let schluesselbundDienst = "com.onlyus.heimherz"
    static let urlSchema = "heimherz"

    /// Ordner der App Group; nil im Testlauf ohne Signierung und im Simulator ohne Entitlement.
    static func gruppenOrdner() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGruppe)
    }
}
