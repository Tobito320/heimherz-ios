import SwiftUI

/// Passwort-Gesundheit (W-037): vier Gruppen (schwach, gleiches Passwort, alt, ohne 2FA), je mit den Einträgen. Tippen öffnet den Eintrag.
/// Alles wird hier im Speicher berechnet, nichts verlässt das Gerät.
struct GesundheitAnsicht: View {
    let store: TresorStore

    private var gesundheit: PasswortGesundheit { PasswortGesundheit.pruefe(store.eintraege) }

    var body: some View {
        let g = gesundheit
        List {
            if g.istLeer {
                Section { HinweisKarte(text: "Alles in Ordnung: keine schwachen, doppelten oder alten Passwörter, und überall ist 2FA hinterlegt.", symbol: "checkmark.shield") }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(GesundheitGruppe.allCases, id: \.self) { gruppe in
                let eintraege = g.ids(gruppe).compactMap { store.eintrag($0) }
                if !eintraege.isEmpty {
                    Section {
                        ForEach(eintraege) { e in
                            NavigationLink(value: PasswoerterZiel.eintrag(e.id)) { EintragZeile(eintrag: e) }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.haar)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("\(gruppe.titel) (\(eintraege.count))", systemImage: gruppe.symbol)
                                .font(.footnote.weight(.semibold))
                            Text(gruppe.erklaerung)
                                .font(.footnote)
                        }
                        .foregroundStyle(Color.tinte2)
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .heimherzHintergrund()
        .navigationTitle("Passwort-Gesundheit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

/// Die Zeile oben in "Sicherheit", die zur Passwort-Gesundheit führt, mit der Zahl betroffener Einträge.
struct GesundheitZeile: View {
    let gesundheit: PasswortGesundheit

    private var betroffen: Int { Set(GesundheitGruppe.allCases.flatMap { gesundheit.ids($0) }).count }

    var body: some View {
        HStack(spacing: Abstand.m) {
            Image(systemName: "heart.text.square")
                .font(.title3)
                .foregroundStyle(Color.akzent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Passwort-Gesundheit").font(.headline).foregroundStyle(Color.tinte)
                Text(betroffen == 0 ? "Alles in Ordnung" : (betroffen == 1 ? "1 Eintrag mit Hinweis" : "\(betroffen) Einträge mit Hinweis"))
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
            }
        }
        .frame(minHeight: Abstand.tippflaeche)
        .accessibilityElement(children: .combine)
    }
}
