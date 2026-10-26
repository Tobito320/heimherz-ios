import SwiftUI
import UIKit

/// Das Blatt zum Koppeln: QR vom PC scannen (`heimherz koppeln` am PC) oder den Link einfügen.
struct KoppelBlatt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.dismiss) private var schliessen
    @State private var link = ""
    @State private var fehler: String?
    @State private var laeuft = false
    /// Der Link-Weg ist zugeklappt, solange die Kamera geht; ohne Kamera liegt er offen.
    @State private var linkOffen = false
    /// Ein gültiger Link, der auf die Bestätigung wartet.
    @State private var ausstehend: Ausstehend?

    private struct Ausstehend: Equatable {
        let text: String
        let host: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    Text("Starte am PC `heimherz koppeln` und scanne den QR-Code.")
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
        .confirmationDialog(ausstehend.map { "Mit \($0.host) koppeln?" } ?? "Koppeln?", isPresented: bestaetigung, titleVisibility: .visible) {
            if let a = ausstehend {
                Button(umgebung.istGekoppelt ? "Ersetzen und koppeln" : "Koppeln", role: umgebung.istGekoppelt ? .destructive : nil) { Task { await koppeln(a.text) } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(bestaetigungsText)
        }
    }

    private var bestaetigung: Binding<Bool> {
        Binding(get: { ausstehend != nil }, set: { if !$0 { ausstehend = nil } })
    }

    private var bestaetigungsText: String {
        let frage = "Der Code enthält den Schlüssel zu allen deinen Passwörtern. Koppel nur mit einem Code, den dein eigener PC gezeigt hat."
        guard let alt = umgebung.geraet else { return frage }
        return "Dieses Handy ist schon mit \(alt.url.host ?? "einem PC") gekoppelt. Der alte Zugang, der Schlüssel und der Tresor auf diesem Handy werden ersetzt; vorher gleicht Lumen noch einmal ab. \(frage)"
    }

    /// Prüft den Text und fragt nach, bevor irgendetwas gespeichert wird.
    private func pruefe(_ text: String) {
        guard !laeuft, ausstehend == nil else { return }
        do {
            let daten = try KoppelLink.lese(text)
            fehler = nil
            ausstehend = Ausstehend(text: text, host: daten.url.host ?? "")
        } catch let e as LocalizedError {
            fehler = e.errorDescription
            Haptik.fehler()
        } catch {
            fehler = KoppelFehler.keinKoppelLink.nutzerText
            Haptik.fehler()
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if QRScanner.istMoeglich {
            QRScanner { text in pruefe(text) }
            .frame(height: 300)
            .clipShape(.heimherzKarte)
            .overlay { RoundedRectangle(cornerRadius: Rundung.karte, style: .continuous).stroke(Color.linie, lineWidth: 1) }
            .accessibilityLabel("Kamera zum Scannen des QR-Codes")
        } else {
            ListenKarte {
                Label("Keine Kamera hier. Füge den Link vom PC ein.", systemImage: "camera.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
            }
        }
    }

    @ViewBuilder
    private var einfuegen: some View {
        if QRScanner.istMoeglich {
            DisclosureGroup("Link statt QR-Code einfügen", isExpanded: $linkOffen) { linkFeld.padding(.top, Abstand.s) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tinte)
                .tint(Color.tinte2)
        } else {
            linkFeld
        }
    }

    private var linkFeld: some View {
        VStack(alignment: .leading, spacing: Abstand.s) {
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
                    pruefe(link)
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
