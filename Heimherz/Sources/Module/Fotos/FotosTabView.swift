import SwiftUI
import UIKit

/// Tab "Fotos" (SPEC 11): was schon am PC liegt, Abgleich jetzt, Schalter, Hinweise zu den Grenzen von iOS.
struct FotosTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @State private var modell: FotosModell?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let modell {
                    FotosInhalt(modell: modell)
                } else {
                    ProgressView().padding(Abstand.xxl).frame(maxWidth: .infinity)
                }
            }
            .heimherzHintergrund()
            .navigationTitle("Fotos")
        }
        .task(id: umgebung.istGekoppelt) {
            let m = modell ?? FotosModell(istDemo: umgebung.istDemo)
            modell = m
            await m.lade(gekoppelt: umgebung.istGekoppelt)
            // Beim Öffnen gleicht die App sofort ab (SPEC 2: zweiter Weg neben der Erweiterung).
            if umgebung.istGekoppelt, !umgebung.istDemo, let c = try? umgebung.client() { m.abgleichen(client: c) }
        }
    }
}

private struct FotosInhalt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.openURL) private var oeffne
    let modell: FotosModell

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.l) {
            if !umgebung.istGekoppelt {
                LeerZustand(stimmung: .schlaeft, titel: "Fotos", text: "Koppel zuerst dein Handy mit dem PC (Tab Mehr).")
            } else {
                switch modell.erlaubnis {
                case .offen:
                    LeerZustand(titel: "Fotos sichern", text: "Heimherz braucht Zugriff auf alle deine Fotos, um sie auf deinen PC zu bringen. Am Handy wird nie etwas gelöscht oder geändert.",
                                aktionTitel: "Zugriff erlauben") { Task { await modell.erlaube() } }
                case .verweigert:
                    keinZugriff("Heimherz darf deine Fotos nicht lesen. Schalte den Zugriff in den Einstellungen ein.")
                case .begrenzt:
                    keinZugriff("Heimherz sieht nur einen Teil deiner Fotos. Zum Sichern braucht es den Zugriff auf alle Fotos.")
                case .voll:
                    uebersicht
                }
            }
        }
        .padding(.horizontal, Abstand.l)
        .padding(.bottom, Abstand.xl)
    }

    // MARK: Zustände

    private func keinZugriff(_ text: String) -> some View {
        LeerZustand(stimmung: .sorry, titel: "Kein voller Zugriff", text: text, aktionTitel: "Einstellungen öffnen") {
            if let url = URL(string: UIApplication.openSettingsURLString) { oeffne(url) }
        }
    }

    private var uebersicht: some View {
        VStack(alignment: .leading, spacing: Abstand.l) {
            hero
            zahlen
            einstellungen
            grenzen
        }
    }

    // MARK: Hero

    private var titel: String {
        let a = modell.anzeige
        if a.laeuft, let schritt = a.schritt { return schritt }
        guard let z = a.zahlen else { return "Noch nicht gezählt" }
        return z.offen == 0 ? "Alles liegt auf dem PC" : "\(z.amPC.formatted()) von \(z.gesamt.formatted()) Fotos auf dem PC"
    }

    private var hero: some View {
        HeroKarte {
            HStack(alignment: .center, spacing: Abstand.m) {
                HausherzView(stimmung: stimmung, groesse: 72)
                Text(titel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.tinte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if modell.laeuft, let f = modell.anzeige.fortschritt {
                ProgressView(value: f)
                    .tint(Color.knopf)
                    .accessibilityLabel("Fortschritt")
                    .accessibilityValue(f.formatted(.percent.precision(.fractionLength(0))))
            }
            if let fehler = modell.stand.fehler, !modell.laeuft {
                StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn)
            }
            if modell.laeuft {
                Button { modell.abbrechen() } label: {
                    Label("Abbrechen", systemImage: "xmark")
                        .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    if let c = try? umgebung.client() { modell.abgleichen(client: c) }
                } label: {
                    Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.knopf)
                .foregroundStyle(Color.aufKnopf)
                .controlSize(.large)
            }
        }
    }

    private var stimmung: HausherzStimmung {
        if modell.stand.fehler != nil && !modell.laeuft { return .sorry }
        if let z = modell.anzeige.zahlen, z.offen == 0, !modell.laeuft { return .jubelt }
        return .wach
    }

    // MARK: Zahlen

    private var zahlen: some View {
        ListenKarte {
            let z = modell.anzeige.zahlen
            WertZeile(name: "Fotos und Videos am Handy", wert: z.map { $0.gesamt.formatted() } ?? "–")
            WertZeile(name: "Schon am PC", wert: z.map { $0.amPC.formatted() } ?? "–")
            WertZeile(name: "Noch offen", wert: z.map { $0.offen.formatted() } ?? "–")
            WertZeile(name: "Letzte Übertragung", wert: letzte)
        }
    }

    private var letzte: String {
        guard let d = modell.stand.letzteUebertragung else { return "noch keine" }
        return d.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "de_DE")))
    }

    // MARK: Einstellungen

    private var einstellungen: some View {
        ListenKarte {
            Toggle(isOn: Binding(get: { modell.nurWLAN }, set: { modell.setzeNurWLAN($0) })) {
                Text("Nur im WLAN senden")
                    .foregroundStyle(Color.tinte)
            }
            .tint(Color.knopf)
            .frame(minHeight: Abstand.tippflaeche)
            Text("Videos gehen immer nur im WLAN. Ist das Handy nicht im WLAN, warten die Dateien auf den nächsten Abgleich.")
                .font(.footnote)
                .foregroundStyle(Color.tinte2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Abstand.s)
            Toggle(isOn: Binding(get: { modell.hintergrundAn }, set: { modell.schalteHintergrund($0) })) {
                Text("Im Hintergrund hochladen")
                    .foregroundStyle(Color.tinte)
            }
            .tint(Color.knopf)
            .frame(minHeight: Abstand.tippflaeche)
        }
    }

    // MARK: Grenzen

    private var grenzen: some View {
        ListenKarte {
            Text("Wie das Sichern läuft")
                .font(.headline)
                .foregroundStyle(Color.tinte)
            Text("iOS entscheidet selbst, wann es im Hintergrund hochlädt, meist nachts am Ladegerät im WLAN. Ein Zeitpunkt ist nicht garantiert. Öffne diesen Tab ab und zu: Dann gleicht die App sofort ab. Der PC muss dafür an sein und Tailscale laufen. Am Handy wird nie etwas gelöscht oder geändert.")
                .font(.subheadline)
                .foregroundStyle(Color.tinte2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Abstand.xs)
        }
    }
}
