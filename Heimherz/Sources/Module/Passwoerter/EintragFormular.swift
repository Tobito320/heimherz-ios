import SwiftUI

/// Was das Formular tut: neuer Eintrag der Art `login` oder `notiz`, oder einen bestehenden bearbeiten.
enum FormularZiel: Identifiable {
    case neu(String)
    case bearbeiten(Eintrag)

    var id: String {
        switch self {
        case .neu(let art): return "neu-\(art)"
        case .bearbeiten(let e): return "bearbeiten-\(e.id)"
        }
    }
}

/// Neu und Bearbeiten für Login und Notiz, mit mehreren Webseiten, Einmalcode und Generator.
struct EintragFormular: View {
    let store: TresorStore
    let ziel: FormularZiel

    @Environment(\.dismiss) private var schliessen
    @State private var entwurf: Entwurf
    @State private var zeigePasswort = false
    @State private var zeigeGenerator = false
    @State private var speichert = false

    init(store: TresorStore, ziel: FormularZiel) {
        self.store = store
        self.ziel = ziel
        switch ziel {
        case .neu(let art): _entwurf = State(initialValue: Entwurf(art: art))
        case .bearbeiten(let e): _entwurf = State(initialValue: Entwurf(eintrag: e))
        }
    }

    private var istLogin: Bool { entwurf.art == Eintrag.artLogin }

    private var titel: String {
        switch ziel {
        case .neu: return istLogin ? "Neues Konto" : "Neue Notiz"
        case .bearbeiten: return "Bearbeiten"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $entwurf.name)
                        .textInputAutocapitalization(.words)
                    if istLogin {
                        TextField("Benutzer", text: $entwurf.benutzer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        passwortFeld
                    }
                }
                .listRowBackground(Color.karte)
                if istLogin {
                    Section("Webseiten") {
                        ForEach($entwurf.urlFelder) { $feld in
                            TextField("https://beispiel.de", text: $feld.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        .onDelete { entwurf.urlFelder.remove(atOffsets: $0); if entwurf.urlFelder.isEmpty { entwurf.urlFelder = [Entwurf.UrlFeld()] } }
                        Button { entwurf.urlFelder.append(Entwurf.UrlFeld()) } label: { Label("Webseite hinzufügen", systemImage: "plus.circle") }
                            .frame(minHeight: Abstand.tippflaeche, alignment: .leading)
                    }
                    .listRowBackground(Color.karte)
                    Section {
                        TextField("Einmalcode (otpauth:// oder Geheimnis)", text: $entwurf.totp)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text("Einmalcode")
                    } footer: {
                        if !entwurf.totpGueltig {
                            Text("Den Einmalcode kann ich nicht lesen. Erwartet wird ein otpauth://-Link oder das Geheimnis in Buchstaben und Ziffern.")
                                .foregroundStyle(Color.schlecht)
                        }
                    }
                    .listRowBackground(Color.karte)
                }
                Section("Notiz") {
                    TextField("Notiz", text: $entwurf.notiz, axis: .vertical)
                        .lineLimit(3...10)
                }
                .listRowBackground(Color.karte)
                Section {
                    Toggle("Favorit", isOn: $entwurf.favorit)
                        .tint(Color.knopf)
                }
                .listRowBackground(Color.karte)
            }
            .scrollContentBackground(.hidden)
            .heimherzHintergrund()
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                        .disabled(!entwurf.kannSpeichern || speichert)
                }
            }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $zeigeGenerator) { GeneratorBlatt { entwurf.passwort = $0; zeigePasswort = true } }
        .interactiveDismissDisabled(speichert)
    }

    private var passwortFeld: some View {
        HStack(spacing: Abstand.s) {
            Group {
                if zeigePasswort {
                    TextField("Passwort", text: $entwurf.passwort)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("Passwort", text: $entwurf.passwort)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button { zeigePasswort.toggle() } label: {
                Image(systemName: zeigePasswort ? "eye.slash" : "eye").frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.gruen)
            .accessibilityLabel(zeigePasswort ? "Passwort verbergen" : "Passwort zeigen")
            Button { zeigeGenerator = true } label: {
                Image(systemName: "wand.and.stars").frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.gruen)
            .accessibilityLabel("Passwort erzeugen")
        }
    }

    private func sichern() {
        speichert = true
        let eintrag: Eintrag
        switch ziel {
        case .neu: eintrag = entwurf.neuerEintrag()
        case .bearbeiten(let alt): eintrag = entwurf.anwenden(auf: store.eintrag(alt.id) ?? alt)
        }
        Task {
            await store.speichere(eintrag)
            Haptik.erfolg()
            schliessen()
        }
    }
}
