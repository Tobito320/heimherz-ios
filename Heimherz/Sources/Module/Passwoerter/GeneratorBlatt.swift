import SwiftUI

/// Der Passwort-Generator (SPEC 9): Zeichen-Modus mit Länge 8 bis 64, Ziffern und Sonderzeichen, oder Wortgruppe aus der eigenen deutschen Wortliste.
/// `uebernehmen` gesetzt = Knopf "Übernehmen" (aus dem Formular); sonst nur kopieren.
struct GeneratorBlatt: View {
    var uebernehmen: ((String) -> Void)?

    @Environment(\.dismiss) private var schliessen
    @State private var regeln = PasswortRegeln()
    @State private var passwort = ""
    @State private var kopiert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    ergebnis
                    einstellungen
                }
                .padding(Abstand.l)
            }
            .lumenHintergrund()
            .navigationTitle("Passwort-Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(uebernehmen == nil ? "Fertig" : "Abbrechen") { schliessen() } }
            }
        }
        .fontDesign(.rounded)
        .onAppear { neu() }
        .onChange(of: regeln) { _, _ in neu() }
    }

    private var ergebnis: some View {
        HeroKarte {
            Text(passwort)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.tinte)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Erzeugtes Passwort: \(passwort)")
            StatusChip(text: "Stärke etwa \(PasswortGenerator.bits(regeln)) Bit", symbol: "lock.shield.fill", ton: PasswortGenerator.bits(regeln) >= 70 ? .ok : .warn)
            HStack(spacing: Abstand.m) {
                Button { neu() } label: {
                    Label("Neu erzeugen", systemImage: "arrow.clockwise").frame(minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glass)
                Button {
                    Zwischenablage.kopiere(passwort)
                    Haptik.erfolg()
                    kopiert = true
                } label: {
                    Label(kopiert ? "Kopiert" : "Kopieren", systemImage: kopiert ? "checkmark" : "doc.on.doc").frame(minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glass)
            }
            if let uebernehmen {
                Button {
                    uebernehmen(passwort)
                    schliessen()
                } label: {
                    Text("Übernehmen").font(.headline).frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.knopf)
                .foregroundStyle(Color.aufKnopf)
            }
        }
    }

    private var einstellungen: some View {
        ListenKarte {
            Picker("Art", selection: $regeln.modus) {
                Text("Zeichen").tag(PasswortRegeln.Modus.zeichen)
                Text("Wörter").tag(PasswortRegeln.Modus.wortgruppe)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, Abstand.m)
            if regeln.modus == .zeichen {
                Text("Länge: \(regeln.laenge)").font(.subheadline).foregroundStyle(Color.tinte)
                Slider(value: Binding(get: { Double(regeln.laenge) }, set: { regeln.laenge = Int($0) }),
                       in: Double(PasswortGenerator.laengen.lowerBound)...Double(PasswortGenerator.laengen.upperBound), step: 1)
                    .tint(Color.knopf)
                    .accessibilityLabel("Länge")
                    .accessibilityValue("\(regeln.laenge) Zeichen")
                Toggle("Ziffern", isOn: $regeln.ziffern).tint(Color.knopf)
                Toggle("Sonderzeichen", isOn: $regeln.sonderzeichen).tint(Color.knopf)
            } else {
                Stepper("Wörter: \(regeln.woerter)", value: $regeln.woerter, in: PasswortGenerator.wortAnzahl)
                Toggle("Großgeschrieben", isOn: $regeln.grossschreiben).tint(Color.knopf)
                Toggle("Zahl am Ende", isOn: $regeln.mitZahl).tint(Color.knopf)
                Picker("Trenner", selection: $regeln.trenner) {
                    Text("Strich").tag("-")
                    Text("Punkt").tag(".")
                    Text("Leerzeichen").tag(" ")
                    Text("Keiner").tag("")
                }
            }
        }
    }

    private func neu() {
        passwort = PasswortGenerator.erzeuge(regeln)
        kopiert = false
    }
}
