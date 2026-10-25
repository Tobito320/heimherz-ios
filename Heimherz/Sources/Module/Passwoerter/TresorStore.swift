import CryptoKit
import Foundation
import Observation

/// Der Klartext-Tresor der laufenden App, nur im Speicher (SPEC 9). Beim Sperren der App wird alles geleert (`sperren()`).
/// Öffnen: Schlüssel K aus dem Schlüsselbund (Face ID), lokaler Stand sofort, danach Abgleich mit dem PC.
/// Jede Änderung wird erst lokal verschlüsselt gespeichert (geht auch ohne PC nicht verloren) und dann abgeglichen.
@MainActor @Observable
final class TresorStore {
    enum Zustand: Equatable {
        case leer
        case laedt
        case bereit
        case fehler(String)
    }

    private(set) var zustand: Zustand = .leer
    private(set) var tresor: Tresor?
    /// Wann der PC zuletzt erfolgreich abgeglichen wurde (auch nach Neustart der App bekannt).
    private(set) var zuletzt: Date?
    /// Gesetzt, wenn der PC beim letzten Abgleich nicht erreichbar war: kein Fehler, die Änderungen warten.
    private(set) var offlineText: String?
    /// Ein Fehler beim Abgleich, der kein Netzproblem ist (z. B. PC kennt das Handy nicht mehr).
    private(set) var abgleichFehler: String?
    private(set) var gleichtAb = false

    private let umgebung: AppUmgebung
    private let identitaetenSetzen: @Sendable (Tresor) async -> Void
    private let jetzt: @Sendable () -> Date
    private let merker: UserDefaults
    private var schluessel: SymmetricKey?
    private var abgleichNoetig = false
    private var abgleichTask: Task<Void, Never>?
    private var identitaetenTask: Task<Void, Never>?
    /// Zählt Sperren hoch: Ergebnisse von Aufgaben, die vor einer Sperre starteten, werden verworfen (kein Klartext nach dem Sperren).
    private var sperrZaehler = 0

    static let merkerSchluessel = "heimherz.zuletztAbgeglichen"

    init(umgebung: AppUmgebung,
         identitaeten: (@Sendable (Tresor) async -> Void)? = nil,
         jetzt: @escaping @Sendable () -> Date = { Date() },
         merker: UserDefaults = .standard) {
        self.umgebung = umgebung
        self.identitaetenSetzen = identitaeten ?? Self.setzeImSystem
        self.jetzt = jetzt
        self.merker = merker
        let sekunden = merker.double(forKey: Self.merkerSchluessel)
        self.zuletzt = sekunden > 0 ? Date(timeIntervalSince1970: sekunden) : nil
    }

    // MARK: Lesen

    var eintraege: [Eintrag] { tresor?.lebendige ?? [] }

    func eintrag(_ id: String) -> Eintrag? {
        eintraege.first { $0.id == id }
    }

    // MARK: Öffnen und Sperren

    /// Lädt K (Face ID), zeigt den lokalen Stand und gleicht danach mit dem PC ab. Ohne Netz bleibt der lokale Stand.
    func oeffnen() async {
        guard zustand != .laedt else { return }
        #if DEBUG
        if umgebung.istDemo {
            tresor = Self.demoTresor
            zuletzt = jetzt()
            zustand = .bereit
            return
        }
        #endif
        guard umgebung.istGekoppelt, !umgebung.istDemo else { return }
        if schluessel == nil || tresor == nil {
            zustand = .laedt
            let zaehler = sperrZaehler
            do {
                guard let k = try await umgebung.bund.ladeSchluessel() else {
                    zustand = .fehler("Auf diesem Handy liegt kein Tresorschlüssel. Bitte neu koppeln (Tab Mehr).")
                    return
                }
                let lokal = try await umgebung.tresorDienst().lokal(schluessel: k) ?? Tresor()
                guard zaehler == sperrZaehler else { return }
                schluessel = k
                tresor = lokal
                zustand = .bereit
                aktualisiereIdentitaeten(lokal)
            } catch {
                if zaehler == sperrZaehler { zustand = .fehler(Self.text(error)) }
                return
            }
        }
        await abgleichen()
    }

    /// App gesperrt, entkoppelt oder im Hintergrund zu lange: Klartext und Schlüssel aus dem Speicher.
    func sperren() {
        sperrZaehler += 1
        abgleichTask?.cancel()
        abgleichTask = nil
        tresor = nil
        schluessel = nil
        zustand = .leer
        offlineText = nil
        abgleichFehler = nil
    }

    // MARK: Abgleich

    /// `GET` → entschlüsseln → zusammenführen → `PUT` über den `TresorDienst`. Läuft schon einer, wird danach noch einmal abgeglichen.
    func abgleichen() async {
        guard schluessel != nil, tresor != nil else { return }
        if gleichtAb {
            abgleichNoetig = true
            return
        }
        gleichtAb = true
        defer { gleichtAb = false }
        repeat {
            abgleichNoetig = false
            await uebernehmeDatei()
            guard let k = schluessel, let stand = tresor else { return }
            let zaehler = sperrZaehler
            do {
                let ergebnis = try await umgebung.tresorDienst().abgleichen(lokal: stand, schluessel: k)
                guard zaehler == sperrZaehler, let aktuell = tresor else { return }   // währenddessen gesperrt
                switch ergebnis {
                case .abgeglichen(let t, _):
                    tresor = Zusammenfuehren.zusammenfuehren(aktuell, t, jetzt: jetzt())
                    offlineText = nil
                    let wann = jetzt()
                    zuletzt = wann
                    merker.set(wann.timeIntervalSince1970, forKey: Self.merkerSchluessel)
                case .nurLokal(let t, _):
                    tresor = Zusammenfuehren.zusammenfuehren(aktuell, t, jetzt: jetzt())
                    offlineText = "Der PC ist gerade nicht erreichbar. Alles geht weiter, Änderungen warten bis zum nächsten Abgleich."
                }
                abgleichFehler = nil
                if let neu = tresor { aktualisiereIdentitaeten(neu) }
            } catch {
                guard zaehler == sperrZaehler else { return }
                abgleichFehler = Self.text(error)
            }
        } while abgleichNoetig
    }

    /// Wartet auf einen im Hintergrund gestarteten Abgleich (Tests).
    func warteAufAbgleich() async {
        await abgleichTask?.value
    }

    private func starteAbgleich() {
        abgleichTask = Task { [weak self] in await self?.abgleichen() }
    }

    // MARK: Ändern

    /// Neuer oder geänderter Eintrag. Der Zeitstempel `geaendert` wird hier gesetzt.
    func speichere(_ eintrag: Eintrag) async {
        var e = eintrag
        e.geaendert = Zeit.iso(jetzt())
        await aendere { tresor in
            if let i = tresor.eintraege.firstIndex(where: { $0.id == e.id }) { tresor.eintraege[i] = e } else { tresor.eintraege.append(e) }
        }
    }

    /// Löschen als Grabstein, damit die Löschung auf allen Geräten ankommt (SPEC 5).
    func loesche(id: String) async {
        let stempel = Zeit.iso(jetzt())
        await aendere { tresor in
            if let i = tresor.eintraege.firstIndex(where: { $0.id == id }) { tresor.eintraege[i] = tresor.eintraege[i].alsGrabstein(geaendert: stempel) }
        }
    }

    func setzeFavorit(id: String, _ wert: Bool) async {
        guard var e = eintrag(id) else { return }
        e.favorit = wert
        await speichere(e)
    }

    /// Die AutoFill-Erweiterung kann den verschlüsselten Cache geändert haben, während die App offen war (neues Passwort aus Safari):
    /// vor jedem Schreiben und Abgleichen den Stand der Datei einmischen, sonst würde er überschrieben.
    private func uebernehmeDatei() async {
        guard let k = schluessel, tresor != nil else { return }
        let zaehler = sperrZaehler
        guard let datei = try? await umgebung.tresorDienst().lokal(schluessel: k), zaehler == sperrZaehler, let stand = tresor else { return }
        let gemischt = Zusammenfuehren.zusammenfuehren(stand, datei, jetzt: jetzt())
        if gemischt != stand { tresor = gemischt }
    }

    private func aendere(_ aenderung: (inout Tresor) -> Void) async {
        await uebernehmeDatei()
        guard var t = tresor, let k = schluessel else { return }
        aenderung(&t)
        tresor = t
        do {
            try await umgebung.tresorDienst().speichereLokal(t, schluessel: k)
            abgleichFehler = nil
        } catch {
            abgleichFehler = "Speichern auf dem Handy ist fehlgeschlagen: \(Self.text(error))"
            return
        }
        aktualisiereIdentitaeten(t)
        starteAbgleich()
    }

    private func aktualisiereIdentitaeten(_ t: Tresor) {
        guard !umgebung.istDemo else { return }
        let setzen = identitaetenSetzen
        let vorher = identitaetenTask
        // Nacheinander, damit ein älterer Stand nie einen neueren im System überschreibt.
        identitaetenTask = Task {
            await vorher?.value
            await setzen(t)
        }
    }

    /// Wartet, bis die Identitäten im System gesetzt sind (Tests).
    func warteAufIdentitaeten() async {
        await identitaetenTask?.value
    }

    private nonisolated static func setzeImSystem(_ tresor: Tresor) async {
        _ = await AutoFillIdentitaeten.setze(tresor)
    }

    nonisolated static func text(_ fehler: Error) -> String {
        FehlerText.von(fehler)
    }
}
