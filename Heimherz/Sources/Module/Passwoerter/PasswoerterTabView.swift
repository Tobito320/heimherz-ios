import SwiftUI

/// Platzhalter (T4): das Modul `ios-passwoerter` ersetzt den Inhalt dieser Datei und übernimmt den Ordner.
/// Einstieg: `@Environment(AppUmgebung.self)`, darüber `client()` und `tresorDienst()`.
struct PasswoerterTabView: View {
    @Environment(AppUmgebung.self) private var umgebung

    var body: some View {
        NavigationStack {
            ScrollView {
                LeerZustand(
                    titel: "Passwörter",
                    text: umgebung.istGekoppelt ? "Hier erscheint dein Tresor, sobald das Handy mit dem PC gekoppelt ist." : "Koppel zuerst dein Handy mit dem PC (Tab Mehr)."
                )
            }
            .navigationTitle("Passwörter")
            .heimherzHintergrund()
        }
    }
}
