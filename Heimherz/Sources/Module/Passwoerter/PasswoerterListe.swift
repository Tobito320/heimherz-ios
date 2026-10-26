import SwiftUI

/// Die Liste hinter einer Kachel (Alle, Favoriten, Passkeys, Codes, Sicherheit, Gelöscht) im Stil der Passwörter-App von Apple:
/// A bis Z Leiste, Sortierung (in "Alle" auch "Zuletzt benutzt"), "Auswählen" mit Mehrfach-Löschen, Suche und Plus unten.
/// "Sicherheit" hat oben "In Datenlecks gefunden" und "Doppelt" (zwei Einträge für dasselbe Konto, Vergleich im Blatt), darunter die Empfehlungen.
struct PasswoerterListe: View {
    let store: TresorStore
    let kategorie: PasswoerterKategorie
    var neu: (FormularZiel) -> Void
    var generator: () -> Void

    private enum Frage { case loeschen, endgueltig }

    @State private var suche = ""
    @State private var sortierung: Sortierung = .name
    @State private var bearbeiten: EditMode = .inactive
    @State private var auswahl = Set<String>()
    @State private var frage: Frage?
    @State private var kopiert: String?
    @State private var vergleich: DoppelteGruppe?
    /// Wann welches Konto zuletzt benutzt wurde; einmal geladen (nicht bei jedem Zeichnen), für "Zuletzt benutzt".
    @State private var benutzt: [String: Date] = [:]
    @Environment(\.openURL) private var oeffneURL

    private var jetzt: Date { Date() }

    private var alle: [Eintrag] {
        guard let t = store.tresor else { return [] }
        return PasswoerterLogik.eintraege(kategorie, in: t, jetzt: jetzt, lecks: store.leckIds)
    }

    private var gefiltert: [Eintrag] { EintragSuche.filtern(alle, begriff: suche) }

    /// In "Sicherheit" stehen Datenlecks in einem eigenen Abschnitt oben und nicht noch einmal in A bis Z.
    private var leckZeilen: [Eintrag] {
        kategorie == .sicherheit ? EintragSuche.sortiert(gefiltert.filter { store.leckIds.contains($0.id) }) : []
    }

    private var abschnitte: [Abschnitt] {
        let rest = kategorie == .sicherheit ? gefiltert.filter { !store.leckIds.contains($0.id) } : gefiltert
        return PasswoerterLogik.abschnitte(rest, sortierung: sortierung, benutzt: benutzt)
    }

    /// Doppelte Konten (nur "Sicherheit"); die Suche filtert nach Name, Benutzer und Host der beteiligten Einträge.
    private var doppelte: [DoppelteGruppe] {
        guard kategorie == .sicherheit, let t = store.tresor else { return [] }
        let gruppen = DoppelteKonten.finde(t.lebendige)
        guard !suche.trimmingCharacters(in: .whitespaces).isEmpty else { return gruppen }
        let treffer = Set(EintragSuche.filtern(t.lebendige, begriff: suche).map(\.id))
        return gruppen.filter { g in g.ids.contains(where: treffer.contains) }
    }

    /// Eintrag-id zu Hinweis, für das rote Ausrufezeichen und die Gründe in "Sicherheit".
    private var hinweise: [String: SicherheitsHinweis] {
        Dictionary(PasswortSicherheit.pruefe(store.eintraege, lecks: store.leckIds).map { ($0.eintragId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var istBearbeiten: Bool { bearbeiten.isEditing }

    private var untertitel: String {
        let n = alle.count
        switch kategorie {
        case .passkeys: return n == 1 ? "1 Passkey" : "\(n) Passkeys"
        case .codes: return n == 1 ? "1 Code" : "\(n) Codes"
        case .sicherheit:
            let d = doppelte.count
            let empfehlungen = n == 1 ? "1 Empfehlung" : "\(n) Empfehlungen"
            return d == 0 ? empfehlungen : (n == 0 ? "\(d) doppelt" : "\(empfehlungen), \(d) doppelt")
        default: return n == 1 ? "1 Objekt" : "\(n) Objekte"
        }
    }

    private var hatPlus: Bool { [.alle, .favoriten, .codes].contains(kategorie) }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $auswahl) {
                if hatKopf {
                    Section { kopfKarte }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Abstand.s, leading: Abstand.l, bottom: Abstand.s, trailing: Abstand.l))
                        .listRowSeparator(.hidden)
                }
                let hinweisListe = hinweise
                if kategorie == .sicherheit, !istBearbeiten {
                    Section {
                        NavigationLink(value: PasswoerterZiel.gesundheit) { GesundheitZeile(gesundheit: PasswortGesundheit.pruefe(store.eintraege)) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.haar)
                }
                if kategorie == .sicherheit {
                    if !leckZeilen.isEmpty {
                        Section {
                            ForEach(leckZeilen) { e in zeile(e, hinweis: hinweisListe[e.id]) }
                        } header: { abschnittTitel("In Datenlecks gefunden") }
                    }
                    if !istBearbeiten, !doppelte.isEmpty {
                        Section {
                            ForEach(doppelte) { g in doppeltZeile(g) }
                        } header: { abschnittTitel("Doppelt") }
                    }
                }
                let mitTitel = kategorie == .sicherheit && (!leckZeilen.isEmpty || !doppelte.isEmpty)
                let ersterAbschnitt = abschnitte.first?.id
                ForEach(abschnitte) { a in
                    if mitTitel, a.id == ersterAbschnitt {   // der Titel steht einmal über allen Buchstaben
                        Section {
                            ForEach(a.eintraege) { e in zeile(e, hinweis: hinweisListe[e.id]) }
                        } header: { abschnittTitel("Weitere Empfehlungen") }
                    } else {
                        Section {
                            ForEach(a.eintraege) { e in zeile(e, hinweis: hinweisListe[e.id]) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Platz für die A bis Z Leiste, damit sie Ring und Ausrufezeichen am Zeilenende nicht überdeckt.
            .contentMargins(.trailing, zeigeLeiste ? 22 : 0, for: .scrollContent)
            .overlay(alignment: .trailing) { leiste(proxy) }
            .overlay { leer }
        }
        .lumenHintergrund()
        .environment(\.editMode, $bearbeiten)
        .navigationTitle(kategorie.titel)
        .navigationSubtitle(untertitel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .searchable(text: $suche, prompt: "„\(kategorie.titel)“ durchsuchen")
        .toolbar { werkzeuge }
        .refreshable { await store.abgleichen() }
        .confirmationDialog(frageTitel, isPresented: Binding(get: { frage != nil }, set: { if !$0 { frage = nil } }), titleVisibility: .visible) {
            frageKnoepfe
        } message: {
            Text(frageText)
        }
        .overlay(alignment: .bottom) {
            if let kopiert {
                StatusChip(text: "\(kopiert) kopiert, 60 Sekunden", symbol: "doc.on.doc.fill", ton: .ok)
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Feder.weich, value: kopiert)
        .onChange(of: bearbeiten) { _, neu in if !neu.isEditing { auswahl = [] } }
        .onAppear {
            benutzt = Nutzung().zuletzt
            #if DEBUG
            if UserDefaults.standard.string(forKey: "heimherzPwOffen") == "vergleich" { vergleich = doppelte.first }   // nur Screenshots in CI
            #endif
        }
        .sheet(item: $vergleich) { g in VergleichBlatt(store: store, gruppe: g) }
    }

    private func abschnittTitel(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.tinte2)
            .textCase(nil)
    }

    /// Eine Gruppe doppelter Konten: Name des ersten, Benutzer und wie viele Einträge. Antippen öffnet den Vergleich.
    private func doppeltZeile(_ g: DoppelteGruppe) -> some View {
        let eintraege = g.ids.compactMap { store.eintrag($0) }
        return Button { Haptik.auswahl(); vergleich = g } label: {
            HStack(spacing: Abstand.m) {
                if let erster = eintraege.first { SymbolKachel(eintrag: erster) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(eintraege.first.map { $0.name.isEmpty ? "Ohne Namen" : $0.name } ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.tinte)
                        .lineLimit(1)
                    Text([eintraege.first?.benutzer ?? "", "\(eintraege.count) Einträge"].filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                        .lineLimit(1)
                }
                Spacer(minLength: Abstand.s)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.tinte3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Abstand.xs)
            .frame(minHeight: Abstand.tippflaeche)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.haar)
        .accessibilityHint("Zeigt beide Einträge nebeneinander")
    }

    // MARK: Zeilen

    @ViewBuilder
    private func zeile(_ e: Eintrag, hinweis: SicherheitsHinweis?) -> some View {
        Group {
            if istBearbeiten {
                EintragZeile(eintrag: e, untertitel: zweiteZeile(e, hinweis), hinweis: kategorie != .sicherheit && hinweis != nil)
            } else if kategorie == .codes {
                Button { kopiereCode(e) } label: { CodeZeile(eintrag: e, freigegeben: store.codesFreigegeben) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        NavigationLink(value: PasswoerterZiel.eintrag(e.id)) { Label("Eintrag öffnen", systemImage: "chevron.right") }
                    }
            } else {
                NavigationLink(value: PasswoerterZiel.eintrag(e.id)) {
                    EintragZeile(eintrag: e, untertitel: zweiteZeile(e, hinweis), hinweis: kategorie != .sicherheit && hinweis != nil)
                }
                .contextMenu {
                    if kategorie == .sicherheit, let url = PasswoerterLogik.passwortAendernURL(von: e) {
                        Button { oeffneURL(url) } label: { Label("Passwort ändern …", systemImage: "key.horizontal") }
                    }
                }
            }
        }
        .tag(e.id)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.haar)
        .swipeActions(edge: .trailing, allowsFullSwipe: kategorie != .geloescht) {
            if kategorie == .geloescht {
                Button(role: .destructive) { auswahl = [e.id]; frage = .endgueltig } label: { Label("Endgültig löschen", systemImage: "trash") }
            } else {
                Button(role: .destructive) { Task { await store.loesche(ids: [e.id]) } } label: { Label("Löschen", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .leading) {
            if kategorie == .geloescht {
                Button { Task { await store.stelleWiederHer(ids: [e.id]) } } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                    .tint(Color.knopf)
            } else if kategorie == .sicherheit, let url = PasswoerterLogik.passwortAendernURL(von: e) {
                Button { oeffneURL(url) } label: { Label("Passwort ändern", systemImage: "key.horizontal") }
                    .tint(Color.knopf)
            }
        }
    }

    private func zweiteZeile(_ e: Eintrag, _ h: SicherheitsHinweis?) -> String? {
        switch kategorie {
        case .sicherheit:
            // Im Abschnitt "In Datenlecks gefunden" sagt die Überschrift schon den ersten Grund; hier steht der nächste.
            guard let h else { return nil }
            return store.leckIds.contains(e.id) ? h.gruende.dropFirst().first?.text : h.text
        case .passkeys:
            let konten = PasswoerterLogik.passkeys(von: e)
            return konten.first.map { $0.konto.isEmpty ? $0.seite : $0.konto }
        default: return nil
        }
    }

    // MARK: Kopf und leer

    private var hatKopf: Bool {
        switch kategorie {
        case .sicherheit, .passkeys, .geloescht: return true
        case .codes: return !store.codesFreigegeben && !alle.isEmpty
        default: return false
        }
    }

    @ViewBuilder
    private var kopfKarte: some View {
        switch kategorie {
        case .sicherheit:
            HinweisKarte(text: GeteilteEinstellungen().leckPruefung
                         ? "Lumen Cloud prüft auf diesem Handy, ob Passwörter mehrfach vorkommen oder leicht zu erraten sind. Für Datenlecks geht nur ein kurzer Teil einer Prüfsumme ins Netz, nie ein Passwort."
                         : "Lumen Cloud prüft auf diesem Handy, ob Passwörter mehrfach vorkommen oder leicht zu erraten sind. Die Prüfung auf Datenlecks ist ausgeschaltet.",
                         symbol: "lock.shield")
        case .passkeys:
            HinweisKarte(text: "Anmelden mit Passkey: auf der Seite \"Mit Passkey anmelden\" wählen, dann Lumen Cloud. Neue Passkeys landen auch hier.", symbol: "info.circle")
        case .codes:
            Button { Task { if await GeraeteAbfrage.pruefe(grund: "Einmalcodes anzeigen") { store.gebeCodesFrei() } } } label: {
                Label("Codes mit Face ID anzeigen", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.knopf)
            .foregroundStyle(Color.aufKnopf)
        case .geloescht:
            HinweisKarte(text: "Gelöschte Einträge bleiben 30 Tage hier und lassen sich wiederherstellen. Danach werden ihre Inhalte gelöscht.", symbol: "trash")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var leer: some View {
        if abschnitte.isEmpty, leckZeilen.isEmpty, doppelte.isEmpty {
            if !suche.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Nichts gefunden für „\(suche)“.")
                    .font(.body)
                    .foregroundStyle(Color.tinte2)
                    .padding(Abstand.l)
            } else {
                Text(leerText)
                    .font(.body)
                    .foregroundStyle(Color.tinte2)
                    .multilineTextAlignment(.center)
                    .padding(Abstand.xl)
            }
        }
    }

    private var leerText: String {
        switch kategorie {
        case .alle: return "Noch keine Einträge."
        case .favoriten: return "Noch keine Favoriten. Markiere einen Eintrag mit dem Stern."
        case .passkeys: return "Noch keine Passkeys. Importiere aus Bitwarden oder Apple Passwörter."
        case .codes: return "Noch keine Codes. Füge bei einem Konto einen Einmalcode hinzu."
        case .sicherheit: return "Keine Empfehlungen. Deine Passwörter sind einzigartig und nicht leicht zu erraten."
        case .geloescht: return "Nichts gelöscht."
        }
    }

    // MARK: Leiste

    private var zeigeLeiste: Bool {
        sortierung == .name && !istBearbeiten && abschnitte.count >= 6 && suche.isEmpty   // bei wenigen Buchstaben bringt die Leiste nichts
    }

    @ViewBuilder
    private func leiste(_ proxy: ScrollViewProxy) -> some View {
        let a = abschnitte
        if zeigeLeiste {
            AlphabetLeiste(buchstaben: a.map(\.kennung)) { b in
                if let id = a.first(where: { $0.kennung == b })?.eintraege.first?.id { proxy.scrollTo(id, anchor: .top) }
            }
            .frame(maxHeight: CGFloat(a.count) * 26)   // nie mehr Abstand als nötig, sonst verstreut sie sich über den ganzen Bildschirm
            .padding(.vertical, 80)
            .padding(.trailing, 2)
        }
    }

    // MARK: Werkzeuge

    @ToolbarContentBuilder
    private var werkzeuge: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !alle.isEmpty {
                Button(istBearbeiten ? "Fertig" : "Auswählen") {
                    Haptik.auswahl()
                    bearbeiten = istBearbeiten ? .inactive : .active
                }
            }
        }
        if istBearbeiten {
            ToolbarItem(placement: .bottomBar) {
                if kategorie == .geloescht {
                    Button("Wiederherstellen") { Task { await store.stelleWiederHer(ids: Array(auswahl)); auswahl = []; bearbeiten = .inactive } }
                        .disabled(auswahl.isEmpty)
                } else {
                    Button(auswahl.isEmpty ? "Löschen" : "Löschen (\(auswahl.count))", role: .destructive) { frage = .loeschen }
                        .disabled(auswahl.isEmpty)
                }
            }
            if kategorie == .geloescht {
                ToolbarItem(placement: .bottomBar) {
                    Button(auswahl.isEmpty ? "Endgültig löschen" : "Endgültig löschen (\(auswahl.count))", role: .destructive) { frage = .endgueltig }
                        .disabled(auswahl.isEmpty)
                }
            }
        } else {
            ToolbarItem(placement: .bottomBar) { sortierMenue }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            if hatPlus {
                ToolbarItem(placement: .bottomBar) { plusMenue }
            }
        }
    }

    private var sortierMenue: some View {
        Menu {
            Picker("Sortieren nach", selection: $sortierung) {
                ForEach(Sortierung.allCases.filter { $0 != .zuletztBenutzt || kategorie == .alle }, id: \.self) { Text($0.titel).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sortieren")
        .accessibilityValue(sortierung.titel)
        .onChange(of: sortierung) { _, neu in
            Haptik.auswahl()
            if neu == .zuletztBenutzt { benutzt = Nutzung().zuletzt }
        }
    }

    private var plusMenue: some View {
        Menu {
            Button { neu(.neu(Eintrag.artLogin)) } label: { Label("Neues Konto", systemImage: "person.badge.key") }
            Button { neu(.neu(Eintrag.artNotiz)) } label: { Label("Neue Notiz", systemImage: "note.text") }
            Button { generator() } label: { Label("Passwort-Generator", systemImage: "wand.and.stars") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Neu")
    }

    // MARK: Rückfrage

    private var frageTitel: String {
        let n = auswahl.count
        switch frage {
        case .loeschen: return n == 1 ? "Diesen Eintrag löschen?" : "\(n) Einträge löschen?"
        case .endgueltig: return n == 1 ? "Diesen Eintrag endgültig löschen?" : "\(n) Einträge endgültig löschen?"
        case nil: return ""
        }
    }

    private var frageText: String {
        switch frage {
        case .loeschen: return "Sie bleiben 30 Tage in „Gelöscht“ und lassen sich zurückholen. Auf deinen Geräten verschwinden sie aus der Liste."
        case .endgueltig: return "Passwörter, Codes und Notizen sind danach weg und lassen sich nicht zurückholen. Am PC bleibt eine alte Fassung im Verlauf des Tresors."
        case nil: return ""
        }
    }

    @ViewBuilder
    private var frageKnoepfe: some View {
        switch frage {
        case .loeschen:
            Button("Löschen", role: .destructive) { fuehreAus { await store.loesche(ids: $0) } }
        case .endgueltig:
            Button("Endgültig löschen", role: .destructive) { fuehreAus { await store.loescheEndgueltig(ids: $0) } }
        case nil:
            EmptyView()
        }
        Button("Abbrechen", role: .cancel) {}
    }

    private func fuehreAus(_ aktion: @escaping ([String]) async -> Void) {
        let ids = Array(auswahl)
        auswahl = []
        bearbeiten = .inactive
        Task { await aktion(ids) }
    }

    // MARK: Codes

    private func kopiereCode(_ e: Eintrag) {
        guard store.codesFreigegeben else {
            Task { if await GeraeteAbfrage.pruefe(grund: "Einmalcodes anzeigen") { store.gebeCodesFrei() } }
            return
        }
        // Entscheidet im Moment des Tippens: in den letzten Sekunden eines Codes geht gleich der nächste in die Zwischenablage.
        guard let k = PasswoerterLogik.codeZumKopieren(e.totp, datum: Date()) else { return }
        Zwischenablage.kopiere(k.code)
        Nutzung().merke(id: e.id)
        Haptik.erfolg()
        kopiert = k.istNaechster ? "Nächster Code" : "Code"
        Task {
            try? await Task.sleep(for: .seconds(2))
            kopiert = nil
        }
    }
}
