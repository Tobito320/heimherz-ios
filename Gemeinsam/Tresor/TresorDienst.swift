import CryptoKit
import Foundation

enum AbgleichErgebnis: Sendable, Equatable {
    /// Lokaler und Server-Stand sind zusammengeführt, der Server hat die Fassung `rev`.
    case abgeglichen(Tresor, rev: Int)
    /// Der PC war nicht erreichbar: der Stand liegt verschlüsselt nur lokal und geht beim nächsten Abgleich hoch.
    case nurLokal(Tresor, grund: HeimFehler)
}

/// Der Abgleich-Ablauf (SPEC 9): holen, öffnen, mit dem lokalen Stand zusammenführen, verschließen, `PUT If-Match`.
/// Bei 409 (`rev` zwischendurch geändert) mit dem Stand des Servers nochmal, höchstens 3 Versuche. Ohne Netz bleibt alles lokal.
/// Das ist die eine Stelle, die App (Passwörter-Modul) und AutoFill-Erweiterung benutzen. Der Klartext lebt nur im Speicher der Aufrufer.
actor TresorDienst {
    static let maxVersuche = 3

    private let ablage: TresorAblage
    private let client: HeimClient?
    private let jetzt: @Sendable () -> Date

    /// `client` nil = nicht gekoppelt (nur lokal arbeiten).
    init(ablage: TresorAblage, client: HeimClient?, jetzt: @escaping @Sendable () -> Date = { Date() }) {
        self.ablage = ablage
        self.client = client
        self.jetzt = jetzt
    }

    /// Der lokale Stand, ohne Netz. nil, wenn noch nichts gespeichert wurde.
    func lokal(schluessel: SymmetricKey) throws -> Tresor? {
        try ablage.lade()?.oeffne(schluessel: schluessel)
    }

    /// Verschlüsselt den Stand in die Ablage (ohne Netz). `rev` bleibt die zuletzt bekannte des Servers.
    /// Liest die Datei direkt vorher neu und führt sie mit `tresor` zusammen: App und Erweiterung schreiben dieselbe Datei und überschreiben sich so nie.
    /// Gibt den Stand zurück, der jetzt in der Datei liegt (Aufrufer sollen mit ihm weiterarbeiten).
    @discardableResult
    func speichereLokal(_ tresor: Tresor, schluessel: SymmetricKey) throws -> Tresor {
        let datei = try ablage.lade()
        var stand = tresor
        if let datei { stand = Zusammenfuehren.zusammenfuehren(tresor, try datei.oeffne(schluessel: schluessel), jetzt: jetzt()) }
        try ablage.speichere(Umschlag.verschliesse(stand, schluessel: schluessel, rev: datei?.rev ?? 0))
        return stand
    }

    /// Legt den Stand, den der Server jetzt hat, in die Ablage. Hat die andere Seite (App oder Erweiterung) währenddessen etwas Neues in die Datei
    /// gelegt, bleibt das erhalten (dann liegt eine neu verschlüsselte Fassung mit der neuen `rev` dort, die der nächste Abgleich hochschickt).
    private func uebernimmServerStand(_ umschlag: Umschlag, tresor: Tresor, schluessel: SymmetricKey) throws -> Tresor {
        if let datei = try? ablage.lade()?.oeffne(schluessel: schluessel) {
            let stand = Zusammenfuehren.zusammenfuehren(tresor, datei, jetzt: jetzt())
            if stand != tresor {
                try ablage.speichere(Umschlag.verschliesse(stand, schluessel: schluessel, rev: umschlag.rev))
                return stand
            }
        }
        try ablage.speichere(umschlag)
        return tresor
    }

    /// Gleicht `lokal` (der aktuelle Stand des Aufrufers, auch mit ungesendeten Änderungen) mit dem Server ab.
    /// Wirft bei falschem Schlüssel (`TresorFehler`), 401 usw.; nur Netzprobleme enden in `.nurLokal`.
    func abgleichen(lokal: Tresor, schluessel: SymmetricKey) async throws -> AbgleichErgebnis {
        guard let client else {
            return .nurLokal(try speichereLokal(lokal, schluessel: schluessel), grund: .nichtGekoppelt)
        }
        let start = jetzt()
        var stand = lokal
        do {
            var remote = try await client.tresorHolen()
            for _ in 0..<Self.maxVersuche {
                let serverTresor = try remote?.oeffne(schluessel: schluessel)
                let zusammen = serverTresor.map { Zusammenfuehren.zusammenfuehren(stand, $0, jetzt: jetzt()) } ?? stand
                stand = zusammen
                // Nichts Neues für den Server: keine neue Fassung anlegen (der Verlauf behält nur die letzten 200).
                if let remote, let serverTresor, zusammen == serverTresor {
                    let abgelegt = try uebernimmServerStand(remote, tresor: zusammen, schluessel: schluessel)
                    ablage.markiereAbgeglichen(start)
                    return .abgeglichen(abgelegt, rev: remote.rev)
                }
                let neu = try Umschlag.verschliesse(zusammen, schluessel: schluessel)
                switch try await client.tresorSchreiben(neu, ifMatch: remote?.rev ?? 0) {
                case .gespeichert(let gespeichert):
                    let abgelegt = try uebernimmServerStand(gespeichert, tresor: zusammen, schluessel: schluessel)
                    ablage.markiereAbgeglichen(start)
                    return .abgeglichen(abgelegt, rev: gespeichert.rev)
                case .konflikt(let aktuell):
                    if let aktuell { remote = aktuell } else { remote = try await client.tresorHolen() }
                }
            }
            throw HeimFehler.zuVieleKonflikte
        } catch let fehler as HeimFehler where fehler.istNetzproblem {
            return .nurLokal(try speichereLokal(stand, schluessel: schluessel), grund: fehler)
        }
    }
}
