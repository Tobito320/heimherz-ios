import SwiftUI

/// Der Eintrag im Detail im Stil der Passwörter-App von Apple: Kopf mit Symbol und Name, Benutzer und Passwort kopieren (Zwischenablage 60 s, nur dieses Gerät),
/// Passwort erst nach Face ID zeigen, Einmalcode mit Ring und Restzeit (ebenfalls erst nach Face ID), "Frühere Passwörter (N)" als Unterseite, Passkeys.
/// Der Eintrag wird bei jeder Änderung neu aus dem Store gelesen. Ein gelöschter Eintrag ist nur lesbar und lässt sich wiederherstellen.
struct EintragDetailView: View {
    let store: TresorStore
    let id: String
    var bearbeiten: (Eintrag) -> Void

    @Environment(\.dismiss) private var schliessen
    @State private var zeigePasswort = false
    @State private var frageLoeschen = false
    @State private var frageEndgueltig = false
    @State private var kopiert: String?
    @State private var zeigeFruehere = false
    @Environment(\.openURL) private var oeffneURL

    var body: some View {
        Group {
            if let e = store.eintrag(id) ?? store.geloeschterEintrag(id) {
                inhalt(e)
            } else {
                ScrollView { LeerZustand(titel: "Eintrag nicht mehr da", text: "Er wurde gelöscht oder der Tresor ist gesperrt.") }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .heimherzHintergrund()
    }

    private func inhalt(_ e: Eintrag) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.l) {
                kopf(e)
                if e.geloescht { geloeschtHinweis }
                if let hinweis = sicherheit(e) { hinweisZeile(e, hinweis) }
                if e.art == Eintrag.artLogin { zugang(e) }
                if !e.notiz.isEmpty { notiz(e) }
                if !PasswoerterLogik.passkeys(von: e).isEmpty { passkeyKarte(e) }
                fruehereZeile(e)
                Text("Geändert: \(Self.datum(e.geaendert))")
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
            .padding(.horizontal, Abstand.l)
            .padding(.bottom, Abstand.xl)
        }
        .toolbar {
            if e.geloescht {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                await store.stelleWiederHer(ids: [e.id])
                                Haptik.erfolg()
                                schliessen()
                            }
                        } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                        Button(role: .destructive) { frageEndgueltig = true } label: { Label("Endgültig löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                    }
                    .accessibilityLabel("Mehr")
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Haptik.auswahl()
                        Task { await store.setzeFavorit(id: e.id, !e.favorit) }
                    } label: {
                        Image(systemName: e.favorit ? "star.fill" : "star")
                            .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                    }
                    .accessibilityLabel(e.favorit ? "Favorit entfernen" : "Als Favorit markieren")
                    Menu {
                        Button { bearbeiten(e) } label: { Label("Bearbeiten", systemImage: "pencil") }
                        if let url = PasswoerterLogik.passwortAendernURL(von: e) {
                            Button { oeffneURL(url) } label: { Label("Passwort ändern …", systemImage: "key.horizontal") }
                        }
                        Button(role: .destructive) { frageLoeschen = true } label: { Label("Löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                    }
                    .accessibilityLabel("Mehr")
                }
            }
        }
        .navigationDestination(isPresented: $zeigeFruehere) { FruehereSeite(store: store, id: e.id) }
        #if DEBUG
        .onAppear { if UserDefaults.standard.string(forKey: "heimherzPwOffen") == "frueher" { zeigeFruehere = true } }   // nur Screenshots in CI
        #endif
        .confirmationDialog("Diesen Eintrag löschen?", isPresented: $frageLoeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task {
                    await store.loesche(id: e.id)
                    schliessen()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Er bleibt 30 Tage in „Gelöscht“ und lässt sich zurückholen. Auf deinen Geräten verschwindet er aus der Liste.")
        }
        .confirmationDialog("Diesen Eintrag endgültig löschen?", isPresented: $frageEndgueltig, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                Task {
                    await store.loescheEndgueltig(ids: [e.id])
                    schliessen()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Passwörter, Codes und Notizen sind danach weg und lassen sich nicht zurückholen. Am PC bleibt eine alte Fassung im Verlauf des Tresors.")
        }
        .overlay(alignment: .bottom) {
            if let kopiert {
                StatusChip(text: "\(kopiert) kopiert, 60 Sekunden", symbol: "doc.on.doc.fill", ton: .ok)
                    .padding(.bottom, Abstand.l)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Feder.weich, value: kopiert)
    }

    // MARK: Teile

    private func kopf(_ e: Eintrag) -> some View {
        HStack(spacing: Abstand.l) {
            SymbolKachel(eintrag: e, groesse: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name.isEmpty ? "Ohne Namen" : e.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.tinte)
                    .fixedSize(horizontal: false, vertical: true)
                if e.art == Eintrag.artLogin, let host = EintragSuche.hosts(von: e).first {
                    Text(host)
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                } else if e.art == Eintrag.artNotiz {
                    Text("Notiz").font(.subheadline).foregroundStyle(Color.tinte2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Abstand.s)
        .accessibilityElement(children: .combine)
    }

    private var geloeschtHinweis: some View {
        HinweisKarte(text: "Dieser Eintrag ist gelöscht. Er bleibt 30 Tage hier, dann werden seine Inhalte gelöscht. Oben rechts kannst du ihn wiederherstellen.", symbol: "trash")
    }

    /// Der Sicherheitshinweis zu diesem Eintrag (Datenleck, gleiches Passwort in mehreren Konten, leicht zu erraten), lokal berechnet.
    private func sicherheit(_ e: Eintrag) -> SicherheitsHinweis? {
        guard !e.geloescht else { return nil }
        return PasswortSicherheit.pruefe(store.eintraege, lecks: store.leckIds).first { $0.eintragId == e.id }
    }

    /// Hinweis mit dem Knopf dazu: wer ein schwaches oder geleaktes Passwort sieht, will es gleich ändern.
    private func hinweisZeile(_ e: Eintrag, _ h: SicherheitsHinweis) -> some View {
        VStack(alignment: .leading, spacing: Abstand.xs) {
            StatusChip(text: h.text, symbol: "exclamationmark.triangle.fill", ton: h.gruende.first == .datenleck ? .schlecht : .warn)
            if let url = PasswoerterLogik.passwortAendernURL(von: e) {
                Button("Passwort ändern …") { oeffneURL(url) }
                    .font(.subheadline)
                    .foregroundStyle(Color.akzent)
                    .frame(minHeight: Abstand.tippflaeche, alignment: .leading)
            }
        }
    }

    private func passkeyKarte(_ e: Eintrag) -> some View {
        ListenKarte {
            Text("Passkeys").font(.footnote).foregroundStyle(Color.tinte2)
            ForEach(Array(PasswoerterLogik.passkeys(von: e).enumerated()), id: \.offset) { _, p in
                Text([p.seite, p.konto].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(Color.tinte)
                    .frame(minHeight: Abstand.tippflaeche, alignment: .leading)
            }
            Text("Gesichert im Tresor. Haven meldet dich damit an.")
                .font(.footnote)
                .foregroundStyle(Color.tinte2)
        }
    }

    /// Eine Zeile "Frühere Passwörter (N)" mit Unterseite, nur wenn es welche gibt. Anzeigen und Kopieren dort erst nach Face ID.
    @ViewBuilder
    private func fruehereZeile(_ e: Eintrag) -> some View {
        let n = PasswoerterLogik.fruehere(von: e).count
        if n > 0 {
            Button { zeigeFruehere = true } label: {
                ListenKarte {
                    HStack {
                        Text("Frühere Passwörter (\(n))").font(.body).foregroundStyle(Color.tinte)
                        Spacer(minLength: Abstand.s)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.tinte3).accessibilityHidden(true)
                    }
                    .frame(minHeight: Abstand.tippflaeche)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func zugang(_ e: Eintrag) -> some View {
        ListenKarte {
            if !e.benutzer.isEmpty {
                zeile("Benutzer", wert: e.benutzer) {
                    knopf("doc.on.doc", "Benutzer kopieren") { kopiere(e.benutzer, "Benutzer") }
                }
                trenner
            }
            if !e.passwort.isEmpty {
                zeile("Passwort", wert: zeigePasswort ? e.passwort : String(repeating: "•", count: 10), monospace: zeigePasswort, auswaehlbar: false) {
                    HStack(spacing: 0) {
                        knopf(zeigePasswort ? "eye.slash" : "eye", zeigePasswort ? "Passwort verbergen" : "Passwort zeigen") { passwortUmschalten() }
                        knopf("doc.on.doc", "Passwort kopieren") { kopiere(e.passwort, "Passwort") }
                    }
                }
            }
            if !e.totp.isEmpty {
                trenner
                totpZeile(e)
            }
            let webseiten = e.urls.filter { !$0.isEmpty }
            if !webseiten.isEmpty {
                trenner
                VStack(alignment: .leading, spacing: Abstand.xs) {
                    Text(webseiten.count == 1 ? "Webseite" : "Webseiten").font(.footnote).foregroundStyle(Color.tinte2)
                    ForEach(webseiten, id: \.self) { u in
                        if let url = Self.sichereURL(u) {
                            Link(u, destination: url)
                                .font(.body)
                                .frame(minHeight: Abstand.tippflaeche, alignment: .leading)
                        } else {
                            Text(u).font(.body).foregroundStyle(Color.tinte)
                        }
                    }
                }
            }
        }
        .task(id: zeigePasswort) {
            guard zeigePasswort else { return }
            try? await Task.sleep(for: .seconds(30))
            zeigePasswort = false
        }
    }

    private func totpZeile(_ e: Eintrag) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { zeit in
            if !store.codesFreigegeben {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bestätigungscode").font(.footnote).foregroundStyle(Color.tinte2)
                        Text("••• •••").font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(Color.tinte3)
                    }
                    Spacer(minLength: Abstand.s)
                    Button {
                        Task { if await GeraeteAbfrage.pruefe(grund: "Einmalcodes anzeigen") { store.gebeCodesFrei() } }
                    } label: {
                        Label("Anzeigen", systemImage: "faceid").frame(minHeight: Abstand.tippflaeche)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.akzent)
                    .accessibilityLabel("Einmalcode mit Face ID anzeigen")
                }
            } else if let z = TOTPAnzeige.zustand(e.totp, datum: zeit.date) {
                HStack(spacing: Abstand.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bestätigungscode").font(.footnote).foregroundStyle(Color.tinte2)
                        Text(z.gruppiert)
                            .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.tinte)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Abstand.s)
                    TOTPRing(anteil: z.anteil, rest: z.rest)
                    knopf("doc.on.doc", "Einmalcode kopieren") { kopiere(z.code, "Einmalcode") }
                }
                .accessibilityElement(children: .contain)
            } else {
                Text("Der Einmalcode dieses Eintrags ist nicht lesbar.")
                    .font(.footnote)
                    .foregroundStyle(Color.schlecht)
            }
        }
    }

    private func notiz(_ e: Eintrag) -> some View {
        ListenKarte {
            Text("Notiz").font(.footnote).foregroundStyle(Color.tinte2)
            Text(e.notiz)
                .font(.body)
                .foregroundStyle(Color.tinte)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trenner: some View {
        Rectangle().fill(Color.haar).frame(height: 1).padding(.vertical, Abstand.s).accessibilityHidden(true)
    }

    /// `auswaehlbar` false beim Passwort: kopiert wird nur über den eigenen Knopf (lokal, mit Ablauf), nie über das Auswahlmenü des Systems.
    private func zeile<Aktionen: View>(_ titel: String, wert: String, monospace: Bool = false, auswaehlbar: Bool = true, @ViewBuilder aktionen: () -> Aktionen) -> some View {
        HStack(spacing: Abstand.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titel).font(.footnote).foregroundStyle(Color.tinte2)
                Text(wert)
                    .font(monospace ? .system(.body, design: .monospaced) : .body)
                    .foregroundStyle(Color.tinte)
                    .auswaehlbar(auswaehlbar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Abstand.s)
            aktionen()
        }
    }

    private func knopf(_ symbol: String, _ beschriftung: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.akzent)
        .accessibilityLabel(beschriftung)
    }

    // MARK: Aktionen

    private func kopiere(_ text: String, _ was: String) {
        Zwischenablage.kopiere(text)
        Nutzung().merke(id: id)
        Haptik.erfolg()
        kopiert = was
        Task {
            try? await Task.sleep(for: .seconds(2))
            if kopiert == was { kopiert = nil }
        }
    }

    private func passwortUmschalten() {
        if zeigePasswort {
            zeigePasswort = false
            return
        }
        Task {
            if await GeraeteAbfrage.pruefe(grund: "Passwort anzeigen") { zeigePasswort = true }
        }
    }

    /// Nur http(s) wird geöffnet; alles andere (z. B. `javascript:`, App-Schemata) bleibt reiner Text.
    static func sichereURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mitSchema = t.contains("://") ? t : "https://" + t
        guard let url = URL(string: mitSchema), let schema = url.scheme?.lowercased(), schema == "https" || schema == "http", url.host != nil else { return nil }
        return url
    }

    static func datum(_ iso: String) -> String {
        guard let ms = Zeit.millis(iso: iso) else { return "unbekannt" }
        return Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

/// Der Ring um die Restzeit des Einmalcodes. Wird es knapp (5 Sekunden), färbt er sich warm.
struct TOTPRing: View {
    let anteil: Double
    let rest: Int
    var groesse: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().stroke(Color.haar, lineWidth: groesse > 36 ? 5 : 4)
            Circle()
                .trim(from: 0, to: anteil)
                .stroke(rest <= 5 ? Color.warn : Color.knopf, style: StrokeStyle(lineWidth: groesse > 36 ? 5 : 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(rest)")
                .font(groesse > 36 ? .footnote.monospacedDigit().weight(.semibold) : .caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.tinte)
        }
        .frame(width: groesse, height: groesse)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noch \(rest) Sekunden gültig")
    }
}

private extension View {
    /// `textSelection` hat je Wert einen anderen Typ, darum zwei Zweige.
    @ViewBuilder
    func auswaehlbar(_ an: Bool) -> some View {
        if an { textSelection(.enabled) } else { textSelection(.disabled) }
    }
}
