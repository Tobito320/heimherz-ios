import SwiftUI

/// Wohin ein Tipp in der Passwörter-Navigation führt.
enum PasswoerterZiel: Hashable {
    case kategorie(PasswoerterKategorie)
    case eintrag(String)
}

/// Die Startseite des Tabs wie die Passwörter-App von Apple: große Kacheln mit Zahl, Suche über alles, Plus. Die Zahlen sind live aus dem Tresor.
struct PasswoerterStart: View {
    let store: TresorStore
    @Binding var suche: String
    var neu: (FormularZiel) -> Void
    var generator: () -> Void
    var anleitung: () -> Void

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
        .heimherzHintergrund()
        .searchable(text: $suche, prompt: "Suchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { mehrMenue }
            ToolbarItem(placement: .topBarTrailing) { neuMenue }
        }
        .refreshable { await store.abgleichen() }
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.l) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Abstand.m), GridItem(.flexible(), spacing: Abstand.m)], spacing: Abstand.m) {
                    ForEach(kacheln, id: \.self) { k in
                        NavigationLink(value: PasswoerterZiel.kategorie(k)) { KategorieKachel(kategorie: k, anzahl: zaehler[k] ?? 0) }
                            .buttonStyle(.plain)
                    }
                }
                Button(action: anleitung) {
                    HStack(spacing: Abstand.m) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                            .foregroundStyle(Color.gruen)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aus Apple Passwörter holen").font(.headline).foregroundStyle(Color.tinte)
                            Text("Alle Konten, Codes und Passkeys auf einmal").font(.subheadline).foregroundStyle(Color.tinte2)
                        }
                        Spacer(minLength: Abstand.s)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.tinte3).accessibilityHidden(true)
                    }
                    .padding(Abstand.m)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche, alignment: .leading)
                    .background(Color.karte, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                if store.eintraege.isEmpty {
                    LeerZustand(
                        titel: "Noch keine Einträge",
                        text: "Hol alles aus Apple Passwörter, importiere am PC mit `heimherz import bitwarden` oder lege hier ein neues Konto an.",
                        aktionTitel: "Neues Konto"
                    ) { neu(.neu(Eintrag.artLogin)) }
                }
                SyncStatus(store: store)
            }
            .padding(.horizontal, Abstand.l)
            .padding(.bottom, Abstand.xl)
        }
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
            Button(action: anleitung) { Label("Aus Apple Passwörter holen", systemImage: "square.and.arrow.down") }
            Button { Task { await store.abgleichen() } } label: { Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath") }
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
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(KachelFarbe.farbe(kategorie), in: Circle())
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
        .background(Color.karte, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kategorie.titel), \(anzahl)")
    }
}

/// Wann zuletzt mit dem PC abgeglichen wurde, und ob etwas klemmt.
struct SyncStatus: View {
    let store: TresorStore

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
