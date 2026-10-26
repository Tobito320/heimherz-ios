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
    @State private var codes = CodePostfach.geteilt
    @State private var codeModell: CodeEinrichten?
    @State private var aktionen = SchnellaktionPostfach.geteilt
    @State private var suche = ""
    @State private var pfad: [PasswoerterZiel] = []
    @State private var formular: FormularZiel?
    @State private var zeigeGenerator = false
    @State private var zeigeAnleitung = false
    @Namespace private var zoom

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
                .heimherzGrossTitel("Passwörter")
                .navigationDestination(for: PasswoerterZiel.self) { ziel in
                    switch ziel {
                    case .kategorie(let k):
                        PasswoerterListe(store: store, kategorie: k, neu: { formular = $0 }, generator: { zeigeGenerator = true })
                            .zoomZiel(k, in: zoom)
                    case .eintrag(let id):
                        EintragDetailView(store: store, id: id) { formular = .bearbeiten($0) }
                    case .gesundheit:
                        GesundheitAnsicht(store: store)
                    }
                }
                .heimherzHintergrund()
        }
        .environment(symbole)
        .sheet(item: $formular) { ziel in EintragFormular(store: store, ziel: ziel) }
        .sheet(isPresented: $zeigeGenerator) { GeneratorBlatt(uebernehmen: nil) }
        .sheet(isPresented: $zeigeAnleitung) { ImportAnleitungBlatt() }
        .sheet(item: $codeModell) { CodeEinrichtenBlatt(modell: $0) }
        .alert("Code einrichten", isPresented: Binding(get: { codes.fehler != nil && !lage.gesperrt }, set: { if !$0 { codes.schliesseFehler() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(codes.fehler ?? "")
        }
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
        .task(id: CodeBedingung(bereit: store.zustand == .bereit && !lage.gesperrt, gekoppelt: lage.gekoppelt, hatCode: codes.konto != nil,
                                frei: formular == nil && !zeigeGenerator && !zeigeAnleitung && codeModell == nil)) { codeAnnehmen() }
        .task(id: AktionBedingung(bereit: store.zustand == .bereit && !lage.gesperrt, aktion: aktionen.offen)) { fuehreAktionAus() }
        .task(id: SpotlightBedingung(bereit: store.zustand == .bereit && !lage.gesperrt, id: SpotlightPostfach.geteilt.angefragt)) {
            if store.zustand == .bereit, !lage.gesperrt, let id = SpotlightPostfach.geteilt.nimm(in: store) { pfad = [.kategorie(.alle), .eintrag(id)] }
        }
        .onChange(of: phase) { _, neu in
            if neu == .active, lage.gekoppelt, !lage.gesperrt { Task { await store.abgleichen() } }
        }
    }

    /// Ein angekommener Code wartet, bis der Tresor offen ist und kein anderes Blatt im Weg ist.
    private struct CodeBedingung: Equatable {
        let bereit: Bool
        let gekoppelt: Bool
        let hatCode: Bool
        let frei: Bool
    }

    private struct ImportBedingung: Equatable {
        let bereit: Bool
        let hatPaket: Bool
    }

    /// Schnellaktionen vom App-Symbol laufen erst, wenn der Tresor offen ist (nicht gesperrt, Schlüssel geladen).
    private struct AktionBedingung: Equatable {
        let bereit: Bool
        let aktion: Schnellaktion?
    }

    /// Treffer aus der iPhone-Suche: erst öffnen, wenn der Tresor offen ist.
    private struct SpotlightBedingung: Equatable {
        let bereit: Bool
        let id: String?
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
            codeModell = nil   // das Blatt hält das Geheimnis: gesperrt = weg
            if !lage.gekoppelt {
                postfach.verwerfe()
                aktionen.verwirf(tab: .passwoerter)
                SpotlightPostfach.geteilt.verwerfe()
                if !umgebung.istDemo {
                    await AutoFillIdentitaeten.leeren()
                    await SpotlightIndex.leeren()
                    LeckSpeicher().vergiss()
                }
            }
            return
        }
        await store.oeffnen()
        #if DEBUG
        if umgebung.istDemo { demoSeite() }
        #endif
    }

    /// Der Code aus dem Postfach wird erst jetzt gelesen: der Tresor ist offen, also war Face ID oder das Entsperr-Fenster da (`TresorStore.oeffnen`).
    /// Ohne Kopplung gibt es keinen Tresor: der Code wird verworfen und das gesagt.
    private func codeAnnehmen() {
        if !lage.gekoppelt, codes.nimm() != nil {
            codes.zeigeFehler("Koppel Lumen Cloud zuerst mit dem PC (Tab Einstellungen). Danach öffne den Link oder den QR-Code noch einmal.")
            return
        }
        guard store.zustand == .bereit, !lage.gesperrt, formular == nil, !zeigeGenerator, !zeigeAnleitung, codeModell == nil,
              let konto = codes.nimm() else { return }
        codeModell = CodeEinrichten(konto: konto, store: store, demo: umgebung.istDemo)
    }

    /// "Codes" und "Neues Passwort" vom App-Symbol: Liste Codes beziehungsweise das Formular, so wie ein Tipp in der App.
    private func fuehreAktionAus() {
        guard store.zustand == .bereit, !lage.gesperrt else { return }
        if aktionen.nimm(.codes) {
            formular = nil
            pfad = [.kategorie(.codes)]
        } else if aktionen.nimm(.neuesPasswort) {
            pfad = []
            formular = .neu(Eintrag.artLogin)
        }
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
                LeerZustand(titel: "Passwörter", text: "Koppel zuerst dein Handy mit dem PC (Tab Einstellungen). Danach liegen deine Passwörter hier und in Safari und Apps.")
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
                PasswoerterStart(store: store, suche: $suche, zoom: zoom, neu: { formular = $0 }, generator: { zeigeGenerator = true }, anleitung: { zeigeAnleitung = true })
            }
        }
    }

    #if DEBUG
    /// Nur Screenshots in CI (`-heimherzPwSeite alle|passkeys|codes|sicherheit|geloescht|detail|import`): springt in die Demo auf die Seite.
    private func demoSeite() {
        demoCodeBlatt()
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

    /// Nur Screenshots in CI (`-heimherzCodeBlatt auswahl|ersetzen|fertig`): das Blatt "Code einrichten" mit erfundenen Codes.
    /// `auswahl` geht den echten Weg über das Postfach, die anderen öffnen das Blatt gleich im gewünschten Schritt.
    private func demoCodeBlatt() {
        guard let schritt = UserDefaults.standard.string(forKey: "heimherzCodeBlatt") else { return }
        let bank = "otpauth://totp/Online-Bank:mia.beispiel?secret=JBSWY3DPEHPK3PXP&issuer=Online-Bank"
        let github = "otpauth://totp/GitHub:mia?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=GitHub&digits=8&algorithm=SHA256"
        if schritt == "auswahl" { codes.empfange(text: bank); return }
        guard let konto = try? OtpAuth.lese(schritt == "ersetzen" ? github : bank) else { return }
        let modell = CodeEinrichten(konto: konto, store: store, demo: true)
        codeModell = modell
        Task {
            if schritt == "ersetzen", let e = store.eintrag("demo-1") { await modell.waehle(e) }
            if schritt == "fertig", let e = store.eintrag("demo-2") { await modell.waehle(e) }
        }
    }
    #endif
}
