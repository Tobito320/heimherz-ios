import SwiftUI

/// Der Eintrag im Detail: Benutzer und Passwort kopieren (Zwischenablage 60 s, nur dieses Gerät), Passwort erst nach Face ID zeigen,
/// Einmalcode mit Ring und Restzeit. Der Eintrag wird bei jeder Änderung neu aus dem Store gelesen.
struct EintragDetailView: View {
    let store: TresorStore
    let id: String
    var bearbeiten: (Eintrag) -> Void

    @Environment(\.dismiss) private var schliessen
    @State private var zeigePasswort = false
    @State private var frageLoeschen = false
    @State private var kopiert: String?

    var body: some View {
        Group {
            if let e = store.eintrag(id) {
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
                if e.art == Eintrag.artLogin { zugang(e) }
                if !e.notiz.isEmpty { notiz(e) }
                Text("Geändert: \(Self.datum(e.geaendert))")
                    .font(.footnote)
                    .foregroundStyle(Color.tinte2)
            }
            .padding(.horizontal, Abstand.l)
            .padding(.bottom, Abstand.xl)
        }
        .toolbar {
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
                    Button(role: .destructive) { frageLoeschen = true } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                }
                .accessibilityLabel("Mehr")
            }
        }
        .confirmationDialog("Diesen Eintrag löschen?", isPresented: $frageLoeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task {
                    await store.loesche(id: e.id)
                    schliessen()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Er verschwindet auf allen deinen Geräten. Am PC bleibt er im Verlauf des Tresors.")
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
        HeroKarte {
            Text(e.name.isEmpty ? "Ohne Namen" : e.name)
                .font(.title.weight(.bold))
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
        .accessibilityElement(children: .combine)
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
            if let z = TOTPAnzeige.zustand(e.totp, datum: zeit.date) {
                HStack(spacing: Abstand.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Einmalcode").font(.footnote).foregroundStyle(Color.tinte2)
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
        .foregroundStyle(Color.gruen)
        .accessibilityLabel(beschriftung)
    }

    // MARK: Aktionen

    private func kopiere(_ text: String, _ was: String) {
        Zwischenablage.kopiere(text)
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

    private static func datum(_ iso: String) -> String {
        guard let ms = Zeit.millis(iso: iso) else { return "unbekannt" }
        return Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

/// Der Ring um die Restzeit des Einmalcodes. Wird es knapp (5 Sekunden), färbt er sich warm.
struct TOTPRing: View {
    let anteil: Double
    let rest: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.haar, lineWidth: 5)
            Circle()
                .trim(from: 0, to: anteil)
                .stroke(rest <= 5 ? Color.warn : Color.knopf, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(rest)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.tinte)
        }
        .frame(width: 44, height: 44)
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
