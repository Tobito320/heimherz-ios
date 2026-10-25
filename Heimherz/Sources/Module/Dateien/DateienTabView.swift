import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Tab "Dateien" (SPEC 12): Ordner vom PC durchsuchen, ansehen, teilen, hochladen, in den Papierkorb legen.
struct DateienTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @State private var modell: DateienModell?

    var body: some View {
        NavigationStack {
            Group {
                if !umgebung.istGekoppelt {
                    ScrollView { LeerZustand(stimmung: .schlaeft, titel: "Dateien", text: "Koppel zuerst dein Handy mit dem PC (Tab Mehr).") }
                } else if let modell {
                    DateienInhalt(modell: modell)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .heimherzHintergrund()
            .navigationTitle("Dateien")
        }
        .task(id: umgebung.istGekoppelt) {
            guard umgebung.istGekoppelt else { modell = nil; return }
            if modell == nil {
                if !umgebung.istDemo { VorschauCache.leere() }
                modell = DateienModell(istDemo: umgebung.istDemo) { try umgebung.client() }
            }
            await modell?.lade()
        }
    }
}

private struct DateienInhalt: View {
    let modell: DateienModell
    @State private var zeigeImport = false
    @State private var zeigeFotos = false
    @State private var fotoAuswahl: [PhotosPickerItem] = []
    @State private var offen: DateiInfo?
    @State private var frageWeg: DateiInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.l) {
                brotkrumen
                if let meldung = modell.meldung {
                    HStack {
                        StatusChip(text: meldung, symbol: modell.meldungIstFehler ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", ton: modell.meldungIstFehler ? .warn : .ok)
                        Spacer(minLength: 0)
                        Button("Schließen", systemImage: "xmark") { modell.quittiereMeldung() }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                    }
                }
                if modell.uebertragungen > 0 {
                    HStack(spacing: Abstand.s) {
                        ProgressView()
                        Text(modell.uebertragungen == 1 ? "Lade 1 Datei hoch …" : "Lade \(modell.uebertragungen) Dateien hoch …")
                            .font(.subheadline).foregroundStyle(Color.tinte2)
                    }
                    .accessibilityElement(children: .combine)
                }
                inhalt
            }
            .padding(.horizontal, Abstand.l)
            .padding(.bottom, Abstand.xl)
        }
        .refreshable { await modell.lade() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Aus Dateien …", systemImage: "folder") { zeigeImport = true }
                    Button("Aus Fotos …", systemImage: "photo.on.rectangle") { zeigeFotos = true }
                } label: {
                    Label("Hochladen", systemImage: "plus")
                }
                .disabled(modell.istDemo)
            }
        }
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
        .sheet(item: $offen) { datei in
            DateiBlatt(datei: datei, modell: modell) { frageWeg = datei }
        }
        .confirmationDialog(frageWeg.map { "„\($0.name)“ in den Papierkorb am PC legen?" } ?? "", isPresented: Binding(get: { frageWeg != nil }, set: { if !$0 { frageWeg = nil } }), titleVisibility: .visible, presenting: frageWeg) { datei in
            Button("In den Papierkorb", role: .destructive) {
                Task { if await modell.inPapierkorb(datei) { offen = nil } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Am PC landet es im Papierkorb. Dort kannst du es zurückholen.")
        }
    }

    // MARK: Aufbau

    private var brotkrumen: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Abstand.xs) {
                let stufen = DateiPfad.krumen(ordner: modell.ordner)
                ForEach(Array(stufen.enumerated()), id: \.offset) { i, stufe in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.tinte3).accessibilityHidden(true) }
                    if i == stufen.count - 1 {
                        Text(stufe.titel).font(.subheadline.weight(.bold)).foregroundStyle(Color.tinte)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        Button(stufe.titel) { Task { await modell.geheZu(tiefe: stufe.tiefe) } }
                            .font(.subheadline)
                            .frame(minHeight: Abstand.tippflaeche)
                    }
                }
            }
        }
    }

    @ViewBuilder private var inhalt: some View {
        switch modell.zustand {
        case .laedt:
            ProgressView("Lade …").frame(maxWidth: .infinity).padding(Abstand.xl)
        case .fehler(let text, let offline) where modell.eintraege.isEmpty:
            VStack(spacing: Abstand.m) {
                if offline { StatusChip(text: "Offline: Dateien gibt es nur, wenn der PC an ist", symbol: "wifi.slash", ton: .warn) }
                FehlerKarte(text: text) { Task { await modell.lade() } }
            }
        case .fehler(let text, let offline):
            StatusChip(text: offline ? "Offline: \(text)" : text, symbol: offline ? "wifi.slash" : "exclamationmark.triangle.fill", ton: .warn)
            liste
        case .bereit:
            if modell.eintraege.isEmpty { leer } else { liste }
        }
    }

    private var leer: some View {
        LeerZustand(
            titel: modell.ordner.isEmpty ? "Noch nichts da" : "Der Ordner ist leer",
            text: modell.ordner.isEmpty ? "Lege Dateien in den Ordner Heimherz/Dateien am PC, oder lade vom Handy etwas hoch." : "Hier liegt nichts. Lade vom Handy etwas hoch."
        )
    }

    private var liste: some View {
        ListenKarte {
            ForEach(Array(modell.eintraege.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(Color.haar) }
                Button { tippe(e) } label: { zeile(e) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("In den Papierkorb", systemImage: "trash", role: .destructive) { frageWeg = e }
                    }
            }
        }
    }

    private func zeile(_ e: DateiInfo) -> some View {
        HStack(spacing: Abstand.m) {
            Image(systemName: DateiAnzeige.symbol(name: e.name, ordner: e.ordner))
                .font(.title3)
                .foregroundStyle(e.ordner ? Color.knopf : Color.tinte2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.body).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                Text(DateiAnzeige.untertitel(e)).font(.footnote).foregroundStyle(Color.tinte2)
            }
            Spacer(minLength: 0)
            if e.ordner { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.tinte3).accessibilityHidden(true) }
        }
        .padding(.vertical, Abstand.s)
        .frame(minHeight: Abstand.tippflaeche)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(e.ordner ? "Öffnet den Ordner" : "Zeigt die Datei")
    }

    private func tippe(_ e: DateiInfo) {
        if e.ordner { Task { await modell.oeffne(e.name) } } else if !modell.istDemo { offen = e }
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
        for d in dateien { try? FileManager.default.removeItem(at: d.url.deletingLastPathComponent()) }
    }
}

/// Eine Datei: lädt sie in den Cache, dann ansehen, teilen oder in den Papierkorb.
private struct DateiBlatt: View {
    let datei: DateiInfo
    let modell: DateienModell
    let papierkorb: () -> Void

    @Environment(\.dismiss) private var schliesse
    @State private var geladen: URL?
    @State private var fehler: String?
    @State private var vorschau: URL?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Abstand.l) {
                ListenKarte {
                    HStack(spacing: Abstand.m) {
                        Image(systemName: DateiAnzeige.symbol(name: datei.name, ordner: false)).font(.largeTitle).foregroundStyle(Color.knopf).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Abstand.xs) {
                            Text(datei.name).font(.headline).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                            Text(DateiAnzeige.untertitel(datei)).font(.subheadline).foregroundStyle(Color.tinte2)
                        }
                    }
                }
                if let fehler {
                    FehlerKarte(text: fehler) { Task { await lade() } }
                } else if let geladen {
                    Button { vorschau = geladen } label: {
                        Label("Ansehen", systemImage: "eye").font(.headline).frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                    }
                    .buttonStyle(.glassProminent).tint(Color.knopf).foregroundStyle(Color.aufKnopf).controlSize(.large)
                    ShareLink(item: geladen) {
                        Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                    }
                    .buttonStyle(.glass)
                } else {
                    HStack(spacing: Abstand.s) {
                        ProgressView()
                        Text("Lade die Datei vom PC …").font(.subheadline).foregroundStyle(Color.tinte2)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) { papierkorb() } label: {
                    Label("In den Papierkorb am PC", systemImage: "trash").frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glass).tint(Color.schlecht)
            }
            .padding(Abstand.l)
            .heimherzHintergrund()
            .navigationTitle("Datei")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { schliesse() } }
            }
            .quickLookPreview($vorschau)
        }
        .presentationDetents([.medium, .large])
        .task { await lade() }
    }

    private func lade() async {
        fehler = nil
        do { geladen = try await modell.laden(datei) } catch {
            fehler = (error as? HeimFehler)?.nutzerText ?? "Die Datei konnte nicht geladen werden."
        }
    }
}
