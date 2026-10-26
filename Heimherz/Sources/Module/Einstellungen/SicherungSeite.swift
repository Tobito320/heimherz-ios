import LocalAuthentication
import SwiftUI
import UIKit

/// Die neueste Sicherungsdatei im Ordner `Sicherung` (Antwort von `GET /v1/dateien?pfad=Sicherung`). Reine Logik für "Letzte Sicherung".
enum SicherungStand {
    static func neueste(_ liste: [DateiInfo]) -> Date? {
        liste.filter { !$0.ordner && $0.name.hasSuffix(".heimsicherung") }.compactMap(\.datum).max()
    }

    static func text(_ datum: Date?) -> String {
        guard let datum else { return "noch keine" }
        return datum.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "de_DE")))
    }
}

/// Face ID, die immer fragt: das Entsperr-Fenster (W-009) ersetzt sie hier nie.
enum FrischeAbfrage {
    @concurrent
    static func pruefe(grund: String) async -> Bool {
        let kontext = LAContext()
        var fehler: NSError?
        guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return false }
        return (try? await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: grund)) ?? false
    }
}

/// Einstellungen > Sicherung (W-035, W-036): wo die Sicherungen liegen, wann die letzte war, und der Wiederherstellungsschlüssel.
/// Der Code entsteht hier nach Face ID, geht nur umwickelt an den PC und steht nur auf diesem Bildschirm, nirgends sonst
/// (nicht im Schlüsselbund, nicht in den Einstellungen, nicht in der Zwischenablage); er verschwindet, sobald die App den Vordergrund verlässt.
struct SicherungSeite: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.scenePhase) private var phase
    @State private var letzte: Date?
    @State private var geladen = false
    @State private var code: String?
    @State private var laeuft = false
    @State private var fehler: String?
    @State private var frage = false
    @AppStorage("heimherzWiederherstellungVom") private var erzeugtAm: Double = 0

    var body: some View {
        List {
            Section {
                LabeledContent("Letzte Sicherung", value: geladen ? SicherungStand.text(letzte) : "…").lumenZeile()
                LabeledContent("Liegt in", value: "Dateien, Ordner Sicherung").lumenZeile()
            } header: {
                GruppenText(text: "Sicherung")
            } footer: {
                GruppenText(text: "Der PC sichert den Tresor stündlich verschlüsselt: auf dem PC, in Google Drive und hier auf dem Handy (der Tresor liegt verschlüsselt in dieser App). Die Dateien enthalten nie ein Passwort im Klartext.", fuss: true)
            }
            Section {
                if let code {
                    codeKarte(code)
                } else {
                    Button { if erzeugtAm > 0 { frage = true } else { starte() } } label: {
                        KachelTitel(titel: erzeugtAm > 0 ? "Neuen Wiederherstellungsschlüssel erzeugen" : "Wiederherstellungsschlüssel erzeugen", symbol: "key.fill", ton: .gelb)
                    }
                    .disabled(laeuft || umgebung.istDemo)
                    .lumenZeile()
                    if erzeugtAm > 0 {
                        LabeledContent("Zuletzt erzeugt", value: Date(timeIntervalSince1970: erzeugtAm).formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE")))).lumenZeile()
                    }
                }
            } header: {
                GruppenText(text: "Wiederherstellungsschlüssel")
            } footer: {
                GruppenText(text: "Mit dem Code lässt sich eine Sicherung auf einem neuen PC öffnen, ohne dieses Handy. Er wird nach Face ID einmal gezeigt. Schreib ihn ab oder drucke ihn und bewahre ihn getrennt vom Handy auf.", fuss: true)
            }
        }
        .lumenEinstellungenListe()
        .navigationTitle("Sicherung")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ladeStand() }
        .onChange(of: phase) { _, neu in if neu != .active { code = nil } }
        .confirmationDialog("Neuen Schlüssel erzeugen?", isPresented: $frage, titleVisibility: .visible) {
            Button("Neu erzeugen", role: .destructive) { starte() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der alte Code passt dann nicht mehr. Der neue gilt für alle Sicherungen, die der PC ab jetzt schreibt.")
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { fehler != nil }, set: { if !$0 { fehler = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fehler ?? "")
        }
    }

    private func codeKarte(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Abstand.m) {
            Text("Dein Wiederherstellungsschlüssel")
                .font(.headline)
            Text(code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.disabled)
            Text("Er wird nur jetzt angezeigt und ist nirgends gespeichert. Schreib ihn ab oder drucke ihn.")
                .font(.subheadline)
                .foregroundStyle(Color.tinte2)
            HStack {
                Button("Drucken") { drucke(code) }
                Spacer()
                Button("Fertig, ist notiert") { self.code = nil }
                    .buttonStyle(.glassProminent)
                    .tint(Color.knopf)
            }
        }
        .padding(.vertical, Abstand.s)
    }

    private func drucke(_ code: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Lumen Cloud Wiederherstellungsschlüssel"
        let formatter = UISimpleTextPrintFormatter(text: "Lumen Cloud Wiederherstellungsschlüssel\n\n\(code)\n\nOhne PC und Handy öffnet dieser Code eine Sicherung des Tresors. Getrennt vom Handy aufbewahren.")
        formatter.perPageContentInsets = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)
        let druck = UIPrintInteractionController.shared
        druck.printInfo = info
        druck.printFormatter = formatter
        druck.present(animated: true)
    }

    private func ladeStand() async {
        defer { geladen = true }
        guard !umgebung.istDemo, let c = try? umgebung.client() else { return }
        letzte = SicherungStand.neueste((try? await c.dateienListe(pfad: "Sicherung")) ?? [])
    }

    private func starte() {
        laeuft = true
        Task {
            defer { laeuft = false }
            guard await FrischeAbfrage.pruefe(grund: "Wiederherstellungsschlüssel erzeugen") else { return }
            do {
                guard let k = try await umgebung.bund.ladeSchluessel(kontext: umgebung.sperre.kontext) else { throw HeimFehler.nichtGekoppelt }
                let neu = Wiederherstellung.neuerCode()
                // Erst zum PC, dann anzeigen: scheitert das Hochladen, gibt es keinen Code, der nirgends gilt.
                try await umgebung.client().wiederherstellungSetzen(try Wiederherstellung.umwickle(schluessel: k, code: neu))
                erzeugtAm = Date().timeIntervalSince1970
                code = Wiederherstellung.codeText(neu)
            } catch let f as HeimFehler {
                fehler = f.nutzerText
            } catch {
                fehler = "Der Schlüssel konnte nicht erzeugt werden."
            }
        }
    }
}
