import SwiftUI

/// Platzhalter (T4): das Modul `ios-dateien` ersetzt den Inhalt dieser Datei und übernimmt den Ordner.
/// Einstieg: `@Environment(AppUmgebung.self)`, darüber `client()` und `tresorDienst()`.
struct DateienTabView: View {
    @Environment(AppUmgebung.self) private var umgebung

    var body: some View {
        NavigationStack {
            ScrollView {
                LeerZustand(
                    titel: "Dateien",
                    text: umgebung.istGekoppelt ? "Hier erscheinen die Dateien von deinem PC." : "Koppel zuerst dein Handy mit dem PC (Tab Mehr)."
                )
            }
            .navigationTitle("Dateien")
            .heimherzHintergrund()
        }
    }
}
