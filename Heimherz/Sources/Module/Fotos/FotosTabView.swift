import SwiftUI

/// Platzhalter (T4): das Modul `ios-fotos` ersetzt den Inhalt dieser Datei und übernimmt den Ordner.
/// Einstieg: `@Environment(AppUmgebung.self)`, darüber `client()` und `tresorDienst()`.
struct FotosTabView: View {
    @Environment(AppUmgebung.self) private var umgebung

    var body: some View {
        NavigationStack {
            ScrollView {
                LeerZustand(
                    titel: "Fotos",
                    text: umgebung.istGekoppelt ? "Hier siehst du, welche Fotos schon auf dem PC liegen." : "Koppel zuerst dein Handy mit dem PC (Tab Mehr)."
                )
            }
            .navigationTitle("Fotos")
            .heimherzHintergrund()
        }
    }
}
