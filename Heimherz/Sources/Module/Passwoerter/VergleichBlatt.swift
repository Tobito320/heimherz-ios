import SwiftUI

/// Vergleich doppelter Konten (gleicher Host, gleicher Benutzer): die Einträge untereinander mit dem, was sich unterscheidet.
/// Heim führt nie zusammen. Löschen geht nur einzeln, mit Rückfrage, als Grabstein in "Gelöscht" (30 Tage wiederherstellbar).
/// Passwörter stehen hier nicht, nur ob sie gleich sind. Der Eintrag wird live aus dem Store gelesen; bleibt nur einer übrig, schließt das Blatt.
struct VergleichBlatt: View {
    let store: TresorStore
    let gruppe: DoppelteGruppe

    @Environment(\.dismiss) private var schliessen
    @State private var frage: String?

    private var eintraege: [Eintrag] { gruppe.ids.compactMap { store.eintrag($0) } }

    private var gleichesPasswort: Bool {
        Set(eintraege.map(\.passwort)).count == 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    StatusChip(text: gleichesPasswort ? "Gleiches Passwort" : "Unterschiedliche Passwörter",
                               symbol: gleichesPasswort ? "equal.circle.fill" : "exclamationmark.circle.fill",
                               ton: gleichesPasswort ? .neutral : .warn)
                    ForEach(eintraege) { e in karte(e) }
                }
                .padding(.horizontal, Abstand.l)
                .padding(.bottom, Abstand.xl)
            }
            .navigationTitle("Doppelte Konten")
            .navigationBarTitleDisplayMode(.inline)
            .lumenHintergrund()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } }
            }
        }
        .confirmationDialog(titel(frage), isPresented: Binding(get: { frage != nil }, set: { if !$0 { frage = nil } }), titleVisibility: .visible, presenting: frage) { id in
            Button("Löschen", role: .destructive) {
                Task {
                    await store.loesche(id: id)
                    Haptik.erfolg()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Er bleibt 30 Tage in „Gelöscht“ und lässt sich zurückholen. Der andere Eintrag bleibt, wie er ist.")
        }
        .onChange(of: eintraege.count) { _, n in if n < 2 { schliessen() } }
    }

    private func titel(_ id: String?) -> String {
        guard let id, let e = store.eintrag(id) else { return "Diesen Eintrag löschen?" }
        return "„\(e.name.isEmpty ? "Ohne Namen" : e.name)“ löschen?"
    }

    private func karte(_ e: Eintrag) -> some View {
        ListenKarte {
            HStack(spacing: Abstand.m) {
                SymbolKachel(eintrag: e)
                Text(e.name.isEmpty ? "Ohne Namen" : e.name)
                    .font(.headline)
                    .foregroundStyle(Color.tinte)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.bottom, Abstand.xs)
            WertZeile(name: "Benutzer", wert: e.benutzer)
            WertZeile(name: "Webseite", wert: EintragSuche.hosts(von: e).joined(separator: "\n"))
            WertZeile(name: "Einmalcode", wert: e.totp.isEmpty ? "Nein" : "Ja")
            WertZeile(name: "Notiz", wert: e.notiz.isEmpty ? "Nein" : "Ja")
            WertZeile(name: "Geändert", wert: Self.datum(e.geaendert))
            Button(role: .destructive) { frage = e.id } label: {
                Text("Löschen …").frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.schlecht)
        }
        .accessibilityElement(children: .contain)
    }

    private static func datum(_ iso: String) -> String {
        guard let ms = Zeit.millis(iso: iso) else { return "unbekannt" }
        return Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .omitted)
    }
}
