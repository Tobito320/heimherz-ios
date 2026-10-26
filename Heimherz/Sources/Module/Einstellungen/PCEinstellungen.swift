import SwiftUI

/// Unterseite "PC": Verbindung, Server-Adresse und was der Dienst meldet, dazu Neu prüfen, Neu koppeln und Entkoppeln (alles Seltene).
struct PCEinstellungenSeite: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.dismiss) private var schliessen
    @State private var zeigeKoppeln = false
    @State private var frageEntkoppeln = false
    @State private var pruefung = EntkoppelPruefung.alleAmPC
    @State private var pruefeEntkoppeln = false
    @State private var entkoppelFehler: String?

    var body: some View {
        List {
            if umgebung.statusFehler != nil || entkoppelFehler != nil {
                Section {
                    if let fehler = umgebung.statusFehler { StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn) }
                    if let fehler = entkoppelFehler { StatusChip(text: fehler, symbol: "xmark.octagon.fill", ton: .schlecht) }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Server", value: umgebung.geraet?.url.host ?? "–").lumenZeile()
                if let status = umgebung.status {
                    LabeledContent("Dienst am PC", value: "Version \(status.version)").lumenZeile()
                    LabeledContent("Tresor-Stand", value: "Fassung \(status.rev)").lumenZeile()
                    LabeledContent("Fotos am PC", value: status.fotos.formatted()).lumenZeile()
                    if let frei = status.frei { LabeledContent("Frei am PC", value: frei.formatted(.byteCount(style: .file))).lumenZeile() }
                }
                Button { Task { await umgebung.ladeStatus() } } label: {
                    KachelTitel(titel: umgebung.statusLaedt ? "Prüfe …" : "Neu prüfen", symbol: "arrow.clockwise", ton: .tuerkis)
                }
                .disabled(umgebung.statusLaedt)
                .lumenZeile()
            }
            Section {
                Button { zeigeKoppeln = true } label: {
                    KachelTitel(titel: "Mit anderem PC koppeln", symbol: "qrcode.viewfinder", ton: .gruen)
                }
                .lumenZeile()
                Button(role: .destructive) { starteEntkoppeln() } label: {
                    HStack(spacing: Abstand.m) {
                        EinstellungsKachel(symbol: "xmark.circle.fill", ton: .rot)
                        Text(pruefeEntkoppeln ? "Prüfe …" : "Entkoppeln")
                    }
                }
                .disabled(pruefeEntkoppeln)
                .lumenZeile()
            }
        }
        .lumenEinstellungenListe()
        .navigationTitle("PC")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $zeigeKoppeln) { KoppelBlatt() }
        .confirmationDialog("Dieses Handy vom PC trennen?", isPresented: $frageEntkoppeln, titleVisibility: .visible) {
            Button("Entkoppeln", role: .destructive) {
                do {
                    try umgebung.entkoppeln()
                    schliessen()
                } catch {
                    entkoppelFehler = "Entkoppeln hat nicht geklappt: \(FehlerText.von(error))"
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(pruefung.nachricht)
        }
    }

    private func starteEntkoppeln() {
        entkoppelFehler = nil
        Task {
            pruefeEntkoppeln = true
            pruefung = await umgebung.pruefeVorEntkoppeln()
            pruefeEntkoppeln = false
            frageEntkoppeln = true
        }
    }
}
