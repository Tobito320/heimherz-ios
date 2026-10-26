import PhotosUI
import QuickLook
import SwiftUI

/// Tab "Dateien" (SPEC 12): wie Apples Dateien. Ein NavigationStack mit einem Ordner je Stufe (großer Titel, Zurück-Pfeil), Suche, Symbol- und Listenansicht,
/// Sortierung, Vorschaubilder, Langdruck-Menü (Teilen, Informationen, Papierkorb), Hochladen.
struct DateienTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @State private var lader: DateiVorschauLader?
    @State private var pfad: [OrdnerZiel] = []
    @State private var aufgeraeumt = false

    init() {
        #if DEBUG
        // Nur Screenshots in CI: `-heimherzDateienOrdner "Bürokratie/4 Geld"` öffnet den Ordner.
        if let name = UserDefaults.standard.string(forKey: "heimherzDateienOrdner") {
            _pfad = State(initialValue: DateiPfad.stufen(DateiPfad.teile(name)).map { OrdnerZiel(ordner: $0) })
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $pfad) {
            Group {
                if !umgebung.istGekoppelt {
                    ScrollView { LeerZustand(stimmung: .schlaeft, titel: "Dateien", text: "Koppel zuerst dein Handy mit dem PC (Tab Einstellungen).") }
                        .navigationTitle("Dateien")
                } else if let lader {
                    OrdnerSeite(ordner: [], umgebung: umgebung, lader: lader, navigation: $pfad)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(for: OrdnerZiel.self) { ziel in
                if let lader { OrdnerSeite(ordner: ziel.ordner, umgebung: umgebung, lader: lader, navigation: $pfad) }
            }
        }
        .id(umgebung.kopplung)
        .task(id: umgebung.kopplung) {
            guard umgebung.istGekoppelt else { lader = nil; return }
            if !umgebung.istDemo, !aufgeraeumt {
                VorschauCache.leere()
                aufgeraeumt = true
            }
            lader = DateiVorschauLader(holen: DateiVorschauLader.holenFuer(umgebung))
        }
    }
}

/// Ein Ordner: Liste oder Raster, Suche, Menüs. Hält sein eigenes Modell; die Stufen des Stapels leben im NavigationStack.
struct OrdnerSeite: View {
    let ordner: [String]
    let lader: DateiVorschauLader
    @Binding var navigation: [OrdnerZiel]

    @Environment(\.dynamicTypeSize) private var schriftgroesse
    @State private var modell: DateienModell
    @State private var startModell: DateienStartModell
    @State private var suchModell: DateienSucheModell
    @State private var suchtext: String
    @State private var bereich = SuchBereich.alle
    @AppStorage("heimherzDateienAnsicht") private var ansicht = "symbole"
    @AppStorage("heimherzDateienSortierung") private var sortierungRoh = "name-auf"
    @AppStorage("heimherzDateienEingeklappt") private var eingeklappt = EingeklappteAbschnitte()
    @State private var zeigeImport = false
    @State private var zeigeFotos = false
    @State private var fotoAuswahl: [PhotosPickerItem] = []
    @State private var frageWeg: Gewaehlt?
    @State private var info: Gewaehlt?
    @State private var vorschau: URL?
    @State private var teilen: TeilenZiel?
    @State private var laedt: String?

    init(ordner: [String], umgebung: AppUmgebung, lader: DateiVorschauLader, navigation: Binding<[OrdnerZiel]>) {
        self.ordner = ordner
        self.lader = lader
        _navigation = navigation
        let holeClient: @MainActor () throws -> HeimClient = { try umgebung.client() }
        _modell = State(initialValue: DateienModell(ordner: ordner, istDemo: umgebung.istDemo, holeClient: holeClient))
        _startModell = State(initialValue: DateienStartModell(istDemo: umgebung.istDemo, holeClient: holeClient))
        _suchModell = State(initialValue: DateienSucheModell(demo: umgebung.istDemo ? DateienDemo.treffer : nil, holeClient: holeClient))
        _suchtext = State(initialValue: Self.startSuche)
    }

    /// Nur Screenshots in CI: `-heimherzDateienSuche "rechnung"` startet mit diesem Suchtext.
    private static var startSuche: String {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "heimherzDateienSuche") ?? ""
        #else
        return ""
        #endif
    }

    private var titel: String { ordner.last ?? "Dateien" }
    private var sortierung: DateiSortierung { DateiSortierung(rohwert: sortierungRoh) ?? .standard }
    private var sortiert: [DateiInfo] { sortierung.sortiere(modell.eintraege) }
    private var istSuche: Bool { !suchtext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var suchPfad: String { bereich == .alle ? "" : modell.pfad }

    var body: some View {
        hauptteil
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(ordner.isEmpty ? .large : .inline)
            .searchable(text: $suchtext, placement: .navigationBarDrawer(displayMode: .always), prompt: "Suchen")
            .modifier(SuchBereiche(aktiv: !ordner.isEmpty, auswahl: $bereich, ordnerName: titel))
            .onChange(of: suchtext) { _, _ in starteSuche() }
            .onChange(of: bereich) { _, _ in starteSuche() }
            .safeAreaInset(edge: .top, spacing: 0) { banner }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { mehrMenue }
            }
            .overlay { ladeAnzeige }
            .quickLookPreview($vorschau)
            .sheet(item: $info) { DateiInfoBlatt(gewaehlt: $0) }
            .sheet(item: $teilen) { TeilenBlatt(url: $0.url).presentationDetents([.medium, .large]) }
            .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.item], allowsMultipleSelection: true) { ergebnis in
                guard case .success(let urls) = ergebnis else { return }
                Task { await ladeHoch(urls) }
            }
            .photosPicker(isPresented: $zeigeFotos, selection: $fotoAuswahl, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
            .onChange(of: fotoAuswahl) { _, neu in
                guard !neu.isEmpty else { return }
                fotoAuswahl = []
                Task { await ladeHoch(fotos: neu) }
            }
            .confirmationDialog(
                frageWeg.map { "„\($0.info.name)“ in den Papierkorb am PC legen?" } ?? "",
                isPresented: Binding(get: { frageWeg != nil }, set: { if !$0 { frageWeg = nil } }),
                titleVisibility: .visible, presenting: frageWeg
            ) { g in
                Button("In den Papierkorb", role: .destructive) { Task { await papierkorb(g) } }
                Button("Abbrechen", role: .cancel) {}
            } message: { _ in
                Text("Am PC landet es im Papierkorb. Dort kannst du es zurückholen.")
            }
            .task {
                if ordner.isEmpty { await startModell.lade() } else { await modell.lade() }
                if istSuche { starteSuche() }
            }
    }

    // MARK: Aufbau

    @ViewBuilder private var hauptteil: some View {
        if istSuche { ergebnisse } else if ordner.isEmpty { startseite } else { inhalt }
    }

    // MARK: Startseite (wie "Durchsuchen" in Dateien)

    @ViewBuilder private var startseite: some View {
        switch startModell.zustand {
        case .laedt where startModell.abschnitte.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .fehler(let text, let offline) where startModell.abschnitte.isEmpty:
            ContentUnavailableView {
                Label(offline ? "PC nicht erreichbar" : "Das hat nicht geklappt", systemImage: offline ? "wifi.slash" : "exclamationmark.triangle")
            } description: {
                Text(text)
            } actions: {
                Button("Erneut versuchen") { Task { await startModell.lade() } }
            }
        default:
            if startModell.abschnitte.isEmpty {
                ContentUnavailableView("Noch keine Dateien", systemImage: "folder")
            } else {
                List {
                    ForEach(startModell.abschnitte) { a in
                        Section {
                            if !eingeklappt.istEingeklappt(a.kategorie) {
                                ForEach(a.zeilen) { startZeile($0) }
                            }
                        } header: {
                            abschnittsKopf(a.kategorie)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await startModell.lade() }
            }
        }
    }

    /// Fette Überschrift mit Pfeil rechts, der den Abschnitt ein- und ausklappt (wie "Speicherorte" im Vorbild).
    private func abschnittsKopf(_ k: DateiKategorie) -> some View {
        let zu = eingeklappt.istEingeklappt(k)
        return Button {
            withAnimation { eingeklappt.schalte(k) }
        } label: {
            HStack {
                Text(k.titel).font(.title3.bold()).foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(zu ? -90 : 0))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(zu ? "eingeklappt" : "ausgeklappt")
    }

    /// Eine Zeile: blaues Symbol, Name, Pfeil. Ordner öffnen die Rasteransicht, Dateien die Vorschau.
    @ViewBuilder private func startZeile(_ z: StartZeile) -> some View {
        let beschriftung = HStack(spacing: 12) {
            Image(systemName: z.symbol).font(.title3).foregroundStyle(Color.blue).frame(width: 28).accessibilityHidden(true)
            Text(z.info.name).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        if z.info.ordner {
            NavigationLink(value: OrdnerZiel(ordner: DateiPfad.teile(z.pfad))) { beschriftung }
        } else {
            Button { Task { await oeffne(Gewaehlt(info: z.info, pfad: z.pfad)) } } label: { beschriftung }
        }
    }

    @ViewBuilder private var inhalt: some View {
        switch modell.zustand {
        case .laedt where modell.eintraege.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .fehler(let text, let offline) where modell.eintraege.isEmpty:
            ContentUnavailableView {
                Label(offline ? "PC nicht erreichbar" : "Das hat nicht geklappt", systemImage: offline ? "wifi.slash" : "exclamationmark.triangle")
            } description: {
                Text(text)
            } actions: {
                Button("Erneut versuchen") { Task { await modell.lade() } }
            }
        default:
            if modell.eintraege.isEmpty {
                ContentUnavailableView("Ordner ist leer", systemImage: "folder")
            } else if ansicht == "liste" {
                liste
            } else {
                raster
            }
        }
    }

    /// Wie im Vorbild unter dem Inhalt, mittig: "9 Objekte" fett, darunter der Stand.
    private var fusszeile: some View {
        VStack(spacing: 6) {
            Text(DateiAnzeige.objekte(modell.eintraege.count)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            Text(warnung == nil ? DateiAnzeige.synchron : DateiAnzeige.getrennt).font(.subheadline).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var liste: some View {
        List {
            ForEach(sortiert) { e in
                let g = Gewaehlt(info: e, pfad: DateiPfad.zusammen(ordner, e.name))
                Group {
                    if e.ordner {
                        NavigationLink(value: OrdnerZiel(ordner: ordner + [e.name])) {
                            ListenZeile(eintrag: e, pfad: g.pfad, lader: lader)
                        }
                    } else {
                        Button { Task { await oeffne(g) } } label: {
                            ListenZeile(eintrag: e, pfad: g.pfad, lader: lader)
                        }
                    }
                }
                .contextMenu { menue(g) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { frageWeg = g } label: { Label("Papierkorb", systemImage: "trash") }
                }
            }
            fusszeile.listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .refreshable { await modell.lade() }
    }

    private var raster: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: schriftgroesse.isAccessibilitySize ? 160 : 104), spacing: 12, alignment: .top)], spacing: 44) {
                ForEach(sortiert) { e in
                    let g = Gewaehlt(info: e, pfad: DateiPfad.zusammen(ordner, e.name))
                    Group {
                        if e.ordner {
                            NavigationLink(value: OrdnerZiel(ordner: ordner + [e.name])) {
                                RasterZelle(eintrag: e, pfad: g.pfad, lader: lader)
                            }
                        } else {
                            Button { Task { await oeffne(g) } } label: {
                                RasterZelle(eintrag: e, pfad: g.pfad, lader: lader)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menue(g) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            fusszeile.padding(.vertical, 40)
        }
        .refreshable { await modell.lade() }
    }

    @ViewBuilder private var ergebnisse: some View {
        if !suchModell.treffer.isEmpty {
            List {
                ForEach(suchModell.treffer) { t in
                    let g = Gewaehlt(info: t.info, pfad: t.pfad)
                    Button { Task { await oeffneTreffer(t) } } label: {
                        TrefferZeile(treffer: t, lader: lader)
                    }
                    .contextMenu { menue(g) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { frageWeg = g } label: { Label("Papierkorb", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
        } else {
            switch suchModell.zustand {
            case .fehler(let text):
                ContentUnavailableView {
                    Label("Suche nicht möglich", systemImage: "wifi.slash")
                } description: {
                    Text(text)
                }
            case .bereit:
                ContentUnavailableView.search(text: suchtext)
            case .laedt, .leer:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func menue(_ g: Gewaehlt) -> some View {
        if !g.info.ordner {
            Button("Teilen", systemImage: "square.and.arrow.up") { Task { await teile(g) } }
        }
        Button("Informationen", systemImage: "info.circle") { info = g }
        Button("In den Papierkorb", systemImage: "trash", role: .destructive) { frageWeg = g }
    }

    // MARK: Leisten und Menüs

    /// Der runde Drei-Punkte-Knopf oben rechts (wie in Dateien): Ansicht, Sortieren, Hochladen.
    private var mehrMenue: some View {
        Menu {
            if !ordner.isEmpty {
                Picker("Ansicht", selection: $ansicht) {
                    Label("Symbole", systemImage: "square.grid.2x2").tag("symbole")
                    Label("Liste", systemImage: "list.bullet").tag("liste")
                }
                .pickerStyle(.inline)
                Section("Sortieren nach") {
                    ForEach(SortierKriterium.allCases, id: \.self) { k in sortierKnopf(k) }
                }
            }
            Section {
                Button("Aus Dateien …", systemImage: "folder") { zeigeImport = true }
                Button("Aus Fotos …", systemImage: "photo.on.rectangle") { zeigeFotos = true }
            }
            .disabled(modell.istDemo)
        } label: {
            Label("Mehr", systemImage: "ellipsis")
        }
        .tint(.primary)   // wie Apple Dateien: weiße Punkte, nicht die Akzentfarbe
    }

    private func sortierKnopf(_ k: SortierKriterium) -> some View {
        let aktiv = sortierung.kriterium == k
        let aufsteigend = sortierung.aufsteigend
        return Button {
            sortierungRoh = sortierung.nachTippen(auf: k).rohwert
        } label: {
            if aktiv {
                Label(k.titel, systemImage: aufsteigend ? "chevron.up" : "chevron.down")
            } else {
                Text(k.titel)
            }
        }
        .accessibilityValue(aktiv ? (aufsteigend ? "aufsteigend" : "absteigend") : "")
    }

    /// Meldungen, Upload-Stand und Offline-Hinweis oben, über dem Inhalt; ohne etwas davon 0 pt hoch.
    private var warnung: (text: String, offline: Bool)? {
        let zustand = ordner.isEmpty ? startModell.zustand : modell.zustand
        let hatDaten = ordner.isEmpty ? !startModell.abschnitte.isEmpty : !modell.eintraege.isEmpty
        guard case .fehler(let text, let offline) = zustand, hatDaten else { return nil }
        return (offline ? "Offline: \(text)" : text, offline)
    }

    private var banner: some View {
        let hat = modell.meldung != nil || modell.uebertragungen > 0 || warnung != nil
        return VStack(spacing: 6) {
            if let meldung = modell.meldung {
                HStack {
                    StatusChip(text: meldung, symbol: modell.meldungIstFehler ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", ton: modell.meldungIstFehler ? .warn : .ok)
                    Spacer(minLength: 0)
                    Button("Schließen", systemImage: "xmark") { modell.quittiereMeldung() }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            if modell.uebertragungen > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(modell.uebertragungen == 1 ? "Lade 1 Datei hoch …" : "Lade \(modell.uebertragungen) Dateien hoch …")
                        .font(.subheadline).foregroundStyle(Color.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if let warnung {
                HStack {
                    StatusChip(text: warnung.text, symbol: warnung.offline ? "wifi.slash" : "exclamationmark.triangle.fill", ton: .warn)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, hat ? 6 : 0)
        .background { if hat { Rectangle().fill(.bar) } }
    }

    @ViewBuilder private var ladeAnzeige: some View {
        if let laedt {
            ProgressView { Text("„\(laedt)“ wird geladen …") }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Handlungen

    private func starteSuche() {
        suchModell.suche(text: suchtext, pfad: suchPfad)
    }

    /// Datei antippen: laden (mit Anzeige), dann die Vorschau des Systems (dort auch Teilen).
    private func oeffne(_ g: Gewaehlt) async {
        guard laedt == nil, !modell.istDemo else { return }
        laedt = g.info.name
        defer { laedt = nil }
        do { vorschau = try await modell.laden(pfad: g.pfad, name: g.info.name) } catch { modell.meldeFehler(error) }
    }

    private func teile(_ g: Gewaehlt) async {
        guard laedt == nil, !modell.istDemo else { return }
        laedt = g.info.name
        defer { laedt = nil }
        do { teilen = TeilenZiel(url: try await modell.laden(pfad: g.pfad, name: g.info.name)) } catch { modell.meldeFehler(error) }
    }

    /// Treffer antippen: Ordner öffnen (der Stapel wird bis dorthin aufgebaut, "Zurück" führt Stufe für Stufe heraus), Datei ansehen.
    private func oeffneTreffer(_ t: SuchTreffer) async {
        if t.ordner {
            suchtext = ""
            navigation = DateiPfad.stufen(DateiPfad.teile(t.pfad)).map { OrdnerZiel(ordner: $0) }
        } else {
            await oeffne(Gewaehlt(info: t.info, pfad: t.pfad))
        }
    }

    private func papierkorb(_ g: Gewaehlt) async {
        if await modell.inPapierkorb(pfad: g.pfad, name: g.info.name) {
            if ordner.isEmpty { await startModell.lade() }
            if istSuche { suchModell.wiederhole() }
        }
    }

    // MARK: Hochladen

    private func ladeHoch(_ urls: [URL]) async {
        var dateien: [(url: URL, name: String)] = []
        var zugriff: [URL] = []
        for u in urls where u.startAccessingSecurityScopedResource() {
            zugriff.append(u)
            dateien.append((u, u.lastPathComponent))
        }
        await modell.hochladen(dateien)
        if ordner.isEmpty { await startModell.lade() }
        zugriff.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func ladeHoch(fotos: [PhotosPickerItem]) async {
        var dateien: [(url: URL, name: String)] = []
        let jetzt = Date()
        for (i, item) in fotos.enumerated() {
            guard let datei = try? await item.loadTransferable(type: AusgewaehlteDatei.self) else { continue }
            let name = DateiNamen.fotoName(datum: jetzt, endung: datei.url.pathExtension, nummer: i + 1)
            dateien.append((datei.url, name))
        }
        await modell.hochladen(dateien)
        if ordner.isEmpty { await startModell.lade() }
        for d in dateien { try? FileManager.default.removeItem(at: d.url.deletingLastPathComponent()) }
    }
}
