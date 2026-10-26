import SwiftUI

/// Die Oberfläche der Erweiterung. Sie sieht `Heimherz/Sources/Design` nicht (nur `Gemeinsam`), darum Farben, Abstände und das Haus
/// aus `Gemeinsam/Design` mit System-Listen. Immer ein Abbrechen-Knopf (Apple verlangt ihn).
struct AutoFillWurzel: View {
    @Bindable var modell: AutoFillModell

    var body: some View {
        Group {
            switch modell.phase {
            case .start, .arbeitet:
                Beschaeftigt()
            case .entsperren(let fehler):
                EntsperrenAnsicht(fehler: fehler, nochmal: { Task { await modell.entsperren() } }, abbrechen: { modell.abbrechen() })
            case .liste:
                AuswahlListe(modell: modell)
            case .bestaetigen(let aktion):
                SpeichernAnsicht(aktion: aktion, anfrageHost: modell.anfrageHost, sichern: { Task { await modell.bestaetigeSpeichern() } }, abbrechen: { modell.abbrechen() })
            case .konfiguration:
                KonfigurationAnsicht(fertig: { modell.fertigKonfiguration() })
            case .fremdesKonto(let eintrag, let seite):
                FremdesKontoAnsicht(eintrag: eintrag, seite: seite, ausfuellen: { modell.bestaetigeFremdes() }, abbrechen: { modell.lehneFremdesAb() })
            case .passkeyWahl(let liste):
                PasskeyAuswahl(liste: liste, waehle: { modell.waehlePasskey($0) }, abbrechen: { modell.abbrechen() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.grund.ignoresSafeArea() }
        .tint(Color.knopf)
        .fontDesign(.rounded)
    }
}

private struct Beschaeftigt: View {
    var body: some View {
        VStack(spacing: Abstand.l) {
            HausherzView(stimmung: .wach, groesse: 96)
            ProgressView()
            Text("Einen Moment …")
                .font(.subheadline)
                .foregroundStyle(Color.tinte2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Einen Moment")
    }
}

private struct EntsperrenAnsicht: View {
    let fehler: String?
    let nochmal: () -> Void
    let abbrechen: () -> Void

    var body: some View {
        VStack(spacing: Abstand.l) {
            Spacer()
            HausherzView(stimmung: fehler == nil ? .schlaeft : .sorry, groesse: 120)
            Text("Haven ist gesperrt")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
            Text(fehler ?? "Entsperre mit Face ID, dann füllt Haven das Konto aus.")
                .font(.body)
                .foregroundStyle(fehler == nil ? Color.tinte2 : Color.schlecht)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: nochmal) {
                Label("Entsperren", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Abbrechen", action: abbrechen)
                .frame(minHeight: Abstand.tippflaeche)
        }
        .padding(Abstand.xl)
    }
}

private struct AuswahlListe: View {
    @Bindable var modell: AutoFillModell

    private var codes: Bool {
        modell.listenArt?.codes ?? false
    }

    var body: some View {
        NavigationStack {
            let gruppen = modell.gruppen
            List {
                if gruppen.passend.isEmpty && gruppen.uebrige.isEmpty {
                    Text(codes ? "Kein Konto mit Einmalcode gefunden." : "Kein Konto gefunden.")
                        .foregroundStyle(Color.tinte2)
                        .listRowBackground(Color.karte)
                }
                if !gruppen.passend.isEmpty {
                    Section("Passend zur Webseite") { zeilen(gruppen.passend) }
                }
                if !gruppen.uebrige.isEmpty {
                    Section(gruppen.passend.isEmpty ? "Alle Konten" : "Weitere Konten") { zeilen(gruppen.uebrige) }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $modell.suche, prompt: "Name, Benutzer oder Webseite")
            .navigationTitle(codes ? "Einmalcode wählen" : "Konto wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { modell.abbrechen() } }
            }
        }
    }

    private func zeilen(_ liste: [Eintrag]) -> some View {
        ForEach(liste) { e in
            Button { modell.waehle(e) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name.isEmpty ? "Ohne Namen" : e.name)
                        .font(.headline)
                        .foregroundStyle(Color.tinte)
                    let zusatz = e.benutzer.isEmpty ? (EintragSuche.hosts(von: e).first ?? "") : e.benutzer
                    if !zusatz.isEmpty {
                        Text(zusatz)
                            .font(.subheadline)
                            .foregroundStyle(Color.tinte2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche, alignment: .leading)
            }
            .listRowBackground(Color.karte)
        }
    }
}

private struct PasskeyAuswahl: View {
    let liste: [Passkey]
    let waehle: (Passkey) -> Void
    let abbrechen: () -> Void

    var body: some View {
        NavigationStack {
            List(Array(liste.enumerated()), id: \.offset) { _, p in
                Button { waehle(p) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.userName.isEmpty ? "Ohne Namen" : p.userName)
                                .font(.headline)
                                .foregroundStyle(Color.tinte)
                            Text(p.rpId)
                                .font(.subheadline)
                                .foregroundStyle(Color.tinte2)
                        }
                    } icon: {
                        Image(systemName: "person.badge.key.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche, alignment: .leading)
                }
                .listRowBackground(Color.karte)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Passkey wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: abbrechen) }
            }
        }
    }
}

private struct SpeichernAnsicht: View {
    let aktion: SpeicherAktion
    let anfrageHost: String?
    let sichern: () -> Void
    let abbrechen: () -> Void

    private var eintrag: Eintrag? {
        switch aktion {
        case .neu(let e), .aktualisieren(let e): return e
        case .vorhanden: return nil
        }
    }

    private var aktualisiert: Bool {
        if case .aktualisieren = aktion { return true }
        return false
    }

    var body: some View {
        VStack(spacing: Abstand.l) {
            Spacer()
            HausherzView(stimmung: .wach, groesse: 100)
            Text(aktualisiert ? "Passwort aktualisieren?" : "In Haven sichern?")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
                .multilineTextAlignment(.center)
            if let e = eintrag {
                VStack(spacing: Abstand.xs) {
                    Text(e.name).font(.headline).foregroundStyle(Color.tinte)
                    if !e.benutzer.isEmpty { Text(e.benutzer).font(.subheadline).foregroundStyle(Color.tinte2) }
                    if aktualisiert {
                        // Beim Überschreiben sind alle Hosts des Eintrags wichtig, nicht nur der erste.
                        let hosts = EintragSuche.hosts(von: e)
                        if !hosts.isEmpty { Text(hosts.joined(separator: ", ")).font(.subheadline).foregroundStyle(Color.tinte2) }
                        if let hinweis = PasswortSpeichern.hostHinweis(fuer: e, anfrageHost: anfrageHost) {
                            Text(hinweis).font(.subheadline.weight(.semibold)).foregroundStyle(Color.schlecht)
                        }
                    } else if let host = EintragSuche.hosts(von: e).first {
                        Text(host).font(.subheadline).foregroundStyle(Color.tinte2)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
            Text(aktualisiert ? "Für dieses Konto gibt es schon ein anderes Passwort. Das neue ersetzt es; das alte bleibt im Verlauf des Eintrags." : "Das Konto landet verschlüsselt im Tresor und geht, sobald der PC erreichbar ist, dorthin.")
                .font(.footnote)
                .foregroundStyle(Color.tinte2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: sichern) {
                Text(aktualisiert ? "Aktualisieren" : "Sichern")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Abbrechen", action: abbrechen)
                .frame(minHeight: Abstand.tippflaeche)
        }
        .padding(Abstand.xl)
    }
}

/// Phishing-Fall: Ahmed hat in der Suche ein Konto gewählt, das nicht zur Seite gehört.
private struct FremdesKontoAnsicht: View {
    let eintrag: Eintrag
    let seite: String
    let ausfuellen: () -> Void
    let abbrechen: () -> Void

    var body: some View {
        VStack(spacing: Abstand.l) {
            Spacer()
            HausherzView(stimmung: .sorry, groesse: 100)
            Text("Passt nicht zur Seite")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
            Text("Dieses Konto gehört zu \(EintragSuche.hosts(von: eintrag).first ?? eintrag.name), die Seite ist \(seite). Trotzdem ausfüllen?")
                .font(.body)
                .foregroundStyle(Color.tinte2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: abbrechen) {
                Text("Abbrechen")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Trotzdem ausfüllen", role: .destructive, action: ausfuellen)
                .frame(minHeight: Abstand.tippflaeche)
        }
        .padding(Abstand.xl)
    }
}

private struct KonfigurationAnsicht: View {
    let fertig: () -> Void

    var body: some View {
        VStack(spacing: Abstand.l) {
            Spacer()
            HausherzView(stimmung: .jubelt, groesse: 120)
            Text("Haven ist eingeschaltet")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
            Text("Safari und Apps bieten dir jetzt deine Konten an. Öffne einmal die App Haven, koppel das Handy mit dem PC und warte, bis die Passwörter da sind.")
                .font(.body)
                .foregroundStyle(Color.tinte2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: fertig) {
                Text("Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(Abstand.xl)
    }
}
