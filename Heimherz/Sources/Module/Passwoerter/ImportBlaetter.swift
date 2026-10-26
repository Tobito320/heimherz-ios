import SwiftUI

/// Anleitung "Aus Apple Passwörter holen": Apple startet den Export, Heim nimmt ihn an (Credential Exchange, iOS 26).
struct ImportAnleitungBlatt: View {
    @Environment(\.dismiss) private var schliessen

    private let schritte = [
        "Öffne die App „Passwörter“ von Apple.",
        "Öffne das Menü (drei Punkte) und wähle „Daten an andere App exportieren“. Der Menüpunkt kann je nach iOS-Version etwas anders heißen.",
        "Bestätige mit Face ID und wähle „Lumen Cloud“ in der Liste.",
        "Lumen Cloud öffnet sich, nimmt alles auf und gleicht gleich mit deinem PC ab."
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    Text("Alle Konten, Einmalcodes, Passkeys und Notizen auf einmal. Es entsteht keine Datei.")
                        .font(.body)
                        .foregroundStyle(Color.tinte)
                        .fixedSize(horizontal: false, vertical: true)
                    ListenKarte {
                        ForEach(Array(schritte.enumerated()), id: \.offset) { i, text in
                            HStack(alignment: .firstTextBaseline, spacing: Abstand.m) {
                                Text("\(i + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.aufKnopf)
                                    .frame(width: 26, height: 26)
                                    .background(Color.knopf, in: Circle())
                                    .accessibilityHidden(true)
                                Text(text)
                                    .font(.body)
                                    .foregroundStyle(Color.tinte)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, Abstand.xs)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Schritt \(i + 1): \(text)")
                        }
                    }
                    // Selten gebraucht: zugeklappt, damit die Schritte die Seite tragen.
                    DisclosureGroup("Gut zu wissen") {
                        VStack(alignment: .leading, spacing: Abstand.s) {
                            punkt("Gleicher Benutzer und gleiche Seite mit gleichem Passwort: wird übersprungen.")
                            punkt("Gleicher Benutzer und gleiche Seite mit neuerem Passwort: Lumen Cloud übernimmt das neue, das alte bleibt im Verlauf des Eintrags.")
                            punkt("Passkeys werden gesichert (mit Seite, Konto und Schlüssel, nur im verschlüsselten Tresor). Anmelden damit geht über Automatisch ausfüllen.")
                            punkt("WLAN-Passwörter, Karten und Ausweise kennt Lumen Cloud nicht und überspringt sie.")
                            punkt("Lumen Cloud muss in den iPhone-Einstellungen unter Allgemein, AutoFill und Passwörter als Anbieter eingeschaltet sein, falls Apple die App sonst nicht anbietet.")
                        }
                        .padding(.top, Abstand.s)
                    }
                    .font(.headline)
                    .foregroundStyle(Color.tinte)
                    .tint(Color.tinte2)
                }
                .padding(Abstand.l)
            }
            .lumenHintergrund()
            .navigationTitle("Aus Apple Passwörter holen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
        }
        .fontDesign(.rounded)
    }

    private func punkt(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.s) {
            Text("•").foregroundStyle(Color.tinte2).accessibilityHidden(true)
            Text(text).foregroundStyle(Color.tinte2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

/// Das Ergebnis nach dem Import: nur Zahlen, nie ein Name oder Passwort.
struct ImportErgebnisBlatt: View {
    let ergebnis: ImportZaehler
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    HeroKarte {
                        Text("Aus Apple Passwörter geholt")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.tinte)
                        Text(ergebnis.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.tinte2)
                    }
                    .accessibilityElement(children: .combine)
                    ListenKarte {
                        WertZeile(name: "Neu", wert: "\(ergebnis.neu)")
                        WertZeile(name: "Aktualisiert", wert: "\(ergebnis.aktualisiert)")
                        WertZeile(name: "Passkeys gesichert", wert: "\(ergebnis.passkeys)")
                        WertZeile(name: "Übersprungen", wert: "\(ergebnis.uebersprungen)")
                    }
                    if ergebnis.passkeys > 0 {
                        Text("Die Passkeys liegen sicher im Tresor. Anmelden damit geht über Automatisch ausfüllen.")
                            .font(.footnote)
                            .foregroundStyle(Color.tinte2)
                    }
                }
                .padding(Abstand.l)
            }
            .lumenHintergrund()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
        }
        .fontDesign(.rounded)
        .presentationDetents([.medium, .large])
    }
}
