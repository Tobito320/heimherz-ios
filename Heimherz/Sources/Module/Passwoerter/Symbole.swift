import CryptoKit
import Foundation
import Observation
import SwiftUI
import UIKit

/// Der Cache der Webseiten-Symbole: eine Datei je Host, benannt nach dem SHA-256 des Hosts (kein Klartext-Name auf der Platte).
/// Ein Treffer gilt 30 Tage, "kein Symbol" auch. Liegt in der App-Gruppe, damit er Neustarts übersteht; er enthält nur öffentliche Bilder der Seiten.
struct SymbolCache: Sendable {
    enum Treffer: Equatable, Sendable {
        case bild(Data)
        case keins
    }

    static let tage = 30

    let ordner: URL

    private func datei(_ host: String, endung: String) -> URL {
        let hash = SHA256.hash(data: Data(host.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return ordner.appendingPathComponent(hash + "." + endung)
    }

    private func frisch(_ url: URL, jetzt: Date) -> Bool {
        guard let wann = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
        return jetzt.timeIntervalSince(wann) < Double(Self.tage) * 86_400
    }

    func lies(_ host: String, jetzt: Date = Date()) -> Treffer? {
        let bild = datei(host, endung: "bild")
        if frisch(bild, jetzt: jetzt), let d = try? Data(contentsOf: bild) { return .bild(d) }
        if frisch(datei(host, endung: "keins"), jetzt: jetzt) { return .keins }
        return nil
    }

    func schreibe(_ host: String, _ treffer: Treffer) {
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        switch treffer {
        case .bild(let d):
            try? d.write(to: datei(host, endung: "bild"), options: .atomic)
            try? FileManager.default.removeItem(at: datei(host, endung: "keins"))
        case .keins:
            try? Data().write(to: datei(host, endung: "keins"), options: .atomic)
            try? FileManager.default.removeItem(at: datei(host, endung: "bild"))
        }
    }

    /// Im Ordner der App-Gruppe, sonst (Tests, kein Zugriff) im Caches-Ordner.
    static func standard() -> SymbolCache {
        let wurzel = Kennungen.gruppenOrdner() ?? URL.cachesDirectory
        return SymbolCache(ordner: wurzel.appendingPathComponent("symbole", isDirectory: true))
    }
}

/// Holt Symbole vom PC (`GET /v1/symbol`) und hält sie im Speicher. Die Zeile zeigt sofort die graue Buchstaben-Kachel; kommt das Bild, wird sie ersetzt.
/// Nur sichtbare Zeilen fragen an (`SymbolKachel` lädt per `.task`), höchstens `parallel` gleichzeitig, jeder Host einmal je Sitzung.
@MainActor @Observable
final class SymbolLader {
    private(set) var bilder: [String: UIImage] = [:]

    private let cache: SymbolCache?
    private let holen: (@Sendable (String) async throws -> Data?)?
    @ObservationIgnored private var versucht = Set<String>()
    @ObservationIgnored private var laufend = 0
    @ObservationIgnored private var wartende: [CheckedContinuation<Void, Never>] = []
    private let parallel = 6

    /// Ohne `holen` und `cache` (Demo, Tests ohne Netz) bleibt es bei den Buchstaben-Kacheln.
    init(cache: SymbolCache? = nil, holen: (@Sendable (String) async throws -> Data?)? = nil) {
        self.cache = cache
        self.holen = holen
    }

    func bild(fuer host: String) -> UIImage? { bilder[host] }

    func lade(_ host: String) async {
        guard bilder[host] == nil, !versucht.contains(host), cache != nil || holen != nil else { return }
        versucht.insert(host)
        if let cache, let treffer = await Self.leseCache(cache, host) {
            if case .bild(let d) = treffer, let b = UIImage(data: d) { bilder[host] = b }
            return
        }
        guard let holen else { return }
        await platz()
        defer { freigeben() }
        let daten: Data?
        do {
            daten = try await holen(host)
        } catch {
            versucht.remove(host)   // Netz oder PC weg: beim nächsten Erscheinen der Zeile wieder versuchen, ohne es zu speichern
            return
        }
        if let d = daten, let b = UIImage(data: d) {
            bilder[host] = b
            cache?.schreibe(host, .bild(d))
        } else {
            cache?.schreibe(host, .keins)
        }
    }

    @concurrent
    private static func leseCache(_ cache: SymbolCache, _ host: String) async -> SymbolCache.Treffer? {
        cache.lies(host)
    }

    private func platz() async {
        if laufend < parallel {
            laufend += 1
            return
        }
        await withCheckedContinuation { wartende.append($0) }
    }

    private func freigeben() {
        if wartende.isEmpty { laufend -= 1 } else { wartende.removeFirst().resume() }
    }
}

extension SymbolLader {
    /// Mit dem PC aus der Umgebung verbunden: Anfragen gehen an `GET /v1/symbol`.
    static func verbunden(mit umgebung: AppUmgebung) -> SymbolLader {
        if umgebung.istDemo { return SymbolLader() }
        let sitzung = umgebung.sitzung
        let bund = umgebung.bund
        return SymbolLader(cache: .standard()) { host in
            try await HeimClient.aus(bund, sitzung: sitzung).symbolHolen(host: host)
        }
    }
}

/// Das Symbol einer Zeile: das Bild der Seite, sonst die graue Kachel mit dem Anfangsbuchstaben (wie in der Passwörter-App von Apple).
struct SymbolKachel: View {
    let eintrag: Eintrag
    var groesse: CGFloat = 40

    @Environment(SymbolLader.self) private var symbole

    private var host: String? {
        eintrag.art == Eintrag.artLogin ? EintragSuche.hosts(von: eintrag).first : nil
    }

    /// Der Buchstabe aus A bis Z, sonst das erste Zeichen des Namens (Ziffer, Zeichen), sonst ein Fragezeichen.
    private var anzeigeBuchstabe: String {
        let b = PasswoerterLogik.buchstabe(eintrag.name)
        if b != "#" { return b }
        let erstes = eintrag.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
        return erstes.isEmpty ? "?" : erstes
    }

    private var form: RoundedRectangle { RoundedRectangle(cornerRadius: groesse * 0.225, style: .continuous) }

    var body: some View {
        ZStack {
            if let host, let bild = symbole.bild(fuer: host) {
                form.fill(Color.white)
                Image(uiImage: bild)
                    .resizable()
                    .scaledToFit()
                    .padding(groesse * 0.06)
            } else {
                form.fill(Color(uiColor: .systemGray))
                if eintrag.art == Eintrag.artNotiz {
                    Image(systemName: "note.text").font(.system(size: groesse * 0.45)).foregroundStyle(Color.white)
                } else {
                    Text(anzeigeBuchstabe)
                        .font(.system(size: groesse * 0.62, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: groesse, height: groesse)
        .clipShape(form)
        .overlay(form.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: host) {
            if let host { await symbole.lade(host) }
        }
    }
}
