import Photos
import SwiftUI
import UIKit

/// "Fotos sehen": die Mediathek als Raster, jedes Bild mit seinem Stand (am PC, wartet, läuft, Fehler). Übertragene Bilder bekommen ihr Häkchen,
/// während der Abgleich läuft. Vorschauen kommen von PhotoKit (`VorschauLader`), nie aus iCloud.
struct FotoRasterView: View {
    @Environment(AppUmgebung.self) private var umgebung
    let modell: FotosModell
    @State private var mediathek: FotoMediathek
    @State private var filter: FotoFilter = .alle
    @State private var indizes: [Int] = []
    @State private var letzterStand = ""
    @State private var auswahl: Auswahl?

    struct Auswahl: Identifiable {
        let index: Int
        var id: Int { index }
    }

    init(modell: FotosModell) {
        self.modell = modell
        _mediathek = State(initialValue: FotoMediathek(istDemo: modell.istDemo))
    }

    var body: some View {
        VStack(spacing: Abstand.s) {
            FotoLaufLeiste(modell: modell)
                .padding(.horizontal, Abstand.l)
            Picker("Filter", selection: $filter) {
                ForEach(FotoFilter.allCases) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Abstand.l)
            raster
        }
        .task { await laufend() }
        .onChange(of: filter) { _, _ in berechne() }
        .sheet(item: $auswahl) { a in
            FotoDetail(modell: modell, asset: mediathek.asset(at: a.index), kennung: mediathek.koepfe[safe: a.index]?.kennung ?? "")
        }
    }

    @ViewBuilder private var raster: some View {
        if !mediathek.geladen {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if indizes.isEmpty {
            LeerZustand(titel: filter == .amPC ? "Noch nichts am PC" : "Nichts zu zeigen", text: filter == .amPC ? "Starte den Abgleich, dann erscheinen die Bilder hier mit Häkchen." : "In dieser Ansicht ist kein Bild.")
                .padding(Abstand.l)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 2)], spacing: 2) {
                    ForEach(indizes, id: \.self) { i in zelle(i) }
                }
                .padding(.bottom, Abstand.xl)
            }
            .refreshable { await mediathek.lade(); berechne() }
        }
    }

    private func zelle(_ i: Int) -> some View {
        let kennung = mediathek.koepfe[safe: i]?.kennung ?? ""
        let status = FotoRaster.status(kennung: kennung, anzeige: modell.anzeige)
        return Button { auswahl = Auswahl(index: i) } label: {
            FotoZelle(asset: mediathek.asset(at: i), status: status)
        }
        .buttonStyle(.plain)
        .onAppear { VorschauLader.geteilt.sichtbar(mitte: i, mediathek: mediathek) }
    }

    /// Lädt die Mediathek und bildet die Liste höchstens einmal je Sekunde neu, solange der Abgleich Bilder fertig meldet.
    private func laufend() async {
        await mediathek.lade()
        while !Task.isCancelled {
            berechne()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func berechne() {
        let stand = "\(filter.rawValue)-\(mediathek.koepfe.count)-\(filter == .alle ? 0 : modell.anzeige.fertig.count)"
        guard stand != letzterStand else { return }
        letzterStand = stand
        indizes = FotoRaster.indizes(koepfe: mediathek.koepfe, filter: filter, anzeige: modell.anzeige)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Eine Zelle: Vorschau, unten rechts der Stand als Symbol.
private struct FotoZelle: View {
    let asset: PHAsset?
    let status: FotoStatus
    @State private var bild: UIImage?

    var body: some View {
        Color.karteZart
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let bild {
                    Image(uiImage: bild).resizable().scaledToFill()
                } else {
                    Image(systemName: asset?.mediaType == .video ? "video.fill" : "photo.fill").foregroundStyle(Color.tinte3)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) { Plakette(status: status) }
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                bild = await VorschauLader.geteilt.bild(asset)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(beschreibung))
            .accessibilityAddTraits(.isButton)
    }

    private var beschreibung: String {
        let art = asset?.mediaType == .video ? "Video" : "Foto"
        let datum = asset?.creationDate.map { " vom \($0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE"))))" } ?? ""
        return "\(art)\(datum), \(status.text)"
    }
}

private struct Plakette: View {
    let status: FotoStatus

    var body: some View {
        Group {
            switch status {
            case .offen:
                EmptyView()
            case .laeuft:
                ProgressView().controlSize(.mini).padding(4).background(.regularMaterial, in: Circle())
            default:
                Image(systemName: status.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(farbe)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding(4)
    }

    private var farbe: Color {
        switch status {
        case .amPC: return .ok
        case .fehler: return .schlecht
        default: return .tinte2
        }
    }
}

/// Schmale Leiste über dem Raster: Stand des Abgleichs und Start oder Anhalten, damit man beim Schauen nicht zurück muss.
struct FotoLaufLeiste: View {
    let modell: FotosModell

    var body: some View {
        // Bei großer Schrift ist kein Platz nebeneinander: dann steht der Knopf unter dem Text.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Abstand.m) {
                stand
                Spacer(minLength: 0)
                FotoStartKnopf(modell: modell, kompakt: true)
            }
            VStack(alignment: .leading, spacing: Abstand.s) {
                stand
                FotoStartKnopf(modell: modell, kompakt: false)
            }
        }
        .padding(Abstand.m)
        .background(Color.karte, in: .lumenFeld)
    }
}

extension FotoLaufLeiste {
    fileprivate var stand: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(FotoText.stand(modell.anzeige))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tinte)
                .fixedSize(horizontal: false, vertical: true)
            if modell.laeuft, let t = FotoText.tempo(modell.anzeige) {
                Text(t).font(.caption).foregroundStyle(Color.tinte2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Der eine Knopf: "Abgleich starten", solange nichts läuft, sonst "Anhalten".
struct FotoStartKnopf: View {
    @Environment(AppUmgebung.self) private var umgebung
    let modell: FotosModell
    var kompakt = false

    var body: some View {
        if modell.laeuft {
            Button { modell.halteAnVomNutzer() } label: {
                Label("Anhalten", systemImage: "pause.fill")
                    .frame(maxWidth: kompakt ? nil : .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glass)
        } else {
            Button {
                if let c = try? umgebung.client() { modell.starte(client: c) }
            } label: {
                Label("Abgleich starten", systemImage: "arrow.triangle.2.circlepath")
                    .font(kompakt ? .subheadline.weight(.semibold) : .headline)
                    .frame(maxWidth: kompakt ? nil : .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.knopf)
            .foregroundStyle(Color.aufKnopf)
            .controlSize(kompakt ? .regular : .large)
        }
    }
}

/// Texte zum Stand, rein (Test).
enum FotoText {
    /// "Fotos: 4.812 von 6.900 · danach 625 Videos", danach "Videos: 120 von 625". nil ohne Videos oder wenn alles da ist.
    static func phasen(_ p: FotoPhasen?) -> String? {
        guard let p, p.videosGesamt > 0 else { return nil }
        if p.fotosOffen > 0 {
            let videos = p.videosOffen == 1 ? "1 Video" : "\(p.videosOffen.formatted()) Videos"
            return p.videosOffen > 0 ? "Fotos: \(p.fotosAmPC.formatted()) von \(p.fotosGesamt.formatted()) · danach \(videos)" : "Fotos: \(p.fotosAmPC.formatted()) von \(p.fotosGesamt.formatted())"
        }
        return p.videosOffen > 0 ? "Videos: \(p.videosAmPC.formatted()) von \(p.videosGesamt.formatted())" : nil
    }

    static func stand(_ a: FotoAnzeige) -> String {
        guard let z = a.zahlen else { return a.laeuft ? "Zähle die Fotos …" : "Noch nicht gezählt" }
        if z.offen == 0 { return "Alles liegt auf dem PC" }
        return "\(z.amPC.formatted()) von \(z.gesamt.formatted()) am PC"
    }

    /// Unter dem Tempo, solange ein Lauf aktiv ist: iOS drosselt Hintergrund-Übertragungen; ob und wie stark, zeigt `heimherz tempo` (Session vorder gegen hinter, SPEC 11).
    static let vordergrundHinweis = "Schneller, wenn Lumen Cloud offen bleibt."

    /// "4,2 MB/s · ca. 1 Std. 30 Min. übrig"
    static func tempo(_ a: FotoAnzeige) -> String? {
        var teile: [String] = []
        if let b = a.bytesProSekunde { teile.append("\(Int64(b).formatted(.byteCount(style: .file)))/s") }
        if let r = a.restSekunden { teile.append("\(FotoTempo.restText(r)) übrig") }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }
}

/// Ein Bild groß, mit Datum, Art, Auflösung, Stand und "Jetzt hochladen" für genau dieses Bild.
private struct FotoDetail: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.dismiss) private var schliesse
    let modell: FotosModell
    let asset: PHAsset?
    let kennung: String
    @State private var bild: UIImage?

    private var status: FotoStatus { FotoRaster.status(kennung: kennung, anzeige: modell.anzeige) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.l) {
                    gross
                    ListenKarte {
                        WertZeile(name: "Aufgenommen", wert: datum)
                        WertZeile(name: "Art", wert: art)
                        WertZeile(name: "Auflösung", wert: aufloesung)
                        WertZeile(name: "Stand", wert: status.text)
                    }
                    knopf
                }
                .padding(Abstand.l)
            }
            .lumenHintergrund()
            .navigationTitle("Bild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliesse() } } }
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                bild = await VorschauLader.geteilt.gross(asset)
            }
        }
    }

    private var gross: some View {
        Color.karteZart
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let bild { Image(uiImage: bild).resizable().scaledToFit() } else { ProgressView() }
            }
            .clipShape(.lumenFeld)
            .accessibilityHidden(true)
    }

    private var knopf: some View {
        VStack(alignment: .leading, spacing: Abstand.xs) {
            Button {
                if let asset, let c = try? umgebung.client() { modell.ladeEinzeln(assetId: asset.localIdentifier, client: c) }
            } label: {
                Label("Jetzt hochladen", systemImage: "arrow.up.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.knopf)
            .foregroundStyle(Color.aufKnopf)
            .disabled(hinweis != nil || asset == nil)
            if let hinweis {
                Text(hinweis).font(.footnote).foregroundStyle(Color.tinte2)
            }
        }
    }

    /// Grund, warum der Knopf aus ist. Während eines Abgleichs gesperrt, sonst bekäme der PC dieselbe Datei zweimal gleichzeitig.
    private var hinweis: String? {
        if status == .amPC { return "Liegt schon auf dem PC." }
        if modell.laeuft { return "Geht erst, wenn der Abgleich angehalten ist. Dann kommt dieses Bild sofort dran." }
        return nil
    }

    private var datum: String {
        asset?.creationDate?.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "de_DE"))) ?? "–"
    }

    private var art: String {
        switch asset?.mediaType {
        case .video: return "Video"
        default: return asset?.mediaSubtypes.contains(.photoLive) == true ? "Live Photo" : "Foto"
        }
    }

    private var aufloesung: String {
        guard let asset else { return "–" }
        return "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }
}
