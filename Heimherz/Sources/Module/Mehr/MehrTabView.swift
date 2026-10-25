import SwiftUI
import UIKit

/// Tab "Mehr": Status vom PC, Koppeln, Hinweis zum Ablauf des Builds, AutoFill einschalten, Gerät entkoppeln.
struct MehrTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.openURL) private var oeffne
    @State private var zeigeKoppeln = false
    @State private var frageEntkoppeln = false
    @State private var pruefungEntkoppeln = EntkoppelPruefung.alleAmPC
    @State private var pruefeEntkoppeln = false
    @State private var entkoppelFehler: String?

    private var buildDatum: String? {
        Bundle.main.object(forInfoDictionaryKey: "HeimherzBuildDatum") as? String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    verbindung
                    if let hinweis = BuildAblauf.hinweis(buildDatum: buildDatum, jetzt: Date()) { buildHinweis(hinweis) }
                    autoFill
                    ueber
                }
                .padding(.horizontal, Abstand.l)
                .padding(.bottom, Abstand.xl)
            }
            .heimherzHintergrund()
            .navigationTitle("Mehr")
            .refreshable { await umgebung.ladeStatus() }
            .task { await umgebung.ladeStatus() }
        }
        .sheet(isPresented: $zeigeKoppeln) { KoppelBlatt() }
        .confirmationDialog("Dieses Handy vom PC trennen?", isPresented: $frageEntkoppeln, titleVisibility: .visible) {
            Button("Entkoppeln", role: .destructive) {
                do { try umgebung.entkoppeln() } catch { entkoppelFehler = "Entkoppeln hat nicht geklappt: \(FehlerText.von(error))" }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(pruefungEntkoppeln.nachricht)
        }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "heimherzKoppeln") { zeigeKoppeln = true }
            #endif
        }
    }

    // MARK: Verbindung

    private var verbindung: some View {
        HeroKarte {
            HStack(alignment: .center, spacing: Abstand.m) {
                HausherzView(stimmung: umgebung.istGekoppelt ? (umgebung.statusFehler == nil ? .wach : .sorry) : .schlaeft, groesse: 72)
                VStack(alignment: .leading, spacing: Abstand.xs) {
                    Text(umgebung.istGekoppelt ? "Mit dem PC verbunden" : "Noch nicht gekoppelt")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.tinte)
                    Text(untertitel)
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let status = umgebung.status {
                VStack(spacing: 0) {
                    WertZeile(name: "Dienst am PC", wert: "Version \(status.version)")
                    WertZeile(name: "Tresor-Stand", wert: "Fassung \(status.rev)")
                    WertZeile(name: "Fotos am PC", wert: status.fotos.formatted())
                    if let frei = status.frei { WertZeile(name: "Frei am PC", wert: Self.groesse(frei)) }
                }
            }
            if let fehler = umgebung.statusFehler {
                StatusChip(text: fehler, symbol: "exclamationmark.triangle.fill", ton: .warn)
            }
            if let fehler = entkoppelFehler {
                StatusChip(text: fehler, symbol: "xmark.octagon.fill", ton: .schlecht)
            }
            if umgebung.istGekoppelt {
                HStack {
                    Button {
                        Task { await umgebung.ladeStatus() }
                    } label: {
                        Label(umgebung.statusLaedt ? "Prüfe …" : "Neu prüfen", systemImage: "arrow.clockwise")
                            .frame(minHeight: Abstand.tippflaeche)
                    }
                    .buttonStyle(.glass)
                    .disabled(umgebung.statusLaedt)
                    Spacer()
                    Button(role: .destructive) {
                        entkoppelFehler = nil
                        Task {
                            pruefeEntkoppeln = true
                            pruefungEntkoppeln = await umgebung.pruefeVorEntkoppeln()
                            pruefeEntkoppeln = false
                            frageEntkoppeln = true
                        }
                    } label: {
                        Label(pruefeEntkoppeln ? "Prüfe …" : "Entkoppeln", systemImage: "link.badge.minus")
                            .frame(minHeight: Abstand.tippflaeche)
                    }
                    .buttonStyle(.glass)
                    .tint(Color.schlecht)
                    .disabled(pruefeEntkoppeln)
                }
            } else {
                Button {
                    zeigeKoppeln = true
                } label: {
                    Label("Mit PC koppeln", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.knopf)
                .foregroundStyle(Color.aufKnopf)
                .controlSize(.large)
            }
        }
    }

    private var untertitel: String {
        if !umgebung.istGekoppelt { return "Scanne den QR-Code vom PC, dann holt das Handy Passwörter, Fotos und Dateien." }
        if umgebung.statusLaedt && umgebung.status == nil { return "Prüfe die Verbindung …" }
        if umgebung.statusFehler != nil { return "Der PC antwortet gerade nicht. Passwörter gehen trotzdem." }
        return "Der PC antwortet. Alles ist bereit."
    }

    private static func groesse(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    // MARK: Build

    private func buildHinweis(_ hinweis: BuildAblauf.Hinweis) -> some View {
        ListenKarte {
            StatusChip(text: hinweis.text, symbol: hinweis.abgelaufen ? "xmark.octagon.fill" : "clock.badge.exclamationmark.fill", ton: hinweis.abgelaufen ? .schlecht : .warn)
            Text("TestFlight-Builds laufen nach 90 Tagen ab. Lade vorher den neuen Build, sonst startet die App nicht mehr. Tresor und Fotos am PC bleiben davon unberührt.")
                .font(.footnote)
                .foregroundStyle(Color.tinte2)
                .padding(.top, Abstand.s)
        }
    }

    // MARK: AutoFill

    private var autoFill: some View {
        ListenKarte {
            Text("AutoFill einschalten")
                .font(.headline)
                .foregroundStyle(Color.tinte)
            Text("Damit füllt iOS Passwörter und Einmalcodes aus Heim aus, in Safari und in Apps.")
                .font(.subheadline)
                .foregroundStyle(Color.tinte2)
                .padding(.top, Abstand.xs)
            VStack(alignment: .leading, spacing: Abstand.s) {
                schritt(1, "Einstellungen öffnen")
                schritt(2, "Allgemein, dann AutoFill & Passwörter")
                schritt(3, "Unter „Ausfüllen von“ Heim einschalten")
                schritt(4, "Erst wenn alles sicher läuft: iCloud-Passwörter ausschalten")
            }
            .padding(.vertical, Abstand.m)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { oeffne(url) }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gearshape")
                    .frame(minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glass)
        }
    }

    private func schritt(_ nummer: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.m) {
            Text("\(nummer)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.gruen)
                .frame(width: 26, height: 26)
                .background(Color.chip, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.tinte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(nummer): \(text)")
    }

    // MARK: Über

    private var ueber: some View {
        ListenKarte {
            WertZeile(name: "App-Sperre", wert: "nach 5 Minuten")
            WertZeile(name: "Version", wert: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            if let datum = BuildAblauf.buildDatum(buildDatum) {
                WertZeile(name: "Build vom", wert: datum.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE"))))
            }
        }
    }
}
