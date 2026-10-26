import SwiftUI
import UIKit

/// Unterseite "AutoFill einschalten": die vier Schritte in iOS und ein Knopf zu den Einstellungen.
struct AutoFillAnleitung: View {
    @Environment(\.openURL) private var oeffne

    private let schritte = [
        "Einstellungen öffnen",
        "Allgemein, dann AutoFill & Passwörter",
        "Unter „Ausfüllen von“ Lumen einschalten",
        "Erst wenn alles sicher läuft: iCloud-Passwörter ausschalten"
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(schritte.enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .firstTextBaseline, spacing: Abstand.m) {
                        Text("\(i + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.akzent)
                            .frame(width: 26, height: 26)
                            .background(Color.chip, in: Circle())
                            .accessibilityHidden(true)
                        Text(text).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Schritt \(i + 1): \(text)")
                    .heimherzZeile()
                }
            } header: {
                GruppenText(text: "Damit füllt iOS Passwörter und Einmalcodes aus Lumen aus, in Safari und in Apps.", fuss: true)
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { oeffne(url) }
                } label: {
                    KachelTitel(titel: "iOS-Einstellungen öffnen", symbol: "gearshape.fill", ton: .grau)
                }
                .heimherzZeile()
            }
        }
        .heimherzEinstellungenListe()
        .navigationTitle("AutoFill")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Unterseite "Neue 2FA-Codes in Lumen" (W-028). Belegt ist nur der Weg über den Link und den QR-Code in der App;
/// ob iOS Lumen unter „Codes konfigurieren in“ anbietet, zeigt erst das Handy (SPEC 9), darum steht es hier als „sollte“.
struct CodesAnleitung: View {
    @Environment(\.openURL) private var oeffne
    @State private var zeigeScanner = false

    private let schritte = [
        "Einstellungen öffnen",
        "Allgemein, dann AutoFill & Passwörter",
        "Ganz unten bei „Codes konfigurieren in“ Lumen wählen"
    ]

    var body: some View {
        List {
            Section {
                if QRScanner.istMoeglich {
                    Button { zeigeScanner = true } label: {
                        KachelTitel(titel: "QR-Code scannen", symbol: "qrcode.viewfinder", ton: .gelb)
                    }
                    .heimherzZeile()
                }
                Text("Tippst du auf der Seite auf den Link zum Einrichten oder öffnest ihn aus einer Mail, nimmt Lumen den Code an. Oder scanne den QR-Code hier.")
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
                    .fixedSize(horizontal: false, vertical: true)
                    .heimherzZeile()
            } header: {
                GruppenText(text: "Das geht immer")
            }
            Section {
                ForEach(Array(schritte.enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .firstTextBaseline, spacing: Abstand.m) {
                        Text("\(i + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.akzent)
                            .frame(width: 26, height: 26)
                            .background(Color.chip, in: Circle())
                            .accessibilityHidden(true)
                        Text(text).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Schritt \(i + 1): \(text)")
                    .heimherzZeile()
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { oeffne(url) }
                } label: {
                    KachelTitel(titel: "iOS-Einstellungen öffnen", symbol: "gearshape.fill", ton: .grau)
                }
                .heimherzZeile()
            } header: {
                GruppenText(text: "Direkt von iOS")
            } footer: {
                GruppenText(text: "Dann sollen Links und QR-Codes zum Einrichten gleich in Lumen landen statt im Authenticator. Ob iOS Lumen dort anbietet, zeigt erst dein Handy.", fuss: true)
            }
        }
        .heimherzEinstellungenListe()
        .navigationTitle("Neue 2FA-Codes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $zeigeScanner) { CodeScanBlatt { CodePostfach.geteilt.empfange(text: $0) } }
    }
}

/// Unterseite "Wie das Sichern läuft": die Regeln von iOS in kurzen Abschnitten (stand vorher als Textblock im Fotos-Tab).
struct SichernErklaerung: View {
    private let punkte: [(titel: String, text: String)] = [
        ("Start", "Mit „Abgleich starten“ geht es in kleinen Stücken los: erst alle Fotos, dann die Videos, jeweils die neuesten zuerst. Was lokal auf dem Handy liegt, kommt vor den iCloud-Originalen."),
        ("Anhalten", "Stoppt sofort. Was schon am PC liegt, zählt; die Datei dazwischen wird verworfen und beim nächsten Start neu gesendet."),
        ("App geschlossen", "Schließt du die App oder sperrst das Handy, macht iOS mit einer Anzeige weiter, solange es das zulässt. Wischst du Lumen im App-Umschalter weg, endet der Abgleich, bis du ihn wieder startest."),
        ("Nachts", "Am Ladegerät im WLAN setzt iOS den Abgleich fort, wenn du ihn nicht angehalten hast. Wann, entscheidet iOS."),
        ("Im Hintergrund hochladen", "iOS lädt dann auch bei geschlossener App hoch, wenn es ihm passt. „Anhalten“ hält das nicht auf: Dafür schaltest du es aus."),
        ("Originale aus iCloud", "Mit „iPhone-Speicher optimieren“ liegen viele Originale nur in iCloud. iOS muss sie erst laden, das dauert und braucht Platz und Netz. Aus: Solche Dateien werden übersprungen und bleiben offen."),
        ("Voraussetzung", "Der PC muss an sein und Tailscale laufen. Am Handy wird nie etwas gelöscht oder geändert.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(punkte.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.titel).font(.headline).foregroundStyle(Color.tinte)
                        Text(p.text).font(.subheadline).foregroundStyle(Color.tinte2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Abstand.xs)
                    .accessibilityElement(children: .combine)
                    .heimherzZeile()
                }
            }
        }
        .heimherzEinstellungenListe()
        .navigationTitle("Wie das Sichern läuft")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Dieselbe Erklärung als Blatt, aus dem Menü im Fotos-Tab.
struct SichernErklaerungBlatt: View {
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            SichernErklaerung()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
        }
        .fontDesign(.rounded)
        .presentationDetents([.medium, .large])
    }
}
