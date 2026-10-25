import SwiftUI
import UIKit

/// Tab "Fotos" (SPEC 11): was schon am PC liegt und der Abgleich. Die Schalter und die Erklärung zum Sichern stehen in den Einstellungen.
struct FotosTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @State private var modell: FotosModell?

    var body: some View {
        NavigationStack {
            Group {
                if let modell {
                    FotosInhalt(modell: modell)
                } else {
                    ProgressView().padding(Abstand.xxl).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .heimherzHintergrund()
            .navigationTitle("Fotos")
        }
        .task(id: umgebung.istGekoppelt) {
            let m = modell ?? (umgebung.istDemo ? FotosModell(istDemo: true) : FotosModell.geteilt)
            modell = m
            await m.lade(gekoppelt: umgebung.istGekoppelt)
            // Beim Öffnen wird nur gezählt. Gesendet wird erst auf "Abgleich starten": Wer anhält, will nicht, dass der Tab wieder anfängt.
            if umgebung.istGekoppelt, !umgebung.istDemo, let c = try? umgebung.client() { m.aktualisiere(client: c) }
        }
    }
}

private struct FotosInhalt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.openURL) private var oeffne
    let modell: FotosModell

    private enum Ansicht: String { case abgleich, fotos }
    @State private var ansicht: Ansicht = Self.startAnsicht
    @State private var aktionen = SchnellaktionPostfach.geteilt
    @State private var zeigeErklaerung = false
    @State private var amStrom = false

    private static var startAnsicht: Ansicht {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "heimherzFotosRaster") { return .fotos }
        #endif
        return .abgleich
    }

    /// Was das Tippen auf "Fotos sichern" am App-Symbol auslösen darf: nicht gesperrt, gekoppelt, die Erlaubnis da.
    private struct AktionBedingung: Equatable {
        let gesperrt: Bool
        let aktion: Schnellaktion?
    }

    var body: some View {
        inhalt
            .task(id: AktionBedingung(gesperrt: umgebung.sperre.gesperrt, aktion: aktionen.offen)) { fuehreAktionAus() }
            .sheet(isPresented: $zeigeErklaerung) { SichernErklaerungBlatt() }
            .onAppear { amStrom = BildschirmWach.amStrom }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                amStrom = BildschirmWach.amStrom
                if modell.laeuft { BildschirmWach.setze(laeuft: true) }   // Stecker rein oder raus mitten im Lauf
            }
    }

    /// "Fotos sichern" vom App-Symbol: derselbe Start wie der Knopf. Fehlt die Erlaubnis, bleibt der Tab stehen und zeigt sie an.
    private func fuehreAktionAus() {
        guard !umgebung.sperre.gesperrt, aktionen.nimm(.fotosSichern) else { return }
        guard umgebung.istGekoppelt, modell.erlaubnis == .voll, !modell.laeuft, let c = try? umgebung.client() else { return }
        ansicht = .abgleich
        modell.starte(client: c)
    }

    @ViewBuilder
    private var inhalt: some View {
        if !umgebung.istGekoppelt {
            seite { LeerZustand(stimmung: .schlaeft, titel: "Fotos", text: "Koppel zuerst dein Handy mit dem PC (Tab Einstellungen).") }
        } else {
            switch modell.erlaubnis {
            case .offen:
                seite {
                    LeerZustand(titel: "Fotos sichern", text: "Heim braucht Zugriff auf alle deine Fotos, um sie auf deinen PC zu bringen. Am Handy wird nie etwas gelöscht oder geändert.",
                                aktionTitel: "Zugriff erlauben") { Task { await modell.erlaube() } }
                }
            case .verweigert:
                seite { keinZugriff("Heim darf deine Fotos nicht lesen. Schalte den Zugriff in den Einstellungen ein.") }
            case .begrenzt:
                seite { keinZugriff("Heim sieht nur einen Teil deiner Fotos. Zum Sichern braucht es den Zugriff auf alle Fotos.") }
            case .voll:
                voll
            }
        }
    }

    private func seite<Inhalt: View>(@ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        ScrollView {
            inhalt()
                .padding(.horizontal, Abstand.l)
                .padding(.bottom, Abstand.xl)
        }
    }

    private var voll: some View {
        VStack(spacing: Abstand.s) {
            Picker("Ansicht", selection: $ansicht) {
                Text("Abgleich").tag(Ansicht.abgleich)
                Text("Fotos").tag(Ansicht.fotos)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Abstand.l)
            switch ansicht {
            case .abgleich: seite { uebersicht }
            case .fotos: FotoRasterView(modell: modell)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { zeigeErklaerung = true } label: { Label("Wie das Sichern läuft", systemImage: "questionmark.circle") }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                }
                .accessibilityLabel("Mehr")
            }
        }
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
        }
    }

    // MARK: Hero

    private var titel: String { FotoText.stand(modell.anzeige) }

    private var hero: some View {
        HeroKarte {
            HStack(alignment: .center, spacing: Abstand.m) {
                HausherzView(stimmung: stimmung, groesse: 72)
                Text(titel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.tinte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let phasen = FotoText.phasen(modell.anzeige.phasen) {
                Text(phasen)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tinte)
            }
            if modell.laeuft || modell.anzeige.schritt != nil, let schritt = modell.anzeige.schritt {
                Text(schritt)
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if modell.laeuft, let f = modell.anzeige.fortschritt {
                ProgressView(value: f)
                    .tint(Color.knopf)
                    .accessibilityLabel("Fortschritt")
                    .accessibilityValue(f.formatted(.percent.precision(.fractionLength(0))))
            }
            if modell.laeuft, let t = FotoText.tempo(modell.anzeige) {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
            if modell.laeuft, amStrom || modell.istDemo {
                Label("Bildschirm bleibt an, solange am Strom", systemImage: "bolt.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
            if modell.anzeige.angehalten, !modell.laeuft {
                StatusChip(text: "Angehalten. Der nächste Start macht genau hier weiter.", symbol: "pause.circle.fill")
            }
            if let fehler = modell.stand.fehler, !modell.laeuft {
                StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn)
            }
            FotoStartKnopf(modell: modell)
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
            WertZeile(name: "Noch offen", wert: z.map { $0.offen.formatted() } ?? "–")
            WertZeile(name: "Letzte Übertragung", wert: letzte)
        }
    }

    private var letzte: String {
        guard let d = modell.stand.letzteUebertragung else { return "noch keine" }
        return d.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "de_DE")))
    }
}
