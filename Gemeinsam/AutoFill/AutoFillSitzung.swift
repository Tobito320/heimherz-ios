import CryptoKit
import Foundation
import LocalAuthentication
import Observation

enum AutoFillFehler: Error, Equatable, LocalizedError {
    case nichtGekoppelt
    case keinSpeicher

    var nutzerText: String {
        switch self {
        case .nichtGekoppelt: return "Heimherz ist noch nicht mit dem PC gekoppelt. Öffne die App und koppel das Handy."
        case .keinSpeicher: return "Heimherz kann seinen Tresor nicht finden. Bitte die App einmal öffnen."
        }
    }

    var errorDescription: String? { nutzerText }
}

/// Der Satz für den Nutzer zu einem Fehler (alle Fehlertypen des Projekts sind `LocalizedError` mit `nutzerText`).
enum FehlerText {
    static func von(_ fehler: Error) -> String {
        (fehler as? LocalizedError)?.errorDescription ?? "Etwas ist schiefgegangen."
    }
}

/// Ein Aufruf der AutoFill-Erweiterung: Schlüssel K einmal laden (ein Face ID für den ganzen Aufruf, über einen `EntsperrKontext`),
/// den Tresor einmal aus dem verschlüsselten Cache öffnen und danach nur im Speicher halten. Geht auch ohne PC und ohne Netz.
/// Speichergrenze der Erweiterung: kein zweites Entschlüsseln, kein Foto- oder Dateicode, nur der Tresor.
@MainActor @Observable
final class AutoFillSitzung {
    private(set) var tresor: Tresor?

    private let bund: Schluesselbund
    private let dienst: TresorDienst
    private let kontext: EntsperrKontext
    private let identitaeten: @Sendable (Tresor) async -> Void
    private var schluessel: SymmetricKey?

    init(bund: Schluesselbund, ablage: TresorAblage, client: HeimClient?, kontext: EntsperrKontext = AutoFillSitzung.neuerKontext(),
         identitaeten: (@Sendable (Tresor) async -> Void)? = nil) {
        self.bund = bund
        self.dienst = TresorDienst(ablage: ablage, client: client)
        self.kontext = kontext
        self.identitaeten = identitaeten ?? Self.setzeImSystem
    }

    /// Mit dem echten Schlüsselbund und der App-Group-Ablage; wirft `keinSpeicher`, wenn es die Gruppe nicht gibt.
    static func live() throws -> AutoFillSitzung {
        guard let ablage = TresorAblage.appGruppe() else { throw AutoFillFehler.keinSpeicher }
        return AutoFillSitzung(bund: .live, ablage: ablage, client: try? HeimClient.aus(.live))
    }

    /// Der Kontext mit Text für die Face-ID-Abfrage des Schlüsselbunds.
    nonisolated static func neuerKontext() -> EntsperrKontext {
        let c = LAContext()
        c.localizedReason = "Heimherz entsperren"
        return EntsperrKontext(c)
    }

    var istEntsperrt: Bool { tresor != nil }

    /// Fragt Face ID (oder Code), lädt K und öffnet den lokalen Stand. Mehrfaches Aufrufen fragt nicht noch einmal.
    func entsperren() async throws {
        if tresor != nil { return }
        guard try bund.ladeGeraet() != nil else { throw AutoFillFehler.nichtGekoppelt }
        guard let k = try await bund.ladeSchluessel(kontext: kontext) else { throw AutoFillFehler.nichtGekoppelt }
        let lokal = try await dienst.lokal(schluessel: k) ?? Tresor()
        schluessel = k
        tresor = lokal
    }

    /// Speichert verschlüsselt im lokalen Cache und gleicht danach höchstens `sekunden` lang mit dem PC ab (Erweiterungen dürfen nicht lange laufen).
    /// Ohne PC bleibt es lokal; die App gleicht beim nächsten Öffnen ab.
    func speichere(_ aktion: SpeicherAktion, abgleichSekunden sekunden: Double = 6) async throws {
        guard let k = schluessel, let alt = tresor else { throw AutoFillFehler.nichtGekoppelt }
        let neu = PasswortSpeichern.anwenden(aktion, auf: alt)
        guard neu != alt else { return }
        try await dienst.speichereLokal(neu, schluessel: k)
        tresor = neu
        let dienst = self.dienst
        await withTaskGroup(of: Void.self) { gruppe in
            gruppe.addTask { _ = try? await dienst.abgleichen(lokal: neu, schluessel: k) }
            gruppe.addTask { try? await Task.sleep(for: .seconds(sekunden)) }
            _ = await gruppe.next()
            gruppe.cancelAll()
        }
        // Nach dem Abgleich kann der Stand am PC größer sein; die Identitäten kennen jedoch immer mindestens den lokalen.
        await identitaeten(neu)
    }

    private nonisolated static func setzeImSystem(_ tresor: Tresor) async {
        _ = await AutoFillIdentitaeten.setze(tresor)
    }
}
