// Lumen-Kit: NICHT in der App ändern. Änderungen im Kit (80 System/Agents/lumen-kit/Sources), dann `lumen-sync APP_REPO`.
import SwiftUI
import UIKit

/// Alle Schlüssel und Titel der Standard-Einstellungen an einer Stelle: jede Lumen-App sieht gleich aus und spricht gleich.
enum LumenEinstellung {
    static let aussehenSchluessel = "lumen.aussehen"
    static let bewegungSchluessel = "lumen.bewegung"
    static let haptikSchluessel = "lumen.haptik"

    static let darstellung = "Darstellung"
    static let aussehen = "Aussehen"
    static let bewegung = "Bewegung"
    static let bewegungFuss = "Voll ignoriert „Bewegung reduzieren“ von iOS. Reduziert und Folgt System lassen Zahlen, Linien und Übergänge stehen."
    static let haptik = "Haptik"
    static let benachrichtigungen = "Mitteilungen"
    static let benachrichtigungenZeile = "Mitteilungen in den iOS-Einstellungen"
    static let daten = "Daten"
    static let ueber = "Über"
    static let hilfe = "Hilfe"
    static let fehlerMelden = "Fehlerbericht teilen"
    static let fehlerMeldenFuss = "Kopiert nichts von selbst und sendet nichts: du entscheidest im Teilen-Blatt, wohin der Text geht. Er enthält keine Passwörter und keine Inhalte."
}

enum LumenAussehen: Int, CaseIterable, Identifiable {
    case automatisch, hell, dunkel
    var id: Int { rawValue }
    var titel: String { ["Automatisch", "Hell", "Dunkel"][rawValue] }
    var schema: ColorScheme? { [nil, .light, .dark][rawValue] }
}

enum LumenBewegung: Int, CaseIterable, Identifiable {
    case system, reduziert, voll
    var id: Int { rawValue }
    var titel: String { ["Folgt System", "Reduziert", "Voll"][rawValue] }
}

/// `@LumenStill private var still`: wahr, wenn Bewegung stehen soll (Wahl der App oder Reduce Motion von iOS). Alle Bausteine des Kits lesen das hier.
@propertyWrapper
struct LumenStill: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(LumenEinstellung.bewegungSchluessel) private var wahl = LumenBewegung.system.rawValue

    var wrappedValue: Bool {
        switch LumenBewegung(rawValue: wahl) ?? .system {
        case .voll: return false
        case .reduziert: return true
        case .system: return system
        }
    }
}

extension View {
    /// Wurzel jeder Lumen-App (am TabView oder der obersten Ansicht): setzt Hell, Dunkel oder Automatisch.
    func lumenWurzel() -> some View { modifier(LumenWurzel()) }
}

private struct LumenWurzel: ViewModifier {
    @AppStorage(LumenEinstellung.aussehenSchluessel) private var aussehen = LumenAussehen.automatisch.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme((LumenAussehen(rawValue: aussehen) ?? .automatisch).schema)
    }
}

/// Was eine App zu den Standard-Abschnitten beisteuert. Nur `appName` ist Pflicht.
struct LumenEinstellungenKonfig {
    var appName: String
    /// Zeile "Verbindung" im Abschnitt Über (zum Beispiel "Mit dem PC verbunden"); nil blendet sie aus.
    var verbindung: String?
    /// Abschnitt Daten: nil blendet die Zeile aus.
    var exportieren: (() -> Void)?
    var zuruecksetzen: (() -> Void)?
    var zuruecksetzenFrage = "Wirklich zurücksetzen?"
    /// Mitteilungen anzeigen (Apps ohne Mitteilungen: false).
    var mitMitteilungen = true
    /// Weitere Zeilen im Abschnitt Über (zum Beispiel "Build vom").
    var ueberExtra: [(String, String)] = []

    init(appName: String, verbindung: String? = nil, exportieren: (() -> Void)? = nil, zuruecksetzen: (() -> Void)? = nil, mitMitteilungen: Bool = true, ueberExtra: [(String, String)] = []) {
        self.appName = appName
        self.verbindung = verbindung
        self.exportieren = exportieren
        self.zuruecksetzen = zuruecksetzen
        self.mitMitteilungen = mitMitteilungen
        self.ueberExtra = ueberExtra
    }
}

/// Die gleichen Abschnitte für jede Lumen-App: Darstellung, Mitteilungen, Daten, Über, Hilfe. In jede `List` einfügen; Sperre und App-eigene
/// Zeilen baut die App als eigene Abschnitte daneben. Zeilen nutzen `.lumenZeile()` (flache Karte).
struct LumenStandardAbschnitte: View {
    let konfig: LumenEinstellungenKonfig

    @AppStorage(LumenEinstellung.aussehenSchluessel) private var aussehen = LumenAussehen.automatisch.rawValue
    @AppStorage(LumenEinstellung.bewegungSchluessel) private var bewegung = LumenBewegung.system.rawValue
    @AppStorage(LumenEinstellung.haptikSchluessel) private var haptik = true
    @Environment(\.openURL) private var oeffne
    @State private var frageZuruecksetzen = false

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–" }

    /// Text für den Fehlerbericht: App, Version, iOS, Gerät, Verbindung. Nie Inhalte.
    var bericht: String {
        ["\(konfig.appName) \(version) (\(build))", "iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)", konfig.verbindung.map { "Verbindung: \($0)" }]
            .compactMap { $0 }.joined(separator: "\n")
    }

    var body: some View {
        Group {
            Section {
                Picker(LumenEinstellung.aussehen, selection: $aussehen) {
                    ForEach(LumenAussehen.allCases) { Text($0.titel).tag($0.rawValue) }
                }
                .lumenZeile()
                Picker(LumenEinstellung.bewegung, selection: $bewegung) {
                    ForEach(LumenBewegung.allCases) { Text($0.titel).tag($0.rawValue) }
                }
                .lumenZeile()
                Toggle(LumenEinstellung.haptik, isOn: $haptik)
                    .lumenZeile()
            } header: {
                GruppenText(text: LumenEinstellung.darstellung)
            } footer: {
                GruppenText(text: LumenEinstellung.bewegungFuss, fuss: true)
            }

            if konfig.mitMitteilungen {
                Section {
                    Button(LumenEinstellung.benachrichtigungenZeile) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { oeffne(url) }
                    }
                    .lumenZeile()
                } header: {
                    GruppenText(text: LumenEinstellung.benachrichtigungen)
                }
            }

            if konfig.exportieren != nil || konfig.zuruecksetzen != nil {
                Section {
                    if let exportieren = konfig.exportieren {
                        Button("Exportieren", action: exportieren).lumenZeile()
                    }
                    if konfig.zuruecksetzen != nil {
                        Button("Zurücksetzen", role: .destructive) { frageZuruecksetzen = true }.lumenZeile()
                    }
                } header: {
                    GruppenText(text: LumenEinstellung.daten)
                }
            }

            Section {
                LabeledContent("Name", value: konfig.appName).lumenZeile()
                LabeledContent("Version", value: version).lumenZeile()
                LabeledContent("Build", value: build).lumenZeile()
                if let verbindung = konfig.verbindung { LabeledContent("Verbindung", value: verbindung).lumenZeile() }
                ForEach(Array(konfig.ueberExtra.enumerated()), id: \.offset) { zeile in
                    LabeledContent(zeile.element.0, value: zeile.element.1).lumenZeile()
                }
            } header: {
                GruppenText(text: LumenEinstellung.ueber)
            }

            Section {
                ShareLink(item: bericht) { Label(LumenEinstellung.fehlerMelden, systemImage: "square.and.arrow.up") }
                    .lumenZeile()
            } header: {
                GruppenText(text: LumenEinstellung.hilfe)
            } footer: {
                GruppenText(text: LumenEinstellung.fehlerMeldenFuss, fuss: true)
            }
        }
        .confirmationDialog(konfig.zuruecksetzenFrage, isPresented: $frageZuruecksetzen, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { konfig.zuruecksetzen?() }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
