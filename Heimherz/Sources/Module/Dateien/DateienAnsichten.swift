import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Bausteine des Dateien-Tabs. Nur Systemkomponenten und Systemfarben (SPEC 12): kein eigener Hintergrund, keine Karten.

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
                Image(systemName: "folder.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.blue)
                    .padding(seite * 0.06)
            } else if let bild {
                Image(uiImage: bild)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: seite * 0.08, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: seite * 0.08, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            } else {
                Image(systemName: DateiAnzeige.symbol(name: eintrag.name, ordner: false))
                    .font(.system(size: seite * 0.5))
                    .foregroundStyle(Color.secondary)
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
                Text(eintrag.name).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                Text(DateiAnzeige.listenUntertitel(eintrag)).font(.footnote).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Zelle der Symbolansicht: Vorschau, Name (bis zwei Zeilen, mittig), darunter Datum und Größe klein und grau; Ordner mit "12 Objekte".
struct RasterZelle: View {
    let eintrag: DateiInfo
    let pfad: String
    let lader: DateiVorschauLader

    var body: some View {
        VStack(spacing: 4) {
            DateiBild(eintrag: eintrag, pfad: pfad, seite: 100, px: 300, lader: lader)
            Text(eintrag.name).font(.footnote).foregroundStyle(Color.primary).multilineTextAlignment(.center).lineLimit(2)
            ForEach(Array(DateiAnzeige.rasterZeilen(eintrag).enumerated()), id: \.offset) { _, zeile in
                Text(zeile).font(.caption2).foregroundStyle(Color.secondary)
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
                Text(treffer.name).font(.body).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                Text(DateiAnzeige.ort(treffer.uebergeordnet)).font(.footnote).foregroundStyle(Color.secondary)
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
                        Image(systemName: DateiAnzeige.symbol(name: e.name, ordner: e.ordner))
                            .font(.largeTitle)
                            .foregroundStyle(e.ordner ? Color.blue : Color.secondary)
                            .accessibilityHidden(true)
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
