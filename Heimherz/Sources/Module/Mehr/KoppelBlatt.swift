import SwiftUI
import UIKit

/// Das Blatt zum Koppeln: QR vom PC scannen (`heimherz koppeln` am PC) oder den Link einfügen.
struct KoppelBlatt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.dismiss) private var schliessen
    @State private var link = ""
    @State private var fehler: String?
    @State private var laeuft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    Text("Am PC `heimherz koppeln` aufrufen. Dort erscheint ein QR-Code, den du hier scannst. Er enthält Adresse, Geräte-Token und Schlüssel und gilt nur für dieses Handy.")
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                    scanner
                    if let fehler { FehlerKarte(text: fehler) }
                    einfuegen
                }
                .padding(Abstand.l)
            }
            .heimherzHintergrund()
            .navigationTitle("Mit PC koppeln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } }
            }
        }
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private var scanner: some View {
        if QRScanner.istMoeglich {
            QRScanner { text in
                Task { await koppeln(text) }
            }
            .frame(height: 300)
            .clipShape(.heimherzKarte)
            .overlay { RoundedRectangle(cornerRadius: Rundung.karte, style: .continuous).stroke(Color.linie, lineWidth: 1) }
            .accessibilityLabel("Kamera zum Scannen des QR-Codes")
        } else {
            ListenKarte {
                Label("Die Kamera steht hier nicht zur Verfügung. Füge den Link vom PC unten ein.", systemImage: "camera.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
            }
        }
    }

    private var einfuegen: some View {
        VStack(alignment: .leading, spacing: Abstand.s) {
            Text("Oder Link einfügen")
                .font(.headline)
                .foregroundStyle(Color.tinte)
            TextField("heimherz://koppeln?…", text: $link, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(Abstand.m)
                .frame(minHeight: Abstand.tippflaeche)
                .background(Color.karte, in: .heimherzFeld)
            HStack(spacing: Abstand.m) {
                Button {
                    if let text = UIPasteboard.general.string { link = text }
                } label: {
                    Label("Einfügen", systemImage: "doc.on.clipboard")
                        .frame(minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glass)
                Button {
                    Task { await koppeln(link) }
                } label: {
                    Label(laeuft ? "Verbinde …" : "Koppeln", systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.knopf)
                .foregroundStyle(Color.aufKnopf)
                .disabled(laeuft || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func koppeln(_ text: String) async {
        guard !laeuft else { return }
        laeuft = true
        fehler = nil
        defer { laeuft = false }
        do {
            try await umgebung.koppeln(link: text)
            Haptik.erfolg()
            schliessen()
        } catch let e as LocalizedError {
            fehler = e.errorDescription
            Haptik.fehler()
        } catch {
            fehler = HeimFehler.nichtErreichbar.nutzerText
            Haptik.fehler()
        }
    }
}
