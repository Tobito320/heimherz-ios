import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Bausteine des Dateien-Tabs. Nur Systemkomponenten und Systemfarben (SPEC 12): kein eigener Hintergrund, keine Karten.

/// Der Ordner wie in Apples Dateien (Vorbild: Bildschirmfoto von Ahmed, iOS 26), selbst gezeichnet: hinteres Blatt mit Reiter, ein weißer
/// Papierstreifen, davor die Vorderseite mit leichtem Verlauf. Feste Farben, in Hell und Dunkel gleich; kein Schlitz, durch den der Hintergrund scheint.
struct OrdnerSymbol: View {
    static let seitenverhaeltnis: CGFloat = 1.24

    private static let hinten = Color(red: 0.42, green: 0.70, blue: 0.89)
    private static let vorneOben = Color(red: 0.53, green: 0.79, blue: 0.95)
    private static let vorneUnten = Color(red: 0.39, green: 0.68, blue: 0.86)

    var body: some View {
        ZStack {
            OrdnerRueckseite().fill(Self.hinten)
            OrdnerPapier().fill(Color.white)
            OrdnerVorderseite().fill(LinearGradient(colors: [Self.vorneOben, Self.vorneUnten], startPoint: .top, endPoint: .bottom))
        }
        .aspectRatio(Self.seitenverhaeltnis, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Hinteres Blatt: Reiter links, danach eine Stufe nach unten bis zur rechten Kante.
private struct OrdnerRueckseite: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let stufe = h * 0.09
        let ecke = w * 0.05
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + ecke))
        p.addQuadCurve(to: CGPoint(x: r.minX + ecke, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.33, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.39, y: r.minY + stufe),
                   control1: CGPoint(x: r.minX + w * 0.365, y: r.minY),
                   control2: CGPoint(x: r.minX + w * 0.355, y: r.minY + stufe))
        p.addLine(to: CGPoint(x: r.maxX - ecke, y: r.minY + stufe))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + stufe + ecke), control: CGPoint(x: r.maxX, y: r.minY + stufe))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Der weiße Papierstreifen zwischen hinterem Blatt und Vorderseite (unten von der Vorderseite verdeckt).
private struct OrdnerPapier: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: r.minX + r.width * 0.03, y: r.minY + r.height * 0.13, width: r.width * 0.94, height: r.height * 0.2),
             cornerRadius: r.width * 0.03, style: .continuous)
    }
}

private struct OrdnerVorderseite: Shape {
    func path(in r: CGRect) -> Path {
        let oben = r.height * 0.185
        return Path(roundedRect: CGRect(x: r.minX, y: r.minY + oben, width: r.width, height: r.height - oben),
                    cornerRadius: r.width * 0.045, style: .continuous)
    }
}

/// Ordner im Navigationsstapel: ein Wert je Stufe, `ordner` ist der ganze Weg von der Wurzel.
struct OrdnerZiel: Hashable {
    let ordner: [String]
}

/// Was die Suche durchsucht: alles oder nur den Ordner, in dem man steht (Bereichsleiste wie in Dateien).
enum SuchBereich: Hashable {
    case alle, ordner
}

/// Eine Datei oder ein Ordner samt ganzem Pfad (Treffer der Suche liegen nicht im aktuellen Ordner).
struct Gewaehlt: Identifiable, Hashable {
    let info: DateiInfo
    let pfad: String
    var id: String { pfad }
}

struct TeilenZiel: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Vorschaubild, sonst das graue Dateisymbol (sofort da); kommt das Bild vom PC, ersetzt es das Symbol. Ordner sind blaue Ordner.
struct DateiBild: View {
    let eintrag: DateiInfo
    let pfad: String
    let seite: CGFloat
    let px: Int
    let lader: DateiVorschauLader

    @State private var bild: UIImage?

    private var schluessel: String { "\(pfad)|\(eintrag.geaendert)|\(eintrag.groesse)|\(px)" }

    var body: some View {
        ZStack {
            if eintrag.ordner {
                OrdnerSymbol().padding(seite * 0.04)
            } else if let bild {
                Image(uiImage: bild)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: seite * 0.08, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: seite * 0.08, style: .continuous).strokeBorder(Color.tinte.opacity(0.12), lineWidth: 0.5))
            } else {
                Image(systemName: DateiAnzeige.symbol(name: eintrag.name, ordner: false))
                    .font(.system(size: seite * 0.5))
                    .foregroundStyle(Color.tinte2)
            }
        }
        .frame(width: seite, height: seite)
        .accessibilityHidden(true)
        .task(id: schluessel) {
            guard !eintrag.ordner, DateiAnzeige.hatVorschau(name: eintrag.name) else { return }
            bild = lader.bild(schluessel: schluessel)
            if bild == nil { bild = await lader.lade(pfad: pfad, schluessel: schluessel, px: px) }
        }
    }
}

/// Zeile der Listenansicht: Vorschau 40 pt, Name, darunter "Datum – Größe".
struct ListenZeile: View {
    let eintrag: DateiInfo
    let pfad: String
    let lader: DateiVorschauLader

    var body: some View {
        HStack(spacing: 12) {
            DateiBild(eintrag: eintrag, pfad: pfad, seite: 40, px: 120, lader: lader)
            VStack(alignment: .leading, spacing: 2) {
                Text(eintrag.name).font(.body).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                Text(DateiAnzeige.listenUntertitel(eintrag)).font(.footnote).foregroundStyle(Color.tinte2)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Zelle der Symbolansicht wie im Vorbild: großes Symbol oder Vorschau, Name (bis zwei Zeilen, mittig, normale Schrift), darunter grau "8 Objekte" bzw. Datum und Größe.
struct RasterZelle: View {
    let eintrag: DateiInfo
    let pfad: String
    let lader: DateiVorschauLader

    var body: some View {
        VStack(spacing: 4) {
            DateiBild(eintrag: eintrag, pfad: pfad, seite: 96, px: 300, lader: lader)
                .padding(.bottom, 4)
            Text(eintrag.name).font(.body).foregroundStyle(Color.tinte).multilineTextAlignment(.center).lineLimit(2)
            ForEach(Array(DateiAnzeige.rasterZeilen(eintrag).enumerated()), id: \.offset) { _, zeile in
                Text(zeile).font(.subheadline).foregroundStyle(Color.tinte2)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Zeile eines Suchtreffers: wie die Listenzeile, darunter der Ordner, in dem die Datei liegt.
struct TrefferZeile: View {
    let treffer: SuchTreffer
    let lader: DateiVorschauLader

    var body: some View {
        HStack(spacing: 12) {
            DateiBild(eintrag: treffer.info, pfad: treffer.pfad, seite: 40, px: 120, lader: lader)
            VStack(alignment: .leading, spacing: 2) {
                Text(treffer.name).font(.body).foregroundStyle(Color.tinte).fixedSize(horizontal: false, vertical: true)
                Text(DateiAnzeige.ort(treffer.uebergeordnet)).font(.footnote).foregroundStyle(Color.tinte2)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "Informationen" aus dem Langdruck-Menü: Art, Größe, Datum, Ort.
struct DateiInfoBlatt: View {
    let gewaehlt: Gewaehlt

    @Environment(\.dismiss) private var schliesse

    private var e: DateiInfo { gewaehlt.info }

    private var art: String {
        if e.ordner { return "Ordner" }
        let endung = (e.name as NSString).pathExtension
        return UTType(filenameExtension: endung)?.localizedDescription ?? (endung.isEmpty ? "Dokument" : endung.uppercased())
    }

    private var umfang: String {
        if !e.ordner { return DateiAnzeige.groesse(e.groesse) }
        return e.anzahl.map { DateiAnzeige.objekte($0) } ?? "–"
    }

    private var ort: String {
        DateiAnzeige.ort(Array(DateiPfad.teile(gewaehlt.pfad).dropLast()))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if e.ordner {
                            OrdnerSymbol().frame(width: 52)
                        } else {
                            Image(systemName: DateiAnzeige.symbol(name: e.name, ordner: false))
                                .font(.largeTitle)
                                .foregroundStyle(Color.tinte2)
                                .accessibilityHidden(true)
                        }
                        Text(e.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    LabeledContent("Art", value: art)
                    LabeledContent(e.ordner ? "Inhalt" : "Größe", value: umfang)
                    LabeledContent("Geändert", value: DateiAnzeige.datum(e) ?? "–")
                    LabeledContent("Ort", value: ort)
                }
            }
            .navigationTitle("Informationen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliesse() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Das Teilen-Blatt des Systems für eine geladene Datei.
struct TeilenBlatt: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Bereichsleiste "Alle | <Ordnername>" unter der Suche, nur in Unterordnern (an der Wurzel wären beide gleich).
struct SuchBereiche: ViewModifier {
    let aktiv: Bool
    @Binding var auswahl: SuchBereich
    let ordnerName: String

    func body(content: Content) -> some View {
        if aktiv {
            content.searchScopes($auswahl) {
                Text("Alle").tag(SuchBereich.alle)
                Text(ordnerName).tag(SuchBereich.ordner)
            }
        } else {
            content
        }
    }
}

/// Verbundene Ordner vom Handy (W-045): Liste, Trennen per Wischen, neuen Ordner aus der Dateien-App verbinden.
struct OrdnerBlatt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.dismiss) private var schliesse
    @State private var abgleich = OrdnerAbgleich.geteilt
    @State private var waehle = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(abgleich.ordner) { o in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(o.name, systemImage: "folder")
                            if let n = o.offen, n > 0 {
                                Text(n == 1 ? "1 Datei noch nicht am PC" : "\(n) Dateien noch nicht am PC")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Trennen", role: .destructive) { abgleich.trenne(o.id) }
                        }
                    }
                    Button("Ordner verbinden …", systemImage: "plus") { waehle = true }
                } footer: {
                    Text("Neue Dateien gehen an den PC, wenn Cloud geöffnet wird oder Fotos abgleicht.")
                }
            }
            .navigationTitle("Ordner vom Handy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliesse() } }
            }
            .fileImporter(isPresented: $waehle, allowedContentTypes: [.folder]) { ergebnis in
                guard case .success(let url) = ergebnis, abgleich.verbinde(url), let client = try? umgebung.client() else { return }
                Task { await abgleich.abgleichen(client: client) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
