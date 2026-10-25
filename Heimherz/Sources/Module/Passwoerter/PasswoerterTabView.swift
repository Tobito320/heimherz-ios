import SwiftUI

/// Tab "Passwörter" (SPEC 9): Wurzel. Der Store entsteht einmal pro Ansicht (`State(initialValue:)`, der Initialisierer ist billig und ohne Nebenwirkung).
struct PasswoerterTabView: View {
    @Environment(AppUmgebung.self) private var umgebung

    var body: some View {
        PasswoerterInhalt(umgebung: umgebung)
    }
}

/// Zusammenspiel aus Sperre, Kopplung und Store: gesperrt oder nicht gekoppelt = Klartext raus; entsperrt = öffnen und abgleichen.
struct PasswoerterInhalt: View {
    @Environment(AppUmgebung.self) private var umgebung
    @Environment(\.scenePhase) private var phase
    @State private var store: TresorStore
    @State private var symbole: SymbolLader
    @State private var postfach = ImportPostfach.geteilt
    @State private var suche = ""
    @State private var pfad: [PasswoerterZiel] = []
    @State private var formular: FormularZiel?
    @State private var zeigeGenerator = false
    @State private var zeigeAnleitung = false

    init(umgebung: AppUmgebung) {
        _store = State(initialValue: TresorStore(umgebung: umgebung))
        _symbole = State(initialValue: SymbolLader.verbunden(mit: umgebung))
    }

    /// Ändert sich einer der Werte, startet `.task(id:)` neu.
    private struct Lage: Equatable {
        let gesperrt: Bool
        let gekoppelt: Bool
        /// Ein neuer Zugang ersetzt den alten, ohne dass `gekoppelt` wechselt.
        let kopplung: Int
    }

    private var lage: Lage { Lage(gesperrt: umgebung.sperre.gesperrt, gekoppelt: umgebung.istGekoppelt, kopplung: umgebung.kopplung) }

    var body: some View {
        NavigationStack(path: $pfad) {
            inhalt
                .navigationTitle("Passwörter")
                .navigationDestination(for: PasswoerterZiel.self) { ziel in
                    switch ziel {
                    case .kategorie(let k):
                        PasswoerterListe(store: store, kategorie: k, neu: { formular = $0 }, generator: { zeigeGenerator = true })
                    case .eintrag(let id):
                        EintragDetailView(store: store, id: id) { formular = .bearbeiten($0) }
                    }
                }
                .heimherzHintergrund()
        }
        .environment(symbole)
        .sheet(item: $formular) { ziel in EintragFormular(store: store, ziel: ziel) }
        .sheet(isPresented: $zeigeGenerator) { GeneratorBlatt(uebernehmen: nil) }
        .sheet(isPresented: $zeigeAnleitung) { ImportAnleitungBlatt() }
        .sheet(item: Binding(get: { postfach.ergebnis.map(ImportAnzeige.init) }, set: { if $0 == nil { postfach.schliesseErgebnis() } })) { anzeige in
            ImportErgebnisBlatt(ergebnis: anzeige.zaehler)
        }
        .alert("Import aus Apple Passwörter", isPresented: Binding(get: { postfach.fehler != nil }, set: { if !$0 { postfach.schliesseFehler() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(postfach.fehler ?? "")
        }
        .task(id: lage) { await lageAnwenden() }
        .task(id: ImportBedingung(bereit: store.zustand == .bereit, hatPaket: postfach.paket != nil)) { await importAusfuehren() }
        .onChange(of: phase) { _, neu in
            if neu == .active, lage.gekoppelt, !lage.gesperrt { Task { await store.abgleichen() } }
        }
    }

    private struct ImportBedingung: Equatable {
        let bereit: Bool
        let hatPaket: Bool
    }

    private struct ImportAnzeige: Identifiable {
        let zaehler: ImportZaehler
        var id: String { zaehler.text }
    }

    private func lageAnwenden() async {
        store.sperren()   // jede neue Lage (auch ein neuer Zugang) beginnt mit leerem Speicher
        if lage.gesperrt || !lage.gekoppelt {
            suche = ""
            pfad = []
            formular = nil
            zeigeGenerator = false
            zeigeAnleitung = false
            if !lage.gekoppelt {
                postfach.verwerfe()
                if !umgebung.istDemo { await AutoFillIdentitaeten.leeren() }
            }
            return
        }
        await store.oeffnen()
        #if DEBUG
        if umgebung.istDemo { demoSeite() }
        #endif
    }

    /// Der Import wartet im Speicher, bis der Tresor offen ist; dann wird einmal eingemischt und abgeglichen.
    private func importAusfuehren() async {
        guard store.zustand == .bereit, let paket = postfach.nimm() else { return }
        // Eigene Aufgabe: `nimm()` ändert die Bedingung von `.task(id:)`, das würde diese Aufgabe mitten im Speichern abbrechen.
        Task {
            let z = await store.importiere(paket)
            pfad = []
            postfach.zeige(z)
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var inhalt: some View {
        if !umgebung.istGekoppelt {
            ScrollView {
                LeerZustand(titel: "Passwörter", text: "Koppel zuerst dein Handy mit dem PC (Tab Mehr). Danach liegen deine Passwörter hier und in Safari und Apps.")
            }
        } else {
            switch store.zustand {
            case .leer, .laedt:
                VStack(spacing: Abstand.m) {
                    ProgressView()
                    Text("Tresor wird geöffnet …")
                        .font(.subheadline)
                        .foregroundStyle(Color.tinte2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fehler(let text):
                ScrollView {
                    FehlerKarte(text: text) { Task { await store.oeffnen() } }
                        .padding(Abstand.l)
                }
            case .bereit:
                PasswoerterStart(store: store, suche: $suche, neu: { formular = $0 }, generator: { zeigeGenerator = true }, anleitung: { zeigeAnleitung = true })
            }
        }
    }

    #if DEBUG
    /// Nur Screenshots in CI (`-heimherzPwSeite alle|passkeys|codes|sicherheit|geloescht|detail|import`): springt in die Demo auf die Seite.
    private func demoSeite() {
        switch UserDefaults.standard.string(forKey: "heimherzPwSeite") {
        case "alle": pfad = [.kategorie(.alle)]
        case "passkeys": pfad = [.kategorie(.passkeys)]
        case "codes": pfad = [.kategorie(.codes)]
        case "sicherheit": pfad = [.kategorie(.sicherheit)]
        case "geloescht": pfad = [.kategorie(.geloescht)]
        case "detail": pfad = [.kategorie(.alle), .eintrag("demo-1")]
        case "import": zeigeAnleitung = true
        default: break
        }
    }
    #endif
}
