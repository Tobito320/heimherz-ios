import SwiftUI
import UIKit

/// Wohin ein Tipp in den Einstellungen führt (Unterseiten für Seltenes).
enum EinstellungenSeite: Hashable {
    case pc, autoFill, sichern, codes, sicherung
}

/// Tab "Einstellungen" (SPEC "Einstellungen"): eine gruppierte Liste wie in iOS. Oben der PC, dann Sicherheit, Passwörter, Fotos, Dateien, Über.
/// Jeder Schalter wirkt: Entsperr-Dauer, Code kopieren und Leck-Prüfung liegen in der App Group (`GeteilteEinstellungen`) und werden dort gelesen,
/// die Foto-Schalter gehören dem `FotosModell` (derselbe Zustand wie im Abgleich).
struct EinstellungenTabView: View {
    @Environment(AppUmgebung.self) private var umgebung
    @State private var pfad: [EinstellungenSeite] = Self.startPfad
    @State private var zeigeKoppeln = false
    @State private var zeigeImport = false
    @State private var frageLeeren = false

    // Geteilte Werte: Kopie hier, `.onChange` schreibt in die App Group (UserDefaults melden Änderungen nicht an SwiftUI).
    @State private var dauer = GeteilteEinstellungen().entsperrDauer
    @State private var codeKopieren = GeteilteEinstellungen().codeKopieren
    @State private var leckPruefung = GeteilteEinstellungen().leckPruefung
    @State private var fotoMitteilung = GeteilteEinstellungen().fotoMitteilung

    @State private var fotos: FotosModell?
    @State private var zuletzt: Date?
    @State private var zwischenspeicher: Int64 = 0
    /// nil: noch nicht gefragt (oder Demo).
    @State private var mitteilungErlaubt: Bool?

    private static var startPfad: [EinstellungenSeite] {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "heimherzEinstellungenSeite") {
        case "pc": return [.pc]
        case "autofill": return [.autoFill]
        case "sichern": return [.sichern]
        case "codes": return [.codes]
        case "sicherung": return [.sicherung]
        default: break
        }
        #endif
        return []
    }

    private var buildDatum: String? { Bundle.main.object(forInfoDictionaryKey: "HeimherzBuildDatum") as? String }

    var body: some View {
        NavigationStack(path: $pfad) {
            List {
                if let hinweis = BuildAblauf.hinweis(buildDatum: buildDatum, jetzt: Date()) {
                    Section {
                        StatusChip(text: hinweis.text, symbol: hinweis.abgelaufen ? "xmark.octagon.fill" : "clock.badge.exclamationmark.fill", ton: hinweis.abgelaufen ? .schlecht : .warn)
                            .listRowBackground(Color.clear)
                    } footer: {
                        GruppenText(text: "TestFlight-Builds laufen nach 90 Tagen ab. Lade vorher den neuen Build.", fuss: true)
                    }
                }
                pcGruppe
                sicherheitGruppe
                passwoerterGruppe
                if umgebung.istGekoppelt {
                    sicherungGruppe
                    fotosGruppe
                    dateienGruppe
                }
                ueberGruppe
            }
            .heimherzEinstellungenListe()
            .heimherzGrossTitel("Einstellungen")
            .navigationDestination(for: EinstellungenSeite.self) { seite in
                switch seite {
                case .pc: PCEinstellungenSeite()
                case .autoFill: AutoFillAnleitung()
                case .sichern: SichernErklaerung()
                case .codes: CodesAnleitung()
                case .sicherung: SicherungSeite()
                }
            }
            .refreshable { await umgebung.ladeStatus() }
            .task {
                await umgebung.ladeStatus()
                ladeZuletzt()
            }
        }
        .task(id: umgebung.istGekoppelt) { await ladeWerte() }
        .sheet(isPresented: $zeigeKoppeln) { KoppelBlatt() }
        .sheet(isPresented: $zeigeImport) { ImportAnleitungBlatt() }
        .confirmationDialog("Zwischenspeicher leeren?", isPresented: $frageLeeren, titleVisibility: .visible) {
            Button("Leeren", role: .destructive) {
                VorschauCache.leere()
                zwischenspeicher = VorschauCache.groesse()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Angesehene und geteilte Dateien werden vom Handy gelöscht. Am PC bleibt alles.")
        }
        .onChange(of: dauer) { _, neu in GeteilteEinstellungen().entsperrDauer = neu }
        .onChange(of: codeKopieren) { _, neu in GeteilteEinstellungen().codeKopieren = neu }
        .onChange(of: leckPruefung) { _, neu in GeteilteEinstellungen().leckPruefung = neu }
        .onChange(of: fotoMitteilung) { _, neu in
            GeteilteEinstellungen().fotoMitteilung = neu
            if neu, !umgebung.istDemo { Task { await frageMitteilung() } }
        }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "heimherzKoppeln") { zeigeKoppeln = true }
            #endif
        }
    }

    // MARK: Laden

    private func ladeZuletzt() {
        let sekunden = UserDefaults.standard.double(forKey: TresorStore.merkerSchluessel)
        zuletzt = sekunden > 0 ? Date(timeIntervalSince1970: sekunden) : nil
    }

    private func ladeWerte() async {
        ladeZuletzt()
        guard umgebung.istGekoppelt else { return }
        let modell = fotos ?? (umgebung.istDemo ? FotosModell(istDemo: true) : FotosModell.geteilt)
        modell.liesSystemStand()
        fotos = modell
        zwischenspeicher = await Task.detached { VorschauCache.groesse() }.value
        if !umgebung.istDemo { mitteilungErlaubt = await SystemMitteilungen().erlaubt() }
    }

    private func frageMitteilung() async {
        await SystemMitteilungen().erlaubnisFragen()
        mitteilungErlaubt = await SystemMitteilungen().erlaubt()
    }

    // MARK: PC

    private var pcGruppe: some View {
        Section {
            if umgebung.istGekoppelt {
                NavigationLink(value: EinstellungenSeite.pc) { pcKopf }.heimherzZeile()
                LabeledContent("Zuletzt abgeglichen", value: zuletzt.map { $0.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "de_DE"))) } ?? "noch nie")
                    .heimherzZeile()
            } else {
                pcKopf.heimherzZeile()
                Button { zeigeKoppeln = true } label: {
                    Label("Mit PC koppeln", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Abstand.tippflaeche)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.knopf)
                .foregroundStyle(Color.aufKnopf)
                .listRowBackground(Color.clear)
            }
        }
    }

    private var pcKopf: some View {
        HStack(spacing: Abstand.m) {
            HausherzView(stimmung: umgebung.istGekoppelt ? (umgebung.statusFehler == nil ? .wach : .sorry) : .schlaeft, groesse: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(umgebung.istGekoppelt ? "Mit dem PC verbunden" : "Noch nicht gekoppelt")
                    .font(.headline)
                    .foregroundStyle(Color.tinte)
                Text(pcUntertitel)
                    .font(.subheadline)
                    .foregroundStyle(Color.tinte2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Abstand.xs)
        .accessibilityElement(children: .combine)
    }

    private var pcUntertitel: String {
        guard let geraet = umgebung.geraet else { return "Scanne den QR-Code vom PC." }
        if umgebung.statusFehler != nil { return "Der PC antwortet gerade nicht." }
        return geraet.url.host ?? "PC"
    }

    // MARK: Sicherheit

    private var sicherheitGruppe: some View {
        Section {
            Picker(selection: $dauer) {
                ForEach(EntsperrDauer.allCases) { Text($0.titel).tag($0) }
            } label: {
                KachelTitel(titel: "Face ID gilt für", symbol: "faceid", ton: .gruen)
            }
            .pickerStyle(.menu)
            .heimherzZeile()
            Toggle(isOn: $codeKopieren) {
                KachelTitel(titel: "2FA-Code nach dem Ausfüllen kopieren", symbol: "doc.on.clipboard", ton: .gelb)
            }
            .heimherzZeile()
        } header: {
            GruppenText(text: "Sicherheit")
        } footer: {
            GruppenText(text: "Solange füllt Lumen ohne neue Abfrage aus.", fuss: true)
        }
    }

    // MARK: Passwörter

    private var passwoerterGruppe: some View {
        Section {
            NavigationLink(value: EinstellungenSeite.autoFill) {
                KachelTitel(titel: "AutoFill einschalten", symbol: "checkmark.shield.fill", ton: .tuerkis)
            }
            .heimherzZeile()
            NavigationLink(value: EinstellungenSeite.codes) {
                KachelTitel(titel: "Neue 2FA-Codes in Lumen", symbol: "qrcode.viewfinder", ton: .gelb)
            }
            .heimherzZeile()
            Button { zeigeImport = true } label: {
                KachelTitel(titel: "Aus Apple Passwörter holen", symbol: "square.and.arrow.down", ton: .orange)
            }
            .heimherzZeile()
            Toggle(isOn: $leckPruefung) {
                KachelTitel(titel: "Auf Datenlecks prüfen", symbol: "exclamationmark.shield.fill", ton: .rot)
            }
            .heimherzZeile()
        } header: {
            GruppenText(text: "Passwörter")
        } footer: {
            GruppenText(text: "Es gehen nur 5 Zeichen eines Hashs an haveibeenpwned.com, nie das Passwort.", fuss: true)
        }
    }

    // MARK: Sicherung

    private var sicherungGruppe: some View {
        Section {
            NavigationLink(value: EinstellungenSeite.sicherung) {
                KachelTitel(titel: "Sicherung und Wiederherstellung", symbol: "externaldrive.fill.badge.checkmark", ton: .gruen)
            }
            .heimherzZeile()
        }
    }

    // MARK: Fotos

    @ViewBuilder
    private var fotosGruppe: some View {
        if let m = fotos {
            Section {
                Toggle(isOn: Binding(get: { m.nurWLAN }, set: { m.setzeNurWLAN($0) })) {
                    KachelTitel(titel: "Nur im WLAN senden", symbol: "wifi", ton: .tuerkis)
                }
                .heimherzZeile()
                Toggle(isOn: Binding(get: { m.iCloudLaden }, set: { m.setzeICloudLaden($0) })) {
                    KachelTitel(titel: "Originale aus iCloud laden", symbol: "icloud.and.arrow.down", ton: .gruen)
                }
                .heimherzZeile()
                Toggle(isOn: Binding(get: { m.hintergrundAn }, set: { m.schalteHintergrund($0) })) {
                    KachelTitel(titel: "Im Hintergrund hochladen", symbol: "moon.stars.fill", ton: .orange)
                }
                .disabled(m.erlaubnis != .voll)
                .heimherzZeile()
                Toggle(isOn: $fotoMitteilung) {
                    KachelTitel(titel: "Mitteilung nach dem Abgleich", symbol: "bell.badge.fill", ton: .rosa)
                }
                .heimherzZeile()
                NavigationLink(value: EinstellungenSeite.sichern) {
                    KachelTitel(titel: "Wie das Sichern läuft", symbol: "questionmark.circle.fill", ton: .grau)
                }
                .heimherzZeile()
            } header: {
                GruppenText(text: "Fotos")
            } footer: {
                GruppenText(text: fotosFuss(m), fuss: true)
            }
        }
    }

    /// Eine Zeile, die gerade am meisten hilft: erst was einen Schalter wirkungslos macht, sonst die feste Regel für Videos.
    private func fotosFuss(_ m: FotosModell) -> String {
        if fotoMitteilung, mitteilungErlaubt == false { return "Mitteilungen sind für Lumen in den iOS-Einstellungen ausgeschaltet." }
        if m.erlaubnis != .voll { return "Hochladen im Hintergrund braucht vollen Zugriff auf deine Fotos." }
        return "Videos gehen immer nur im WLAN. Ist das Handy nicht im WLAN, hält der Abgleich an und wartet auf dich."
    }

    // MARK: Dateien

    private var dateienGruppe: some View {
        Section {
            Button { frageLeeren = true } label: {
                HStack {
                    KachelTitel(titel: "Zwischenspeicher am Handy", symbol: "internaldrive.fill", ton: .grau)
                    Spacer(minLength: Abstand.s)
                    Text(zwischenspeicher == 0 ? "leer" : zwischenspeicher.formatted(.byteCount(style: .file)))
                        .foregroundStyle(Color.tinte2)
                }
            }
            .disabled(zwischenspeicher == 0)
            .heimherzZeile()
        } header: {
            GruppenText(text: "Dateien")
        } footer: {
            GruppenText(text: "Hier liegen Dateien kurz, die du angesehen oder geteilt hast.", fuss: true)
        }
    }

    // MARK: Über

    private var ueberGruppe: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                .heimherzZeile()
            if let datum = BuildAblauf.buildDatum(buildDatum) {
                LabeledContent("Build vom", value: datum.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE"))))
                    .heimherzZeile()
            }
            if let rest = BuildAblauf.verbleibendeTage(buildDatum: buildDatum, jetzt: Date()) {
                LabeledContent("TestFlight läuft ab", value: rest < 0 ? "abgelaufen" : rest == 0 ? "heute" : rest == 1 ? "in 1 Tag" : "in \(rest) Tagen")
                    .heimherzZeile()
            }
        } header: {
            GruppenText(text: "Über")
        }
    }
}
