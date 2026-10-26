import SwiftUI

// App-eigene Bausteine (brauchen das Haus-Zeichen von Lumen Cloud), bleiben deshalb außerhalb des Lumen-Kits.

/// Leerer Zustand: Lumen Cloud-Zeichen, ein Satz, optional eine Handlung. Lädt zur nächsten Handlung ein statt "Keine Daten".
struct LeerZustand: View {
    var stimmung: HausherzStimmung = .wach
    let titel: String
    let text: String
    var aktionTitel: String?
    var aktion: (() -> Void)?

    var body: some View {
        VStack(spacing: Abstand.m) {
            HausherzView(stimmung: stimmung, groesse: 112)
            Text(titel)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.tinte)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.tinte2)
                .multilineTextAlignment(.center)
            if let aktionTitel, let aktion {
                Button(aktionTitel, action: aktion)
                    .buttonStyle(.glassProminent)
                    .tint(Color.knopf)
                    .foregroundStyle(Color.aufKnopf)
                    .controlSize(.large)
                    .padding(.top, Abstand.xs)
            }
        }
        .padding(Abstand.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Fehlerkarte: Fehlerzeichen, ein verständlicher Satz, optional "Nochmal".
struct FehlerKarte: View {
    let text: String
    var wiederholen: (() -> Void)?

    var body: some View {
        ListenKarte {
            HStack(alignment: .top, spacing: Abstand.m) {
                HausherzView(stimmung: .sorry, groesse: 56)
                VStack(alignment: .leading, spacing: Abstand.s) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Color.tinte)
                        .fixedSize(horizontal: false, vertical: true)
                    if let wiederholen {
                        Button("Nochmal", action: wiederholen)
                            .buttonStyle(.glassProminent)
                            .tint(Color.knopf)
                            .foregroundStyle(Color.aufKnopf)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
