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
}

/// Was das System von der Erweiterung will.
enum AutoFillAuftrag: Equatable, Sendable {
    /// Liste zum Auswählen. `codes`: Einmalcodes statt Passwörter.
    case liste(hosts: [String], codes: Bool)
    /// Genau dieses Konto (aus der Vorschlagsleiste) mit Face ID liefern.
    case anfrage(id: String, codes: Bool)
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
    }

    let auftrag: AutoFillAuftrag
    private(set) var phase: Phase = .start
    var suche = ""

    private let sitzung: AutoFillSitzung?
    private let startFehler: String?
    private let jetzt: @Sendable () -> Date
    /// Vom View Controller gesetzt; ruft am Ende genau einmal.
    var abschluss: (AutoFillErgebnis) -> Void = { _ in }
    private var beendet = false

    init(auftrag: AutoFillAuftrag, sitzung: AutoFillSitzung?, startFehler: String? = nil, jetzt: @escaping @Sendable () -> Date = { Date() }) {
        self.auftrag = auftrag
        self.sitzung = sitzung
        self.startFehler = startFehler
        self.jetzt = jetzt
    }

    // MARK: Ablauf

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
        do {
            try await sitzung.entsperren()
        } catch let fehler as SchluesselbundFehler where fehler == .entsperrenAbgebrochen {
            phase = .entsperren(fehler: nil)
            return
        } catch {
            phase = .entsperren(fehler: FehlerText.von(error))
            return
        }
        await nachDemEntsperren()
    }

    private func nachDemEntsperren() async {
        guard let tresor = sitzung?.tresor else { return }
        switch auftrag {
        case .liste:
            phase = .liste
        case .anfrage(let id, let codes):
            guard let e = tresor.lebendige.first(where: { $0.id == id && $0.art == Eintrag.artLogin }) else { return beende(.nichtGefunden) }
            if let ergebnis = Self.ergebnis(fuer: e, codes: codes, datum: jetzt()) { beende(ergebnis) } else { beende(.nichtGefunden) }
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
        guard case .liste(_, let codes) = auftrag else { return }
        if let ergebnis = Self.ergebnis(fuer: eintrag, codes: codes, datum: jetzt()) { beende(ergebnis) }
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
