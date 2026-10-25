import SwiftUI

/// Das Blatt "Code einrichten" (W-028): ein neuer 2FA-Code ist angekommen. Erst wählen, zu welchem Konto er gehört (oder einen neuen Eintrag anlegen),
/// dann steht der laufende Code da, den die Seite meist zur Bestätigung will. Das Blatt erscheint erst, wenn der Tresor offen ist.
struct CodeEinrichtenBlatt: View {
    let modell: CodeEinrichten

    @Environment(\.dismiss) private var schliessen
    @State private var kopiert = false

    var body: some View {
        NavigationStack {
            Group {
                if let fertig = modell.fertig { fertigListe(fertig) } else { auswahlListe }
            }
            .heimherzEinstellungenListe()
            .navigationTitle(modell.fertig == nil ? "Code einrichten" : "Eingerichtet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if modell.fertig == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } }
                }
            }
        }
        .fontDesign(.rounded)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(modell.arbeitet)
        .confirmationDialog("Dieses Konto hat schon einen Code", isPresented: Binding(get: { modell.rueckfrage != nil }, set: { if !$0 { modell.rueckfrage = nil } }),
                            titleVisibility: .visible) {
            Button("Ersetzen", role: .destructive) { Task { await modell.ersetze() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der neue Code ersetzt ihn. Der alte Schlüssel bleibt im Verlauf des Eintrags.")
        }
    }

    // MARK: Wählen

    private var auswahlListe: some View {
        List {
            Section {
                kopf
            }
            Section {
                ForEach(modell.vorschlaege) { e in
                    Button { Task { await modell.waehle(e) } } label: { zeile(e) }
                        .heimherzZeile()
                }
                NavigationLink {
                    AnderesKontoListe(modell: modell)
                } label: {
                    KachelTitel(titel: "Anderes Konto wählen", symbol: "magnifyingglass", ton: .grau)
                }
                .heimherzZeile()
            } header: {
                GruppenText(text: "Zu diesem Konto hinzufügen")
            } footer: {
                if modell.vorschlaege.isEmpty { GruppenText(text: "Kein passender Eintrag gefunden.", fuss: true) }
            }
            Section {
                Button { Task { await modell.legeNeuAn() } } label: {
                    KachelTitel(titel: "Neuer Eintrag „\(modell.konto.anzeigeName)“", symbol: "plus", ton: .gruen)
                }
                .heimherzZeile()
            } footer: {
                if let fehler = modell.fehler { Text(fehler).font(.footnote).foregroundStyle(Color.schlecht) }
            }
        }
        .disabled(modell.arbeitet)
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(modell.konto.issuer.isEmpty ? "Unbekannter Anbieter" : modell.konto.issuer)
                .font(.headline)
                .foregroundStyle(Color.tinte)
            if !modell.konto.konto.isEmpty {
                Text(modell.konto.konto)
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
            }
        }
        .padding(.vertical, Abstand.xs)
        .accessibilityElement(children: .combine)
        .heimherzZeile()
    }

    private func zeile(_ e: Eintrag) -> some View {
        HStack(spacing: Abstand.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).foregroundStyle(Color.tinte)
                if !e.benutzer.isEmpty { Text(e.benutzer).font(.subheadline).foregroundStyle(Color.tinte2) }
            }
            Spacer(minLength: Abstand.s)
            if !e.totp.isEmpty {
                Text("hat einen Code").font(.footnote).foregroundStyle(Color.tinte2)
            }
        }
        .frame(minHeight: Abstand.tippflaeche)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Fertig

    private func fertigListe(_ fertig: CodeEinrichten.Fertig) -> some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { zeit in
                    if let z = TOTPAnzeige.zustand(fertig.uri, datum: zeit.date) {
                        HStack(spacing: Abstand.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fertig.name).font(.footnote).foregroundStyle(Color.tinte2)
                                Text(z.gruppiert)
                                    .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Color.tinte)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Abstand.s)
                            TOTPRing(anteil: z.anteil, rest: z.rest)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Bestätigungscode \(z.code), noch \(z.rest) Sekunden gültig")
                    }
                }
                .padding(.vertical, Abstand.xs)
                .heimherzZeile()
                Button {
                    if let z = TOTPAnzeige.zustand(fertig.uri, datum: Date()) {
                        Zwischenablage.kopiere(z.code)
                        Haptik.erfolg()
                        kopiert = true
                    }
                } label: {
                    KachelTitel(titel: kopiert ? "Kopiert, 60 Sekunden" : "Kopieren", symbol: kopiert ? "checkmark" : "doc.on.doc", ton: .gruen)
                }
                .heimherzZeile()
            } footer: {
                GruppenText(text: "Gib diesen Code auf der Seite ein, um die Einrichtung zu bestätigen.", fuss: true)
            }
        }
        .onAppear { Haptik.erfolg() }
    }
}

/// Alle Logins zur Auswahl, wenn der Vorschlag nicht passt (zum Beispiel Anbieter „Microsoft“, Eintrag „Outlook“).
private struct AnderesKontoListe: View {
    let modell: CodeEinrichten
    @State private var suche = ""

    var body: some View {
        List {
            ForEach(EintragSuche.filtern(modell.alleLogins, begriff: suche)) { e in
                Button { Task { await modell.waehle(e) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).foregroundStyle(Color.tinte)
                        if !e.benutzer.isEmpty { Text(e.benutzer).font(.subheadline).foregroundStyle(Color.tinte2) }
                    }
                    .frame(minHeight: Abstand.tippflaeche, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .heimherzZeile()
            }
        }
        .heimherzEinstellungenListe()
        .searchable(text: $suche, prompt: "Konto suchen")
        .navigationTitle("Anderes Konto")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(modell.arbeitet)
    }
}

/// Die Kamera als Blatt: meldet den ersten QR-Code und schließt. Für die Einstellungen und das Formular (der Scanner meldet jeden Treffer, hier zählt nur der erste).
struct CodeScanBlatt: View {
    let beiCode: (String) -> Void

    @Environment(\.dismiss) private var schliessen
    @State private var gemeldet = false

    var body: some View {
        NavigationStack {
            QRScanner { text in
                guard !gemeldet else { return }
                gemeldet = true
                beiCode(text)
                schliessen()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("QR-Code scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } } }
        }
        .fontDesign(.rounded)
    }
}
