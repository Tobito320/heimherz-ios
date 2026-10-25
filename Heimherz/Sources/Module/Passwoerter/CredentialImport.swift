import Foundation

/// Import aus Apple Passwörter (Credential Exchange, iOS 26): hier nur die reine Abbildung auf Tresor-Einträge, ohne Apple-Typen und ohne Oberfläche.
/// `CredentialImportAdapter` übersetzt die Apple-Typen in diese Werte; `ImportAbbildung.einarbeiten` mischt sie in den Tresor.

/// Ein Passkey aus dem Import. Der private Schlüssel bleibt im verschlüsselten Tresor; die Erweiterung meldet damit an (`Passkeys`, SPEC 24).
struct ImportPasskey: Equatable, Sendable {
    var credentialId: String      // Base64url
    var rpId: String
    var userName: String
    var userDisplayName: String
    var userHandle: String        // Base64url
    var schluessel: String        // Base64url, privater Schlüssel (PKCS#8)

    var json: JSONWert {
        .objekt(["credentialId": .text(credentialId), "rpId": .text(rpId), "userName": .text(userName),
                 "userDisplayName": .text(userDisplayName), "userHandle": .text(userHandle), "key": .text(schluessel)])
    }
}

/// Ein Konto oder eine Notiz aus dem Import.
struct ImportKonto: Equatable, Sendable {
    var art = Eintrag.artLogin
    var titel = ""
    var benutzer = ""
    var passwort = ""
    var urls: [String] = []
    /// `otpauth://totp/…`
    var totp = ""
    var notiz = ""
    var favorit = false
    var passkeys: [ImportPasskey] = []
}

/// Das Ergebnis, nur Zahlen (kein Name, kein Passwort).
struct ImportZaehler: Equatable, Sendable {
    var neu = 0
    var aktualisiert = 0
    /// Neu gesicherte Passkeys.
    var passkeys = 0
    /// Doppelte, WLAN, Karten und alles, was Heimherz nicht kennt.
    var uebersprungen = 0

    var text: String {
        "\(neu) neu, \(aktualisiert) aktualisiert, \(passkeys) Passkeys gesichert, \(uebersprungen) übersprungen"
    }
}

enum ImportAbbildung {
    /// Mischt die Konten in den Tresor. Gleicher Host, Benutzer und Passwort: überspringen. Gleicher Host und Benutzer, anderes Passwort:
    /// der bestehende Eintrag bekommt das neue Passwort (Apple ist die neuere Quelle), das alte wandert in `passwortVerlauf`.
    /// Passkeys kommen als unbekanntes Feld `passkeys` an den Eintrag. `uebersprungenVorher` sind Dinge, die schon der Adapter aussortiert hat.
    static func einarbeiten(_ tresor: Tresor, _ konten: [ImportKonto], uebersprungenVorher: Int = 0, jetzt: Date) -> (tresor: Tresor, zaehler: ImportZaehler) {
        var t = tresor
        var z = ImportZaehler(uebersprungen: uebersprungenVorher)
        let stempel = Zeit.iso(jetzt)
        for k in konten {
            if k.art == Eintrag.artNotiz {
                if t.eintraege.contains(where: { !$0.geloescht && $0.art == Eintrag.artNotiz && $0.name == k.titel && $0.notiz == k.notiz }) {
                    z.uebersprungen += 1
                } else {
                    t.eintraege.append(Eintrag(art: Eintrag.artNotiz, name: k.titel, notiz: k.notiz, favorit: k.favorit, geaendert: stempel))
                    z.neu += 1
                }
                continue
            }
            if let i = vorhandener(in: t, fuer: k) {
                var e = t.eintraege[i]
                var inhaltNeu = false
                if !k.passwort.isEmpty, e.passwort != k.passwort {
                    e.unbekannt["passwortVerlauf"] = PasswortSpeichern.verlauf(von: e, bis: stempel)
                    e.passwort = k.passwort
                    inhaltNeu = true
                }
                if e.totp.isEmpty, !k.totp.isEmpty {
                    e.totp = k.totp
                    inhaltNeu = true
                }
                if e.notiz.isEmpty, !k.notiz.isEmpty {
                    e.notiz = k.notiz
                    inhaltNeu = true
                }
                let bekannteHosts = Set(EintragSuche.hosts(von: e))
                for u in k.urls where EintragSuche.host(von: u).map({ !bekannteHosts.contains($0) }) ?? false {
                    e.urls.append(u)
                    inhaltNeu = true
                }
                let neue = neuePasskeys(k.passkeys, an: e)
                if !neue.isEmpty {
                    e.unbekannt["passkeys"] = .liste((e.unbekannt["passkeys"]?.alsListe ?? []) + neue.map(\.json))
                    z.passkeys += neue.count
                }
                if inhaltNeu || !neue.isEmpty {
                    e.geaendert = stempel
                    t.eintraege[i] = e
                    if inhaltNeu { z.aktualisiert += 1 }
                } else {
                    z.uebersprungen += 1
                }
            } else {
                var e = Eintrag(name: name(fuer: k), benutzer: k.benutzer, passwort: k.passwort, urls: urls(fuer: k), totp: k.totp, notiz: k.notiz,
                                favorit: k.favorit, geaendert: stempel)
                if !k.passkeys.isEmpty {
                    e.unbekannt["passkeys"] = .liste(k.passkeys.map(\.json))
                    z.passkeys += k.passkeys.count
                }
                t.eintraege.append(e)
                z.neu += 1
            }
        }
        return (t, z)
    }

    /// Das lebende Login mit gleichem Benutzer (ohne Groß/Klein) und mindestens einem gleichen Host; ohne Hosts auf beiden Seiten zählt der Name.
    /// Bei mehreren Treffern der zuletzt geänderte.
    private static func vorhandener(in t: Tresor, fuer k: ImportKonto) -> Int? {
        let kHosts = Set(urls(fuer: k).compactMap(EintragSuche.host(von:)))
        let treffer = t.eintraege.indices.filter { i in
            let e = t.eintraege[i]
            guard !e.geloescht, e.art == Eintrag.artLogin, e.benutzer.caseInsensitiveCompare(k.benutzer) == .orderedSame else { return false }
            let eHosts = Set(EintragSuche.hosts(von: e))
            if kHosts.isEmpty || eHosts.isEmpty { return kHosts.isEmpty && eHosts.isEmpty && e.name == name(fuer: k) }
            return !kHosts.isDisjoint(with: eHosts)
        }
        return treffer.max { (Zeit.millis(iso: t.eintraege[$0].geaendert) ?? 0) < (Zeit.millis(iso: t.eintraege[$1].geaendert) ?? 0) }
    }

    /// Die Adressen des Kontos; ein reiner Passkey ohne Adresse bekommt seine Seite als Adresse (so findet ihn die Suche).
    private static func urls(fuer k: ImportKonto) -> [String] {
        if !k.urls.isEmpty { return k.urls }
        return k.passkeys.map(\.rpId).filter { !$0.isEmpty }.prefix(1).map { "https://" + $0 }
    }

    private static func name(fuer k: ImportKonto) -> String {
        let t = k.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return urls(fuer: k).compactMap(EintragSuche.host(von:)).first ?? "Konto"
    }

    private static func neuePasskeys(_ passkeys: [ImportPasskey], an e: Eintrag) -> [ImportPasskey] {
        var da = Set<String>()
        for feld in ["passkeys", "bitwardenFido2"] {
            for w in e.unbekannt[feld]?.alsListe ?? [] {
                if case .objekt(let d) = w, let id = d["credentialId"]?.alsText { da.insert(id) }
            }
        }
        var gesehen = da
        return passkeys.filter { gesehen.insert($0.credentialId).inserted }
    }

    // MARK: Einmalcode

    /// Aus dem rohen Geheimnis wird die `otpauth://`-URI, die der Tresor überall liest (Detail, Codes, AutoFill, Export nach Bitwarden).
    static func totpURI(geheim: Data, periode: Int, stellen: Int, algorithmus: String, aussteller: String?, benutzer: String?) -> String {
        func kodiere(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .heimherzUnreserviert) ?? s }
        let a = (aussteller ?? "").trimmingCharacters(in: .whitespaces), b = (benutzer ?? "").trimmingCharacters(in: .whitespaces)
        let label = [a, b].filter { !$0.isEmpty }.map(kodiere).joined(separator: ":")
        var teile = ["secret=\(base32Text(geheim))"]
        if !a.isEmpty { teile.append("issuer=\(kodiere(a))") }
        teile.append("algorithm=\(algorithmus.uppercased())")
        teile.append("digits=\(stellen)")
        teile.append("period=\(periode)")
        return "otpauth://totp/\(label)?" + teile.joined(separator: "&")
    }

    static func base32Text(_ daten: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var aus = ""
        var puffer = 0
        var bits = 0
        for byte in daten {
            puffer = (puffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                aus.append(alphabet[(puffer >> bits) & 31])
            }
            puffer &= (1 << bits) - 1
        }
        if bits > 0 { aus.append(alphabet[(puffer << (5 - bits)) & 31]) }
        return aus
    }

    static func base64url(_ daten: Data) -> String {
        daten.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
