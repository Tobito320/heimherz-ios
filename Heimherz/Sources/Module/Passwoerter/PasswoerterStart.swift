import SwiftUI

/// Wohin ein Tipp in der Passwörter-Navigation führt.
enum PasswoerterZiel: Hashable {
    case kategorie(PasswoerterKategorie)
    case eintrag(String)
    case gesundheit
}

/// Die Startseite des Tabs wie die Passwörter-App von Apple: große Kacheln mit Zahl, Suche über alles, Plus. Die Zahlen sind live aus dem Tresor.
struct PasswoerterStart: View {
    let store: TresorStore
    @Binding var suche: String
    var zoom: Namespace.ID
    var neu: (FormularZiel) -> Void
    var generator: () -> Void
    var anleitung: () -> Void

    @State private var versatz: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var zaehler: [PasswoerterKategorie: Int] { store.zaehler }

    private var kacheln: [PasswoerterKategorie] {
        PasswoerterKategorie.allCases.filter { $0 != .favoriten || (zaehler[.favoriten] ?? 0) > 0 }
    }

    private var suchtext: String { suche.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var treffer: [Eintrag] { EintragSuche.filtern(EintragSuche.sortiert(store.eintraege), begriff: suchtext) }

    var body: some View {
        Group {
            if suchtext.isEmpty { start } else { ergebnisse }
        }
        .heimherzHintergrund(versatz: versatz)
        .searchable(text: $suche, prompt: "Suchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { mehrMenue }
            ToolbarItem(placement: .topBarTrailing) { neuMenue }
        }
        .refreshable {
            Haptik.auswahl()
            await store.abgleichen()
        }
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.l) {
                hero
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Abstand.m), GridItem(.flexible(), spacing: Abstand.m)], spacing: Abstand.m) {
                    ForEach(Array(kacheln.enumerated()), id: \.element) { item in
                        let k = item.element
                        NavigationLink(value: PasswoerterZiel.kategorie(k)) { KategorieKachel(kategorie: k, anzahl: zaehler[k] ?? 0) }
                            .buttonStyle(.federnd)
                            .zoomQuelle(k, in: zoom)
                            .aufbau(item.offset + 2)
                    }
                }
                if store.eintraege.isEmpty {
                    LeerZustand(
                        titel: "Noch keine Einträge",
                        text: "Lege ein Konto an oder hol sie über das Menü oben aus Apple Passwörter.",
                        aktionTitel: "Neues Konto"
                    ) { neu(.neu(Eintrag.artLogin)) }
                }
                if store.abgleichFehler != nil || store.offlineText != nil || store.gleichtAb { SyncStatus(store: store) }
            }
            .padding(.horizontal, Abstand.l)
            .padding(.bottom, Abstand.xl)
        }
        .scrollVersatz($versatz)
    }

    // MARK: Hero

    /// Revolut-Kopf: große Zahl (zählt hoch), graue Pille, vier runde Schnellaktionen.
    private var hero: some View {
        VStack(spacing: Abstand.m) {
            VStack(spacing: Abstand.s) {
                ZaehltHoch(wert: store.eintraege.count)
                    .foregroundStyle(Color.tinte)
                InfoPille(text: "Einträge im Tresor", symbol: "lock.fill")
            }
            .frame(maxWidth: .infinity)
            .schrumpftBeimScrollen(versatz, reduceMotion: reduceMotion)
            .aufbau(0)
            HStack(alignment: .top, spacing: Abstand.s) {
                RundeAktion(titel: "Neu", symbol: "plus") { Haptik.auswahl(); neu(.neu(Eintrag.artLogin)) }
                RundeAktion(titel: "Notiz", symbol: "note.text") { Haptik.auswahl(); neu(.neu(Eintrag.artNotiz)) }
                RundeAktion(titel: "Generator", symbol: "wand.and.stars") { Haptik.auswahl(); generator() }
                RundeAktion(titel: "Holen", symbol: "square.and.arrow.down") { Haptik.auswahl(); anleitung() }
            }
            .aufbau(1)
        }
        .padding(.top, Abstand.s)
    }

    // MARK: Suche

    @ViewBuilder
    private var ergebnisse: some View {
        if treffer.isEmpty {
            Text("Nichts gefunden für „\(suchtext)“.")
                .font(.body)
                .foregroundStyle(Color.tinte2)
                .padding(Abstand.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            let hinweise = Set(PasswortSicherheit.pruefe(store.eintraege).map(\.eintragId))
            List {
                ForEach(treffer) { e in
                    NavigationLink(value: PasswoerterZiel.eintrag(e.id)) { EintragZeile(eintrag: e, hinweis: hinweise.contains(e.id)) }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.haar)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Menüs

    private var neuMenue: some View {
        Menu {
            Button { neu(.neu(Eintrag.artLogin)) } label: { Label("Neues Konto", systemImage: "person.badge.key") }
            Button { neu(.neu(Eintrag.artNotiz)) } label: { Label("Neue Notiz", systemImage: "note.text") }
            Button(action: generator) { Label("Passwort-Generator", systemImage: "wand.and.stars") }
        } label: {
            Image(systemName: "plus")
                .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
        }
        .accessibilityLabel("Neu")
    }

    private var mehrMenue: some View {
        Menu {
            Section(SyncStatus.zuletztText(store.zuletzt)) {
                Button(action: anleitung) { Label("Aus Apple Passwörter holen", systemImage: "square.and.arrow.down") }
                Button { Task { await store.abgleichen() } } label: { Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
        }
        .accessibilityLabel("Mehr")
    }
}

/// Eine Kachel: farbiges Symbol links oben, Zahl rechts oben, Name unten.
struct KategorieKachel: View {
    let kategorie: PasswoerterKategorie
    let anzahl: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.s) {
            HStack(alignment: .top) {
                Image(systemName: kategorie.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.tinte)
                    .frame(width: 40, height: 40)
                    .background(Color.chip, in: Circle())
                    .accessibilityHidden(true)
                Spacer(minLength: Abstand.s)
                Text("\(anzahl)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.tinte2)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(kategorie.titel)
                .font(.headline)
                .foregroundStyle(Color.tinte)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(Abstand.m)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(Color.karte, in: .heimherzKarte)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kategorie.titel), \(anzahl)")
    }
}

/// Nur was klemmt: Fehler, PC nicht erreichbar, läuft gerade. Das "Zuletzt abgeglichen" steht im Menü (drei Punkte).
struct SyncStatus: View {
    let store: TresorStore

    /// "Zuletzt abgeglichen: vor 5 Minuten" (Kopf des Menüs), nie leer.
    static func zuletztText(_ zuletzt: Date?) -> String {
        guard let zuletzt else { return "Noch nicht abgeglichen" }
        return "Zuletzt abgeglichen: \(zuletzt.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "de_DE"))))"
    }

    var body: some View {
        if let fehler = store.abgleichFehler {
            StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn)
        } else if store.offlineText != nil {
            StatusChip(text: "PC nicht erreichbar, alles geht weiter", symbol: "icloud.slash", ton: .neutral)
        } else if store.gleichtAb {
            StatusChip(text: "Gleiche ab …", symbol: "arrow.triangle.2.circlepath", ton: .neutral)
        }
    }
}
