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
    func speichereLokal(_ tresor: Tresor, schluessel: SymmetricKey) throws {
        let rev = try ablage.lade()?.rev ?? 0
        try ablage.speichere(Umschlag.verschliesse(tresor, schluessel: schluessel, rev: rev))
    }

    /// Gleicht `lokal` (der aktuelle Stand des Aufrufers, auch mit ungesendeten Änderungen) mit dem Server ab.
    /// Wirft bei falschem Schlüssel (`TresorFehler`), 401 usw.; nur Netzprobleme enden in `.nurLokal`.
    func abgleichen(lokal: Tresor, schluessel: SymmetricKey) async throws -> AbgleichErgebnis {
        guard let client else {
            try speichereLokal(lokal, schluessel: schluessel)
            return .nurLokal(lokal, grund: .nichtGekoppelt)
        }
        var stand = lokal
        do {
            var remote = try await client.tresorHolen()
            for _ in 0..<Self.maxVersuche {
                let serverTresor = try remote?.oeffne(schluessel: schluessel)
                let zusammen = serverTresor.map { Zusammenfuehren.zusammenfuehren(stand, $0, jetzt: jetzt()) } ?? stand
                stand = zusammen
                // Nichts Neues für den Server: keine neue Fassung anlegen (der Verlauf behält nur die letzten 200).
                if let remote, let serverTresor, zusammen == serverTresor {
                    try ablage.speichere(remote)
                    return .abgeglichen(zusammen, rev: remote.rev)
                }
                let neu = try Umschlag.verschliesse(zusammen, schluessel: schluessel)
                switch try await client.tresorSchreiben(neu, ifMatch: remote?.rev ?? 0) {
                case .gespeichert(let gespeichert):
                    try ablage.speichere(gespeichert)
                    return .abgeglichen(zusammen, rev: gespeichert.rev)
                case .konflikt(let aktuell):
                    if let aktuell { remote = aktuell } else { remote = try await client.tresorHolen() }
                }
            }
            throw HeimFehler.zuVieleKonflikte
        } catch let fehler as HeimFehler where fehler.istNetzproblem {
            try speichereLokal(stand, schluessel: schluessel)
            return .nurLokal(stand, grund: fehler)
        }
    }
}
