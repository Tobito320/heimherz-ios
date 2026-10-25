import Foundation
import Observation

/// Was die Erweiterung dem System zurückgibt. Der View Controller übersetzt es in `extensionContext`-Aufrufe.
enum AutoFillErgebnis: Equatable, Sendable {
    case passwort(benutzer: String, passwort: String)
    case code(String)
    case gespeichert
    case konfigurationFertig
    case abgebrochen
    /// Das Konto der Anfrage gibt es im Tresor nicht (mehr).
    case nichtGefunden
    case fehlgeschlagen
    /// Nur ohne Blatt: das Konto lässt sich nicht ohne Face ID oder Rückfrage liefern (Fenster zu, Host passt nicht), also soll iOS das Blatt zeigen.
    case abfrageNoetig
}

/// Was das System von der Erweiterung will.
enum AutoFillAuftrag: Equatable, Sendable {
    /// Liste zum Auswählen. `codes`: Einmalcodes statt Passwörter.
    case liste(hosts: [String], codes: Bool)
    /// Genau dieses Konto (aus der Vorschlagsleiste) mit Face ID liefern. `host`: die Domain der Identität, die iOS gewählt hat (zum Gegenprüfen).
    case anfrage(id: String, codes: Bool, host: String? = nil)
    case speichern(SpeicherAnfrage)
    case konfiguration
}

/// Die Angaben aus `ASSavePasswordRequest`. `sofort`: der Nutzer hat ausdrücklich "Sichern" gewählt, dann entfällt die zweite Bestätigung.
struct SpeicherAnfrage: Equatable, Sendable {
    let host: String?
    let name: String
    let benutzer: String
    let passwort: String
    let sofort: Bool
}

/// Zustand und Ablauf der Erweiterungs-Oberfläche. Ohne UIKit und ohne `AuthenticationServices`-Anfragen, damit der Ablauf in CI testbar ist.
@MainActor @Observable
final class AutoFillModell {
    enum Phase: Equatable {
        case start
        case entsperren(fehler: String?)
        case arbeitet
        case liste
        case bestaetigen(SpeicherAktion)
        case konfiguration
        /// Das gewählte Konto gehört nicht zur Seite (Phishing-Schutz): erst nach Bestätigung ausfüllen.
        case fremdesKonto(Eintrag, seite: String)
    }

    /// Passt ein Konto zur Seite, die ausgefüllt werden soll?
    enum Passung: Equatable {
        case passt
        /// Kein Host des Kontos passt zur Seite `seite` (`EintragSuche.passt`, mit Punktgrenze: `evilsparkasse.de` passt nicht zu `sparkasse.de`).
        case fremd(seite: String)
        /// Die Anfrage nennt keine Domain (z. B. eine App): nichts zu vergleichen.
        case unbekannt
    }

    static func passung(_ e: Eintrag, hosts: [String]) -> Passung {
        guard let seite = hosts.first else { return .unbekannt }
        let eintragHosts = EintragSuche.hosts(von: e)
        let passt = hosts.contains { a in eintragHosts.contains { EintragSuche.passt(eintragHost: $0, anfrageHost: a) } }
        return passt ? .passt : .fremd(seite: seite)
    }

    let auftrag: AutoFillAuftrag
    private(set) var phase: Phase = .start
    var suche = ""

    /// Host der Seite, von der das Passwort zum Speichern kommt (für den Hinweis im Aktualisieren-Dialog).
    var anfrageHost: String? {
        if case .speichern(let a) = auftrag { return a.host }
        return nil
    }

    private let sitzung: AutoFillSitzung?
    private let startFehler: String?
    private let jetzt: @Sendable () -> Date
    private let einstellungen: GeteilteEinstellungen
    private let nutzung: Nutzung
    private let warten: @Sendable (Duration) async -> Void
    /// Legt den Code des Kontos in die Zwischenablage (`CodeAblage`); Tests setzen eine Attrappe.
    var zwischenablage: @MainActor (String) -> Void = { CodeAblage.kopiere($0) }
    private var gestartet = false
    private var ohneAbfrage = false
    /// Wie oft ein "-25308" still nachgeholt wird, bevor der Knopf "Entsperren" erscheint.
    static let nachholVersuche = 3
    /// Vom View Controller gesetzt; ruft am Ende genau einmal.
    var abschluss: (AutoFillErgebnis) -> Void = { _ in }
    private var beendet = false

    init(auftrag: AutoFillAuftrag, sitzung: AutoFillSitzung?, startFehler: String? = nil, jetzt: @escaping @Sendable () -> Date = { Date() },
         einstellungen: GeteilteEinstellungen = GeteilteEinstellungen(), nutzung: Nutzung = Nutzung(),
         warten: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.auftrag = auftrag
        self.sitzung = sitzung
        self.startFehler = startFehler
        self.jetzt = jetzt
        self.einstellungen = einstellungen
        self.nutzung = nutzung
        self.warten = warten
    }

    // MARK: Ablauf

    /// Der View Controller meldet: die Ansicht ist wirklich sichtbar (`viewDidAppear`) und der Auftrag gesetzt. Erst jetzt darf Face ID starten:
    /// vorher lehnt iOS die Abfrage mit -25308 ab. Mehrfaches Aufrufen startet nur einmal.
    func ansichtIstAktiv() async {
        guard !gestartet else { return }
        gestartet = true
        await starte()
    }

    /// Fürs Ausfüllen aus der Vorschlagsleiste ohne Blatt: nur mit offenem Entsperr-Fenster und passendem Host, sonst `abfrageNoetig`.
    func starteOhneAbfrage() async {
        guard !gestartet, case .anfrage = auftrag, let sitzung, await sitzung.entsperrenOhneAbfrage() else { return beende(.abfrageNoetig) }
        gestartet = true
        ohneAbfrage = true
        await nachDemEntsperren()
    }

    /// Erster Schritt nach dem Anzeigen. Konfiguration braucht keinen Schlüssel; alles andere beginnt mit Face ID.
    func starte() async {
        if auftrag == .konfiguration {
            phase = .konfiguration
            return
        }
        await entsperren()
    }

    func entsperren() async {
        guard !beendet, phase != .arbeitet else { return }
        guard let sitzung else {
            phase = .entsperren(fehler: startFehler ?? AutoFillFehler.keinSpeicher.nutzerText)
            return
        }
        phase = .arbeitet
        var versuche = 0
        while true {
            do {
                try await sitzung.entsperren()
                break
            } catch let fehler as SchluesselbundFehler where fehler == .entsperrenAbgebrochen {
                phase = .entsperren(fehler: nil)
                return
            } catch let fehler as SchluesselbundFehler where fehler == .abfrageNochNichtMoeglich {
                // -25308: iOS lässt die Abfrage noch nicht zu. Nie zeigen, still nachholen; bleibt es, erscheint der Knopf ohne Fehlertext.
                versuche += 1
                guard versuche <= Self.nachholVersuche else {
                    phase = .entsperren(fehler: nil)
                    return
                }
                await warten(.milliseconds(300))
            } catch {
                phase = .entsperren(fehler: FehlerText.von(error))
                return
            }
        }
        await nachDemEntsperren()
    }

    private func nachDemEntsperren() async {
        guard let tresor = sitzung?.tresor else { return }
        switch auftrag {
        case .liste:
            phase = .liste
        case .anfrage(let id, let codes, let host):
            guard let e = tresor.lebendige.first(where: { $0.id == id && $0.art == Eintrag.artLogin }) else { return beende(.nichtGefunden) }
            pruefeUndFuelle(e, codes: codes, hosts: host.map { [$0] } ?? [])
        case .speichern(let a):
            guard !a.passwort.isEmpty else { return beende(.fehlgeschlagen) }
            let aktion = PasswortSpeichern.plane(in: tresor, host: a.host, name: a.name, benutzer: a.benutzer, passwort: a.passwort, jetzt: jetzt())
            switch aktion {
            case .vorhanden: beende(.gespeichert)
            case .neu where a.sofort: await speichere(aktion)
            default: phase = .bestaetigen(aktion)
            }
        case .konfiguration:
            phase = .konfiguration
        }
    }

    /// Der Nutzer bestätigt das Speichern.
    func bestaetigeSpeichern() async {
        guard !beendet, case .bestaetigen(let aktion) = phase else { return }
        await speichere(aktion)
    }

    private func speichere(_ aktion: SpeicherAktion) async {
        guard !beendet else { return }
        guard let sitzung else { return beende(.fehlgeschlagen) }
        phase = .arbeitet
        do {
            try await sitzung.speichere(aktion)
            beende(.gespeichert)
        } catch {
            beende(.fehlgeschlagen)
        }
    }

    /// Eine Zeile der Liste wurde gewählt.
    func waehle(_ eintrag: Eintrag) {
        guard case .liste(let hosts, let codes) = auftrag else { return }
        pruefeUndFuelle(eintrag, codes: codes, hosts: hosts)
    }

    /// Phishing-Schutz: Passt kein Host des Kontos zur Seite, füllt Heim nie von selbst. Mit Blatt fragt es erst nach, ohne Blatt verlangt es das Blatt.
    private func pruefeUndFuelle(_ e: Eintrag, codes: Bool, hosts: [String]) {
        switch Self.passung(e, hosts: hosts) {
        case .passt: fuelle(e, codes: codes, passend: true)
        case .unbekannt: if ohneAbfrage { beende(.abfrageNoetig) } else { fuelle(e, codes: codes, passend: false) }
        case .fremd(let seite): if ohneAbfrage { beende(.abfrageNoetig) } else { phase = .fremdesKonto(e, seite: seite) }
        }
    }

    /// Ausfüllen, Nutzung merken (W-020) und, nur nach einem Passwort auf passendem Host, den Code des Kontos in die Zwischenablage legen.
    private func fuelle(_ e: Eintrag, codes: Bool, passend: Bool) {
        guard !beendet else { return }
        guard let ergebnis = Self.ergebnis(fuer: e, codes: codes, datum: jetzt()) else { return beende(.nichtGefunden) }
        nutzung.merke(id: e.id, jetzt: jetzt())
        if passend, !codes, einstellungen.codeKopieren, let z = TOTPAnzeige.zustand(e.totp, datum: jetzt()) { zwischenablage(z.code) }
        beende(ergebnis)
    }

    /// "Trotzdem ausfüllen" auf der Rückfrage zum fremden Konto. Der Code geht dann nie in die Zwischenablage.
    func bestaetigeFremdes() {
        guard case .fremdesKonto(let e, _) = phase else { return }
        switch auftrag {
        case .liste(_, let codes), .anfrage(_, let codes, _): fuelle(e, codes: codes, passend: false)
        default: break
        }
    }

    /// "Abbrechen" auf der Rückfrage: zurück zur Liste, sonst ganz abbrechen.
    func lehneFremdesAb() {
        if case .liste = auftrag { phase = .liste } else { abbrechen() }
    }

    func abbrechen() {
        beende(.abgebrochen)
    }

    func fertigKonfiguration() {
        beende(.konfigurationFertig)
    }

    private func beende(_ ergebnis: AutoFillErgebnis) {
        guard !beendet else { return }
        beendet = true
        abschluss(ergebnis)
    }

    // MARK: Liste

    /// Konten für die Liste: zuerst die zur Domain passenden, dann alle übrigen; bei Einmalcodes nur Konten mit lesbarem TOTP. Mit Suchbegriff gefiltert.
    var gruppen: (passend: [Eintrag], uebrige: [Eintrag]) {
        guard case .liste(let hosts, let codes) = auftrag, let tresor = sitzung?.tresor else { return ([], []) }
        let teile = EintragSuche.aufteilen(tresor.eintraege, anfrageHosts: hosts)
        func auswahl(_ l: [Eintrag]) -> [Eintrag] {
            let mitCode = codes ? l.filter { TOTP.einstellung(aus: $0.totp) != nil } : l
            return EintragSuche.filtern(mitCode, begriff: suche)
        }
        return (auswahl(teile.passend), auswahl(teile.uebrige))
    }

    /// Passwort oder aktueller Einmalcode für den Eintrag; nil bei Einmalcode ohne lesbares TOTP.
    static func ergebnis(fuer e: Eintrag, codes: Bool, datum: Date) -> AutoFillErgebnis? {
        if codes {
            guard let z = TOTPAnzeige.zustand(e.totp, datum: datum) else { return nil }
            return .code(z.code)
        }
        return .passwort(benutzer: e.benutzer, passwort: e.passwort)
    }
}
