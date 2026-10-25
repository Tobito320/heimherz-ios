import SwiftUI

/// Wurzel der App: vier Tabs, die Module hängen mit ihrer Wurzelansicht (`PasswoerterTabView` usw.) in `Heimherz/Sources/Module/<Modul>/` ein.
/// Über allem liegt die Sperre (Face ID nach 5 Minuten im Hintergrund).
struct AppRootView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.scenePhase) private var phase
    @State private var tab: HeimherzTab

    init(tab: HeimherzTab = .passwoerter) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(HeimherzTab.passwoerter.titel, systemImage: HeimherzTab.passwoerter.symbolName, value: HeimherzTab.passwoerter) { PasswoerterTabView() }
            Tab(HeimherzTab.fotos.titel, systemImage: HeimherzTab.fotos.symbolName, value: HeimherzTab.fotos) { FotosTabView() }
            Tab(HeimherzTab.dateien.titel, systemImage: HeimherzTab.dateien.symbolName, value: HeimherzTab.dateien) { DateienTabView() }
            Tab(HeimherzTab.mehr.titel, systemImage: HeimherzTab.mehr.symbolName, value: HeimherzTab.mehr) { MehrTabView() }
        }
        .tint(Color.knopf)
        .fontDesign(.rounded)
        .accessibilityHidden(umgebung.sperre.verdeckt)
        .overlay {
            if umgebung.sperre.gesperrt { SperrAnsicht(sperre: umgebung.sperre).transition(.opacity) }
        }
        .animation(Feder.weich, value: umgebung.sperre.gesperrt)
        .overlay {
            // Ohne Übergang und ohne Animation: der Schnappschuss des App-Umschalters entsteht Sekundenbruchteile nach dem Wechsel.
            if umgebung.sperre.verdeckt { DeckFlaeche() }
        }
        .onChange(of: tab) { _, _ in Haptik.auswahl() }
        .onChange(of: phase) { _, neu in umgebung.sperre.szene(neu) }
    }
}
