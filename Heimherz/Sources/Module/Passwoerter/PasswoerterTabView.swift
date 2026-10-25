import SwiftUI

/// Tab "Passwörter" (SPEC 9): Wurzel. Der Store entsteht einmal pro Ansicht (`State(initialValue:)`, der Initialisierer ist billig und ohne Nebenwirkung).
struct PasswoerterTabView: View {
    @Environment(AppUmgebung.self) private var umgebung

    var body: some View {
        PasswoerterInhalt(umgebung: umgebung)
    }
}

/// Zusammenspiel aus Sperre, Kopplung und Store: gesperrt oder nicht gekoppelt = Klartext raus; entsperrt = öffnen und abgleichen.
struct PasswoerterInhalt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.scenePhase) private var phase
    @State private var store: TresorStore
    @State private var suche = ""
    @State private var pfad: [String] = []
    @State private var formular: FormularZiel?
    @State private var zeigeGenerator = false

    init(umgebung: AppUmgebung) {
        _store = State(initialValue: TresorStore(umgebung: umgebung))
    }

    /// Ändert sich einer der Werte, startet `.task(id:)` neu.
    private struct Lage: Equatable {
        let gesperrt: Bool
        let gekoppelt: Bool
    }

    private var lage: Lage { Lage(gesperrt: umgebung.sperre.gesperrt, gekoppelt: umgebung.istGekoppelt) }

    var body: some View {
        NavigationStack(path: $pfad) {
            inhalt
                .navigationTitle("Passwörter")
                .navigationDestination(for: String.self) { id in
                    EintragDetailView(store: store, id: id) { formular = .bearbeiten($0) }
                }
                .toolbar {
                    if store.zustand == .bereit {
                        ToolbarItem(placement: .primaryAction) { neuMenue }
                    }
                }
                .heimherzHintergrund()
        }
        .sheet(item: $formular) { ziel in EintragFormular(store: store, ziel: ziel) }
        .sheet(isPresented: $zeigeGenerator) { GeneratorBlatt(uebernehmen: nil) }
        .task(id: lage) { await lageAnwenden() }
        .onChange(of: phase) { _, neu in
            if neu == .active, lage.gekoppelt, !lage.gesperrt { Task { await store.abgleichen() } }
        }
    }

    private func lageAnwenden() async {
        if lage.gesperrt || !lage.gekoppelt {
            store.sperren()
            suche = ""
            pfad = []
            formular = nil
            zeigeGenerator = false
            if !lage.gekoppelt, !umgebung.istDemo { await AutoFillIdentitaeten.leeren() }
            return
        }
        await store.oeffnen()
    }

    // MARK: Inhalt

    @ViewBuilder
    private var inhalt: some View {
        if !umgebung.istGekoppelt {
            ScrollView {
                LeerZustand(titel: "Passwörter", text: "Koppel zuerst dein Handy mit dem PC (Tab Mehr). Danach liegen deine Passwörter hier und in Safari und Apps.")
            }
        } else {
            switch store.zustand {
            case .leer, .laedt:
                VStack(spacing: Abstand.m) {
                    ProgressView()
                    Text("Tresor wird geöffnet …")
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fehler(let text):
                ScrollView {
                    FehlerKarte(text: text) { Task { await store.oeffnen() } }
                        .padding(Abstand.l)
                }
            case .bereit:
                liste
            }
        }
    }

    private var neuMenue: some View {
        Menu {
            Button { formular = .neu(Eintrag.artLogin) } label: { Label("Neues Konto", systemImage: "person.badge.key") }
            Button { formular = .neu(Eintrag.artNotiz) } label: { Label("Neue Notiz", systemImage: "note.text") }
            Button { zeigeGenerator = true } label: { Label("Passwort-Generator", systemImage: "wand.and.stars") }
        } label: {
            Image(systemName: "plus")
                .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
        }
        .accessibilityLabel("Neu")
    }

    private var gefiltert: [Eintrag] {
        EintragSuche.filtern(EintragSuche.sortiert(store.eintraege), begriff: suche)
    }

    private var liste: some View {
        List {
            Section { statusZeile }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if store.eintraege.isEmpty {
                Section {
                    LeerZustand(
                        titel: "Noch keine Einträge",
                        text: "Importiere am PC mit `heimherz import bitwarden` oder lege hier ein neues Konto an.",
                        aktionTitel: "Neues Konto"
                    ) { formular = .neu(Eintrag.artLogin) }
                }
                .listRowBackground(Color.clear)
            } else if gefiltert.isEmpty {
                Section {
                    Text("Nichts gefunden für „\(suche)“.")
                        .font(.body)
                        .foregroundStyle(Color.tinte2)
                }
                .listRowBackground(Color.karte)
            } else if suche.trimmingCharacters(in: .whitespaces).isEmpty {
                let favoriten = gefiltert.filter(\.favorit)
                if !favoriten.isEmpty {
                    Section("Favoriten") { zeilen(favoriten) }
                    Section("Alle") { zeilen(gefiltert.filter { !$0.favorit }) }
                } else {
                    Section { zeilen(gefiltert) }
                }
            } else {
                Section("Treffer") { zeilen(gefiltert) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $suche, prompt: "Name, Benutzer oder Webseite")
        .refreshable { await store.abgleichen() }
    }

    private func zeilen(_ eintraege: [Eintrag]) -> some View {
        ForEach(eintraege) { e in
            NavigationLink(value: e.id) { EintragZeile(eintrag: e) }
                .listRowBackground(Color.karte)
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusZeile: some View {
        VStack(alignment: .leading, spacing: Abstand.s) {
            if let fehler = store.abgleichFehler {
                StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn)
            } else if store.offlineText != nil {
                StatusChip(text: "PC nicht erreichbar, alles geht weiter", symbol: "icloud.slash", ton: .neutral)
            } else if store.gleichtAb {
                StatusChip(text: "Gleiche ab …", symbol: "arrow.triangle.2.circlepath", ton: .neutral)
            }
            if let zuletzt = store.zuletzt {
                Text("Zuletzt abgeglichen: \(zuletzt.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            } else {
                Text("Noch nicht mit dem PC abgeglichen")
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
            if let offline = store.offlineText {
                Text(offline)
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
        }
        .padding(.horizontal, Abstand.l)
        .padding(.vertical, Abstand.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Eine Zeile der Liste: Anfangsbuchstabe, Name, Benutzer; Symbole für Favorit und Einmalcode.
struct EintragZeile: View {
    let eintrag: Eintrag

    private var istNotiz: Bool { eintrag.art == Eintrag.artNotiz }

    var body: some View {
        HStack(spacing: Abstand.m) {
            Text(String(eintrag.name.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(Color.gruen)
                .frame(width: 40, height: 40)
                .background(Color.chip, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name)
                    .font(.headline)
                    .foregroundStyle(Color.tinte)
                Text(untertitel)
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
                    .lineLimit(1)
            }
            Spacer(minLength: Abstand.s)
            if eintrag.favorit { Image(systemName: "star.fill").foregroundStyle(Color.warn).accessibilityHidden(true) }
            if !eintrag.totp.isEmpty { Image(systemName: "timer").foregroundStyle(Color.tinte2).accessibilityHidden(true) }
        }
        .padding(.vertical, Abstand.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beschriftung)
    }

    private var untertitel: String {
        if istNotiz { return "Notiz" }
        if !eintrag.benutzer.isEmpty { return eintrag.benutzer }
        return EintragSuche.hosts(von: eintrag).first ?? ""
    }

    private var beschriftung: String {
        var teile = [eintrag.name.isEmpty ? "Ohne Namen" : eintrag.name, untertitel]
        if eintrag.favorit { teile.append("Favorit") }
        if !eintrag.totp.isEmpty { teile.append("mit Einmalcode") }
        return teile.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
