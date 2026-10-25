import Foundation
import Observation
import SwiftUI

/// Wo ein neuer Code (W-028) ankommt: der Link kommt von iOS (`onOpenURL`, "Codes konfigurieren in"), vom Scanner in den Einstellungen oder
/// aus dem Formular. Er liegt nur im Speicher, bis der Tresor offen ist (also nach Face ID oder im Entsperr-Fenster), und wird genau einmal herausgegeben.
/// Das Geheimnis kommt nie in ein Log, nie in UserDefaults, nie in die Zwischenablage.
@MainActor @Observable
final class CodePostfach {
    static let geteilt = CodePostfach()
    /// So lange darf ein angenommener Code auf das Entsperren warten; danach ist er weg (wie beim Import).
    static let wartezeit: TimeInterval = 300

    private(set) var konto: OtpKonto?
    private(set) var fehler: String?
    @ObservationIgnored private var von = Date.distantPast

    init() {}

    /// Es gibt etwas zu zeigen: einen Code zum Einrichten oder eine Fehlermeldung.
    var wartet: Bool { konto != nil || fehler != nil }

    /// Nur `otpauth://`: alles andere (etwa ein künftiger Koppel-Link) geht diesen Weg nichts an.
    static func istCodeLink(_ url: URL) -> Bool { url.scheme?.lowercased() == "otpauth" }

    /// Liest den Text; bei Erfolg wartet der Code, sonst steht der Grund in `fehler`. Ein neuer Link ersetzt den alten.
    func empfange(text: String, jetzt: Date = Date()) {
        do {
            konto = try OtpAuth.lese(text)
            fehler = nil
            von = jetzt
        } catch let e as OtpFehler {
            konto = nil
            fehler = e.nutzerText
        } catch {
            konto = nil
            fehler = OtpFehler.keinLink.nutzerText
        }
    }

    /// Gibt den Code genau einmal heraus.
    func nimm(jetzt: Date = Date()) -> OtpKonto? {
        defer { konto = nil }
        guard let konto else { return nil }
        guard jetzt.timeIntervalSince(von) <= Self.wartezeit else {
            fehler = "Der Code hat zu lange gewartet und wurde verworfen. Öffne den Link oder den QR-Code noch einmal."
            return nil
        }
        return konto
    }

    func zeigeFehler(_ text: String) { fehler = text }
    func schliesseFehler() { fehler = nil }
    func verwerfe() { konto = nil }
}

extension View {
    /// Nimmt `otpauth://`-Links an (project.yml: `CFBundleURLTypes`). Das Geheimnis steckt im Link und wird nirgends ausgegeben.
    func heimherzCodeAnnahme() -> some View {
        onOpenURL { url in
            Task { @MainActor in
                guard CodePostfach.istCodeLink(url) else { return }
                CodePostfach.geteilt.empfange(text: url.absoluteString)
            }
        }
    }
}

/// Welche vorhandenen Einträge zu einem neuen Code passen. Rein, ohne Oberfläche.
enum CodeZuordnung {
    /// Kleingeschrieben, ohne Akzente, nur Buchstaben und Ziffern: `Online-Bank` und `online bank` sind gleich.
    static func normal(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    /// Der Teil vor der Endung: `github` aus `login.github.com`. shortcut: bei `co.uk`-Endungen liefert das `co`, dann greift nur der Name.
    private static func hauptteil(_ host: String) -> String {
        let teile = host.split(separator: ".").map(String.init)
        return teile.count >= 2 ? teile[teile.count - 2] : (teile.first ?? host)
    }

    /// Logins, die zu Anbieter und Konto des Codes passen, die besten zuerst (Gleichstand: Reihenfolge nach Name).
    /// Der Anbieter muss passen (gleicher Host, gleicher Name, Name oder Host im Anbieter enthalten oder umgekehrt); passt auch der Benutzer zum Konto, steht der Eintrag weiter oben.
    /// Nur der Benutzer reicht allein, wenn der Link gar keinen Anbieter nennt. Einträge mit Code sind dabei, der Aufrufer fragt dann vor dem Ersetzen.
    static func vorschlaege(fuer k: OtpKonto, in eintraege: [Eintrag]) -> [Eintrag] {
        let anbieter = normal(k.issuer)
        let anbieterHost = k.issuer.contains(".") && !k.issuer.contains(where: \.isWhitespace) ? EintragSuche.host(von: k.issuer) : nil
        let konto = k.konto.trimmingCharacters(in: .whitespaces).lowercased()
        var treffer: [(eintrag: Eintrag, punkte: Int)] = []
        for e in EintragSuche.logins(in: eintraege) {
            let hosts = EintragSuche.hosts(von: e)
            var punkte = 0
            if let anbieterHost, hosts.contains(where: { EintragSuche.passt(eintragHost: $0, anfrageHost: anbieterHost) }) {
                punkte = 3
            } else if anbieter.count >= 2 {
                let name = normal(e.name)
                let haupt = hosts.map(hauptteil).map(normal)
                if name == anbieter || haupt.contains(anbieter) {
                    punkte = 3
                } else if anbieter.count >= 3, (name.count >= 3 && (name.contains(anbieter) || anbieter.contains(name)))
                            || haupt.contains(where: { $0.count >= 3 && ($0.contains(anbieter) || anbieter.contains($0)) }) {
                    punkte = 1
                }
            }
            if !konto.isEmpty, e.benutzer.lowercased() == konto, punkte > 0 || anbieter.isEmpty { punkte += 2 }
            if punkte > 0 { treffer.append((e, punkte)) }
        }
        // `sorted` ist nicht stabil: die Reihenfolge nach Name (aus `logins`) als zweiter Schlüssel.
        let geordnet = treffer.enumerated().sorted { a, b in
            a.element.punkte != b.element.punkte ? a.element.punkte > b.element.punkte : a.offset < b.offset
        }
        return geordnet.map { $0.element.eintrag }
    }
}

/// Was beim Einrichten mit dem Eintrag passiert: rein, damit es testbar ist. Gespeichert wird über `TresorStore.speichere`.
enum CodeEintrag {
    /// So viele alte Schlüssel bleiben am Eintrag (`totpVerlauf`, ein Feld, das der Tresor nicht kennt und das darum erhalten bleibt).
    static let verlaufMax = 5

    /// Der Eintrag mit dem neuen Code. Hatte er einen anderen, wandert der alte vorn in `totpVerlauf` (`[{totp, bis}]`, neueste zuerst).
    static func mitCode(_ e: Eintrag, konto: OtpKonto, jetzt: Date) -> Eintrag {
        var neu = e
        let uri = konto.uri
        let stempel = Zeit.iso(jetzt)
        if e.totp != uri { neu.unbekannt["totpVerlauf"] = verlauf(von: e, bis: stempel) }
        neu.totp = uri
        neu.geaendert = stempel
        return neu
    }

    /// `totpVerlauf` mit dem jetzigen Schlüssel vorn (nur wenn er einen hat), höchstens `verlaufMax`; ohne alten Schlüssel bleibt der Verlauf, wie er ist.
    static func verlauf(von e: Eintrag, bis: String) -> JSONWert? {
        let liste = e.unbekannt["totpVerlauf"]?.alsListe ?? []
        guard !e.totp.isEmpty else { return liste.isEmpty ? nil : .liste(liste) }
        let neuer: JSONWert = .objekt(["totp": .text(e.totp), "bis": .text(bis)])
        return .liste(Array(([neuer] + liste).prefix(verlaufMax)))
    }

    /// Ein neuer Eintrag: Name = Anbieter (ohne Anbieter das Konto), Benutzer = Konto, ohne Webseite (die trägt Ahmed nach).
    static func neu(konto: OtpKonto, jetzt: Date) -> Eintrag {
        let name = konto.anzeigeName.isEmpty ? "Neuer Code" : konto.anzeigeName
        return Eintrag(name: name, benutzer: konto.konto, totp: konto.uri, geaendert: Zeit.iso(jetzt))
    }
}

/// Der Ablauf des Blatts "Code einrichten": wählen (oder neu anlegen), speichern, dann den laufenden Code zeigen.
@MainActor @Observable
final class CodeEinrichten: Identifiable {
    struct Fertig: Equatable {
        let name: String
        let uri: String
    }

    let konto: OtpKonto
    private let store: TresorStore
    private let demo: Bool
    private let jetzt: @Sendable () -> Date

    private(set) var fertig: Fertig?
    private(set) var fehler: String?
    private(set) var arbeitet = false
    /// Der Eintrag, der schon einen anderen Code hat: erst nach "Ersetzen" wird geschrieben.
    var rueckfrage: Eintrag?

    init(konto: OtpKonto, store: TresorStore, demo: Bool = false, jetzt: @escaping @Sendable () -> Date = { Date() }) {
        self.konto = konto
        self.store = store
        self.demo = demo
        self.jetzt = jetzt
    }

    var vorschlaege: [Eintrag] { CodeZuordnung.vorschlaege(fuer: konto, in: store.eintraege) }
    var alleLogins: [Eintrag] { EintragSuche.logins(in: store.eintraege) }

    /// Tippen auf einen Eintrag. Hat er schon einen anderen Code, kommt erst die Rückfrage.
    func waehle(_ e: Eintrag) async {
        let aktuell = store.eintrag(e.id) ?? e
        if !aktuell.totp.isEmpty, aktuell.totp != konto.uri {
            rueckfrage = aktuell
        } else {
            await schreibe(CodeEintrag.mitCode(aktuell, konto: konto, jetzt: jetzt()))
        }
    }

    /// "Ersetzen" in der Rückfrage.
    func ersetze() async {
        guard let e = rueckfrage else { return }
        rueckfrage = nil
        await schreibe(CodeEintrag.mitCode(store.eintrag(e.id) ?? e, konto: konto, jetzt: jetzt()))
    }

    func legeNeuAn() async {
        await schreibe(CodeEintrag.neu(konto: konto, jetzt: jetzt()))
    }

    /// `speichere` meldet keinen Fehler (gesperrt oder Speichern fehlgeschlagen kehrt still zurück): darum nachsehen, ob der Code wirklich im Tresor steht.
    private func schreibe(_ e: Eintrag) async {
        guard !arbeitet, fertig == nil else { return }
        arbeitet = true
        defer { arbeitet = false }
        fehler = nil
        await store.speichere(e)
        guard demo || store.eintrag(e.id)?.totp == e.totp else {
            fehler = "Speichern hat nicht geklappt. Der Code ist noch nicht eingerichtet. Versuche es noch einmal."
            return
        }
        fertig = Fertig(name: e.name, uri: e.totp)
    }
}
