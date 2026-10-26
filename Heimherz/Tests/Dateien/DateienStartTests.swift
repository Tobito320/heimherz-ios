import XCTest
@testable import Heimherz

/// Startseite "Durchsuchen" (T21): Abschnitte, Symbole, Einklappen, Laden.
final class DateienStartLogikTests: XCTestCase {
    private func ordner(_ name: String) -> DateiInfo { DateiInfo(name: name, ordner: true, groesse: 0, geaendert: "2026-10-25T10:00:00.000Z", anzahl: 3) }
    private func datei(_ name: String) -> DateiInfo { DateiInfo(name: name, ordner: false, groesse: 10, geaendert: "2026-10-25T10:00:00.000Z") }

    /// Die echte Ordnung am PC (26.10.2026).
    private var wurzel: [DateiInfo] { [ordner("Weitere"), ordner("Aboherz"), ordner("Projekte"), ordner("Bürokratie")] }
    private var inhalte: [DateiKategorie: [DateiInfo]] {
        [
            .buerokratie: ["_Alt vor 17.09.2026", "_Archiv", "7 Schule & Arbeit", "1 Ausweise", "2 Jobcenter", "3 Behörden", "4 Geld", "5 Wohnen", "6 Gesundheit"].map(ordner),
            .projekte: ["Videos", "Money Machine – Claude Business", "Coding"].map(ordner),
            .weitere: ["Sonstiges", "iCloud Drive", "Fitness"].map(ordner),
        ]
    }

    func testAbschnitteInFesterReihenfolgeMitVollenPfaden() {
        let a = DateienStart.bilde(wurzel: wurzel, inhalte: inhalte)
        XCTAssertEqual(a.map(\.kategorie), [.buerokratie, .projekte, .weitere], "Reihenfolge egal, wie die Wurzel sie liefert")
        XCTAssertEqual(a.map(\.kategorie.titel), ["Bürokratie", "Projekte", "Weitere"])
        XCTAssertEqual(a[0].zeilen.map(\.pfad), [
            "Bürokratie/1 Ausweise", "Bürokratie/2 Jobcenter", "Bürokratie/3 Behörden", "Bürokratie/4 Geld", "Bürokratie/5 Wohnen",
            "Bürokratie/6 Gesundheit", "Bürokratie/7 Schule & Arbeit", "Bürokratie/_Alt vor 17.09.2026", "Bürokratie/_Archiv",
        ], "Zahlen der Reihe nach, Ordner mit _ ganz unten")
        XCTAssertEqual(a[1].zeilen.map(\.pfad), ["Projekte/Coding", "Projekte/Money Machine – Claude Business", "Projekte/Videos"])
        XCTAssertEqual(a[0].zeilen[0].ueber, ["Bürokratie"])
        XCTAssertEqual(a[0].zeilen[0].info.anzahl, 3)
    }

    func testWeitereSammeltFremdeAusDerWurzelUndDenWeitereOrdner() {
        var w = wurzel
        w.append(datei("Notiz.txt"))
        let a = DateienStart.bilde(wurzel: w, inhalte: inhalte)
        let weitere = a[2]
        XCTAssertEqual(weitere.kategorie, .weitere)
        XCTAssertEqual(weitere.zeilen.map(\.pfad), ["Aboherz", "Weitere/Fitness", "Weitere/iCloud Drive", "Weitere/Sonstiges", "Notiz.txt"], "Ordner zuerst, dann Dateien")
        XCTAssertEqual(weitere.zeilen.map(\.ueber), [[], ["Weitere"], ["Weitere"], ["Weitere"], []])
        XCTAssertFalse(weitere.zeilen.contains { $0.pfad == "Bürokratie" || $0.pfad == "Projekte" || $0.pfad == "Weitere" }, "die Kategorie-Ordner selbst sind keine Zeilen")
    }

    func testFehlendeKategorieFehltUndLeereAuch() {
        let ohneProjekte = wurzel.filter { $0.name != "Projekte" }
        XCTAssertEqual(DateienStart.bilde(wurzel: ohneProjekte, inhalte: inhalte).map(\.kategorie), [.buerokratie, .weitere])
        XCTAssertEqual(DateienStart.bilde(wurzel: wurzel, inhalte: [.buerokratie: [], .projekte: inhalte[.projekte] ?? [], .weitere: []]).map(\.kategorie), [.projekte, .weitere],
                       "leerer Ordner gibt keinen leeren Abschnitt; Weitere bleibt wegen Aboherz")
        XCTAssertEqual(DateienStart.bilde(wurzel: [], inhalte: [:]), [])
        XCTAssertEqual(DateienStart.bilde(wurzel: [ordner("Aboherz")], inhalte: [:]).map(\.kategorie), [.weitere], "nur Fremde: Weitere ohne Weitere-Ordner")
    }

    func testEineDateiNamensBuerokratieIstKeineKategorie() {
        let a = DateienStart.bilde(wurzel: [datei("Bürokratie")], inhalte: [:])
        XCTAssertEqual(a.map(\.kategorie), [.weitere])
        XCTAssertEqual(a[0].zeilen.map(\.pfad), ["Bürokratie"])
    }

    func testWelcheKategorienAmPCLiegen() {
        XCTAssertEqual(DateienStart.vorhanden(in: wurzel), [.buerokratie, .projekte, .weitere])
        XCTAssertEqual(DateienStart.vorhanden(in: [datei("Projekte"), ordner("Aboherz")]), [])
    }

    func testOrdnerSymbolTabelleMitEchtenNamen() {
        let erwartet: [String: String] = [
            "1 Ausweise": "person.text.rectangle", "2 Jobcenter": "building.2", "3 Behörden": "building.columns", "4 Geld": "eurosign.circle",
            "5 Wohnen": "house", "6 Gesundheit": "cross.case", "7 Schule & Arbeit": "graduationcap", "_Archiv": "archivebox",
            "_Alt vor 17.09.2026": "archivebox", "Coding": "chevron.left.forwardslash.chevron.right", "Videos": "film",
            "Money Machine – Claude Business": "briefcase", "Fitness": "figure.run", "iCloud Drive": "icloud",
            "Sonstiges": "folder", "Aboherz": "folder", "": "folder",
        ]
        for (name, symbol) in erwartet {
            XCTAssertEqual(DateiAnzeige.ordnerSymbol(name: name), symbol, name)
        }
        XCTAssertEqual(DateiAnzeige.ordnerSymbol(name: "3 Beho\u{308}rden"), "building.columns", "auch zerlegte Umlaute (NFD)")
        XCTAssertEqual(DateiAnzeige.ordnerSymbol(name: "GELD"), "eurosign.circle", "Groß und klein egal")
    }

    func testZeilenSymbolOrdnerNachNameDateiNachEndung() {
        let a = DateienStart.bilde(wurzel: wurzel + [datei("Notiz.txt")], inhalte: inhalte)
        XCTAssertEqual(a[0].zeilen[0].symbol, "person.text.rectangle")
        XCTAssertEqual(a[2].zeilen.last?.symbol, DateiAnzeige.symbol(name: "Notiz.txt", ordner: false))
    }

    func testEinklappenWirdGemerkt() {
        var z = EingeklappteAbschnitte()
        XCTAssertFalse(z.istEingeklappt(.projekte))
        z.schalte(.projekte)
        XCTAssertTrue(z.istEingeklappt(.projekte))
        XCTAssertFalse(z.istEingeklappt(.buerokratie))
        z.schalte(.weitere)
        let gespeichert = z.rawValue
        XCTAssertEqual(EingeklappteAbschnitte(rawValue: gespeichert), z, "AppStorage-Rundreise")
        XCTAssertTrue(EingeklappteAbschnitte(rawValue: gespeichert)?.istEingeklappt(.weitere) ?? false)
        z.schalte(.projekte)
        XCTAssertFalse(z.istEingeklappt(.projekte), "nochmal tippen klappt wieder auf")
        XCTAssertEqual(EingeklappteAbschnitte(rawValue: "")?.namen, [])
        XCTAssertEqual(EingeklappteAbschnitte(rawValue: "Unbekannt|Projekte")?.istEingeklappt(.projekte), true, "Unbekanntes stört nicht")
    }
}

@MainActor
final class DateienStartModellTests: XCTestCase {
    private let jetzt = "2026-10-25T10:00:00.000Z"

    private func liste(_ eintraege: [(String, Bool)]) -> String {
        "[" + eintraege.map { #"{"name":"\#($0.0)","ordner":\#($0.1),"groesse":1,"geaendert":"\#(jetzt)"}"# }.joined(separator: ",") + "]"
    }

    private func modell(_ h: @escaping FakeNetz.Handler) -> DateienStartModell {
        let (sitzung, basis) = FakeNetz.neu(h)
        let client = HeimClient(basis: basis, token: TestSchluessel.token, sitzung: sitzung)
        return DateienStartModell(istDemo: false) { client }
    }

    func testLaedtWurzelUndNurDieKategorienDieEsGibt() async {
        let pfade = Kasten<[String]>([])
        let wurzel = liste([("Bürokratie", true), ("Aboherz", true)])
        let buero = liste([("1 Ausweise", true), ("2 Jobcenter", true)])
        let m = modell { r, _ in
            let p = pfadParameter(r)
            pfade.mit { $0.append(p) }
            return .json(p == "" ? wurzel : (p == "Bürokratie" ? buero : "[]"))
        }
        XCTAssertEqual(m.zustand, .laedt)
        await m.lade()
        XCTAssertEqual(m.zustand, .bereit)
        XCTAssertEqual(m.abschnitte.map(\.kategorie), [.buerokratie, .weitere])
        XCTAssertEqual(m.abschnitte[0].zeilen.map(\.pfad), ["Bürokratie/1 Ausweise", "Bürokratie/2 Jobcenter"])
        XCTAssertEqual(m.abschnitte[1].zeilen.map(\.pfad), ["Aboherz"])
        XCTAssertEqual(Set(pfade.mit { $0 }), ["", "Bürokratie"], "Projekte und Weitere gibt es nicht: nicht anfragen")
    }

    func testKategorieInDerWurzelAberNichtLadbarIstEinFehlerKeinStillesWegfallen() async {
        let wurzel = liste([("Projekte", true)])
        let m = modell { r, _ in pfadParameter(r) == "" ? .json(wurzel) : .init(status: 404) }
        await m.lade()
        XCTAssertEqual(m.zustand, .fehler(HeimFehler.nichtGefunden.nutzerText, offline: false), "Ordner steht in der Wurzel, Liste scheitert: ehrlich melden")
    }

    func testOfflineBehaeltDieLetztenAbschnitte() async {
        let aus = Kasten(false)
        let wurzel = liste([("Bürokratie", true)])
        let buero = liste([("1 Ausweise", true)])
        let m = modell { r, _ in
            if aus.mit({ $0 }) { return .fehler(.notConnectedToInternet) }
            return .json(pfadParameter(r) == "" ? wurzel : buero)
        }
        await m.lade()
        XCTAssertEqual(m.abschnitte.count, 1)
        aus.mit { $0 = true }
        await m.lade()
        XCTAssertEqual(m.abschnitte.count, 1, "die letzte Liste bleibt sichtbar")
        XCTAssertEqual(m.zustand, .fehler(HeimFehler.nichtErreichbar.nutzerText, offline: true))
    }

    func testDemoRuehrtDasNetzNichtAn() async {
        let m = DateienStartModell(istDemo: true) { throw HeimFehler.nichtGekoppelt }
        XCTAssertEqual(m.abschnitte.map(\.kategorie), [.buerokratie, .projekte, .weitere])
        XCTAssertEqual(m.zustand, .bereit)
        let vorher = m.abschnitte
        await m.lade()
        XCTAssertEqual(m.abschnitte, vorher)
        XCTAssertTrue(m.abschnitte[0].zeilen.contains { $0.pfad == "Bürokratie/2 Jobcenter" })
        XCTAssertTrue(m.abschnitte[2].zeilen.contains { $0.pfad == "Aboherz" }, "Fremdes aus der Wurzel steht unter Weitere")
    }
}

private func pfadParameter(_ r: URLRequest) -> String {
    URLComponents(url: r.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pfad" }?.value ?? "?"
}
