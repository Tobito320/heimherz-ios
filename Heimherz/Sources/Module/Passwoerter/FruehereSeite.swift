import SwiftUI

/// Unterseite "Frühere Passwörter" eines Eintrags (aus `passwortVerlauf` und `bitwardenVerlauf`, neueste zuerst).
/// Anzeigen und Kopieren gehen nur nach Face ID (oder Gerätecode); die Anzeige schließt sich nach 30 Sekunden und beim Verlassen der Seite.
struct FruehereSeite: View {
    let store: TresorStore
    let id: String

    @State private var zeigen = false
    @State private var kopiert = false

    private var zeilen: [PasswoerterLogik.FruehereZeile] {
        (store.eintrag(id) ?? store.geloeschterEintrag(id)).map(PasswoerterLogik.fruehere(von:)) ?? []
    }

    var body: some View {
        ScrollView {
            ListenKarte {
                ForEach(Array(zeilen.enumerated()), id: \.offset) { i, z in
                    if i > 0 { Rectangle().fill(Color.haar).frame(height: 1).padding(.vertical, Abstand.s).accessibilityHidden(true) }
                    zeile(z)
                }
            }
            .padding(.horizontal, Abstand.l)
        }
        .navigationTitle("Frühere Passwörter")
        .navigationBarTitleDisplayMode(.inline)
        .heimherzHintergrund()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if zeigen { zeigen = false } else { Task { if await GeraeteAbfrage.pruefe(grund: "Frühere Passwörter anzeigen") { zeigen = true } } }
                } label: {
                    Image(systemName: zeigen ? "eye.slash" : "eye").frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
                }
                .accessibilityLabel(zeigen ? "Passwörter verbergen" : "Passwörter zeigen")
            }
        }
        .task(id: zeigen) {
            guard zeigen else { return }
            try? await Task.sleep(for: .seconds(30))
            zeigen = false
        }
        .onDisappear { zeigen = false }
        .overlay(alignment: .bottom) {
            if kopiert {
                StatusChip(text: "Passwort kopiert, 60 Sekunden", symbol: "doc.on.doc.fill", ton: .ok)
                    .padding(.bottom, Abstand.l)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Feder.weich, value: kopiert)
    }

    private func zeile(_ z: PasswoerterLogik.FruehereZeile) -> some View {
        HStack(spacing: Abstand.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zeigen ? z.passwort : String(repeating: "•", count: 10))
                    .font(zeigen ? .system(.body, design: .monospaced) : .body)
                    .foregroundStyle(Color.tinte)
                    .textSelection(.disabled)
                if let ms = Zeit.millis(iso: z.bis) {
                    Text("Bis \(Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(Color.tinte2)
                }
            }
            Spacer(minLength: Abstand.s)
            Button { kopiere(z.passwort) } label: {
                Image(systemName: "doc.on.doc").frame(minWidth: Abstand.tippflaeche, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.gruen)
            .accessibilityLabel("Früheres Passwort kopieren")
        }
        .accessibilityElement(children: .contain)
    }

    private func kopiere(_ text: String) {
        Task {
            if !zeigen {
                let frei = await GeraeteAbfrage.pruefe(grund: "Früheres Passwort kopieren")
                guard frei else { return }
            }
            Zwischenablage.kopiere(text)
            Nutzung().merke(id: id)
            Haptik.erfolg()
            kopiert = true
            try? await Task.sleep(for: .seconds(2))
            kopiert = false
        }
    }
}
