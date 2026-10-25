import SwiftUI

@main
struct HeimherzApp: App {
    @State private var umgebung = Self.waehleUmgebung()

    var body: some Scene {
        WindowGroup {
            AppRootView(tab: Self.startTab)
                .environment(umgebung)
        }
    }

    /// Debug-Argumente für Screenshots in CI: `-heimherzDemo YES` (erfundene Verbindung, keine Sperre, kein Netz),
    /// `-heimherzTab <passwoerter|fotos|dateien|mehr>`, `-heimherzOhnePC YES` (Demo ungekoppelt), `-heimherzKoppeln YES` (Koppel-Blatt offen).
    private static func waehleUmgebung() -> AppUmgebung {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "heimherzDemo") { return AppUmgebung.demo(ohnePC: defaults.bool(forKey: "heimherzOhnePC")) }
        #endif
        return AppUmgebung.geteilt
    }

    private static var startTab: HeimherzTab {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "heimherzTab"), let tab = HeimherzTab(rawValue: name) { return tab }
        #endif
        return .passwoerter
    }
}
