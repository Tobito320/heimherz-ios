import SwiftUI

/// Wurzel der App: vier Tabs (Passwörter, Fotos, Dateien, Einstellungen), die Module hängen mit ihrer Wurzelansicht (`PasswoerterTabView` usw.) in `Heimherz/Sources/Module/<Modul>/` ein.
/// Über allem liegt die Sperre (Face ID nach 5 Minuten im Hintergrund).
struct AppRootView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.scenePhase) private var phase
    @State private var tab: HeimherzTab
    @State private var aktionen = SchnellaktionPostfach.geteilt

    init(tab: HeimherzTab = .passwoerter) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(HeimherzTab.passwoerter.titel, systemImage: HeimherzTab.passwoerter.symbolName, value: HeimherzTab.passwoerter) { PasswoerterTabView() }
            Tab(HeimherzTab.fotos.titel, systemImage: HeimherzTab.fotos.symbolName, value: HeimherzTab.fotos) { FotosTabView() }
            Tab(HeimherzTab.dateien.titel, systemImage: HeimherzTab.dateien.symbolName, value: HeimherzTab.dateien) { DateienTabView() }
            Tab(HeimherzTab.einstellungen.titel, systemImage: HeimherzTab.einstellungen.symbolName, value: HeimherzTab.einstellungen) { EinstellungenTabView() }
        }
        .lumenWurzel()
        .tint(Color.knopf)
        .tabBarMinimizeBehavior(.onScrollDown)
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
        // Export aus Apple Passwörter kommt in jedem Tab an; das Ergebnisblatt hängt am Passwörter-Tab.
        .heimherzImportAnnahme()
        .onChange(of: ImportPostfach.geteilt.holt) { _, holt in if holt { tab = .passwoerter } }
        .heimherzSpotlightAnnahme()
        // Neuer 2FA-Code per otpauth://-Link (iOS "Codes konfigurieren in") oder QR aus den Einstellungen: das Blatt hängt am Passwörter-Tab.
        .heimherzCodeAnnahme()
        .onChange(of: CodePostfach.geteilt.wartet) { _, wartet in if wartet { tab = .passwoerter } }
        .onChange(of: SpotlightPostfach.geteilt.angefragt) { _, id in if id != nil { tab = .passwoerter } }
        // Schnellaktion vom App-Symbol: der Tab wechselt gleich (auch unter der Sperre); ausgeführt wird sie erst nach dem Entsperren, im Ziel-Tab.
        .onChange(of: aktionen.offen, initial: true) { _, aktion in if let aktion { tab = aktion.tab } }
        .onChange(of: phase) { _, neu in
            umgebung.sperre.szene(neu)
            if neu == .active {
                FotosModell.geteilt.appIstVorn()
                if !umgebung.istDemo, let client = try? umgebung.client() { Task { await OrdnerAbgleich.geteilt.abgleichen(client: client) } }
            } else if neu == .background {
                FotosModell.geteilt.appGehtInHintergrund()
            }
        }
        // Kaltstart: onChange feuert erst beim Wechsel, darum hier einmal; Fotos laufen beim Öffnen von selbst (SPEC 31).
        .task { FotosModell.geteilt.appIstVorn() }
        #if DEBUG
        .onAppear {
            if let name = UserDefaults.standard.string(forKey: "heimherzAktion"), let aktion = Schnellaktion.demo(name) { aktionen.lege(aktion) }
        }
        #endif
    }
}
