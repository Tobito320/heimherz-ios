import FileProvider
import Foundation
import UniformTypeIdentifiers

/// Datei-Anbieter "Lumen Cloud" in der Dateien-App (SPEC 31). `~/Heimherz/Dateien` am PC bleibt die Wahrheit; diese Erweiterung zeigt den Baum,
/// lädt Dateien beim Antippen und gibt Änderungen vom Handy (neu, ändern, umbenennen, verschieben, Ordner, Löschen = Papierkorb am PC) an den Dienst weiter.
/// Zugang wie die anderen Erweiterungen: Schlüsselbund und Adresse der App (`Schluesselbund.live`), keine neue Kopplung.
/// Quellen: developer.apple.com/documentation/fileprovider (NSFileProviderReplicatedExtension, NSFileProviderEnumerator, NSFileProviderError).
/// Reine Regeln (Fehlerarten, Ersatznamen, Versionen): `SyncRegeln` in `Gemeinsam/Dateien/`.

/// Apples Rückrufe und Beobachter sind nicht überall als Sendable markiert; wir rufen jeden genau einmal und nur aus der einen Aufgabe auf.
/// shortcut: `@unchecked Sendable`, nur Weitergabe in die Task; bei einem Compilerfehler nach SDK-Wechsel prüfen.
struct Rueckruf<T>: @unchecked Sendable {
    let wert: T
    init(_ wert: T) { self.wert = wert }
}

/// Ein Eintrag des PCs als Item der Dateien-App.
final class DateiPosten: NSObject, NSFileProviderItem, @unchecked Sendable {   // shortcut: nur `let`-Felder, nach dem Anlegen unveränderlich
    let eintrag: SyncEintrag
    init(_ eintrag: SyncEintrag) { self.eintrag = eintrag }

    var itemIdentifier: NSFileProviderItemIdentifier { NSFileProviderItemIdentifier(rawValue: eintrag.id) }
    var parentItemIdentifier: NSFileProviderItemIdentifier { DateienErweiterung.apple(kennung: eintrag.eltern) }
    var filename: String { eintrag.name }
    var contentType: UTType {
        if eintrag.ordner { return .folder }
        return UTType(filenameExtension: (eintrag.name as NSString).pathExtension) ?? .data
    }
    var capabilities: NSFileProviderItemCapabilities {
        if SyncRegeln.istGeschuetzt(eintrag) { return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems] }
        return eintrag.ordner
            ? [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsReparenting, .allowsDeleting]
            : [.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting, .allowsDeleting]
    }
    var documentSize: NSNumber? { eintrag.ordner ? nil : NSNumber(value: eintrag.groesse) }
    var contentModificationDate: Date? { eintrag.datum }
    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: SyncRegeln.inhaltsVersion(eintrag), metadataVersion: SyncRegeln.metadatenVersion(eintrag))
    }
}

/// Die Wurzel ("Lumen Cloud" selbst).
final class WurzelPosten: NSObject, NSFileProviderItem, @unchecked Sendable {   // shortcut: keine Felder
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { DomainAktion.anzeigename }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems] }
    var itemVersion: NSFileProviderItemVersion { NSFileProviderItemVersion(contentVersion: Data("1".utf8), metadataVersion: Data("1".utf8)) }
}

final class DateienErweiterung: NSObject, NSFileProviderReplicatedExtension, @unchecked Sendable {   // shortcut: nur `domain` (let), nie verändert
    private let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    // MARK: Hilfen

    static func client() throws -> HeimClient { try HeimClient.aus(Schluesselbund.live) }

    /// Kennung des PCs (leer = Wurzel) und die von Apple (`.rootContainer`).
    static func server(kennung k: NSFileProviderItemIdentifier) -> String { k == .rootContainer ? "" : k.rawValue }
    static func apple(kennung k: String) -> NSFileProviderItemIdentifier { k.isEmpty ? .rootContainer : NSFileProviderItemIdentifier(rawValue: k) }

    static func nsFehler(_ fehler: Error) -> Error {
        switch SyncRegeln.fehlerArt(fehler) {
        case .serverUnreachable: return NSFileProviderError(.serverUnreachable)
        case .notAuthenticated: return NSFileProviderError(.notAuthenticated)
        case .noSuchItem: return NSFileProviderError(.noSuchItem)
        case .syncAnchorExpired: return NSFileProviderError(.syncAnchorExpired)
        case .insufficientQuota: return NSFileProviderError(.insufficientQuota)
        case .abgebrochen: return CocoaError(.userCancelled)
        case .cannotSynchronize, .konflikt: return NSFileProviderError(.cannotSynchronize)
        }
    }

    /// Führt die Arbeit in einer Task aus; "Abbrechen" von iOS bricht die Task ab.
    private func laufe(_ arbeit: @escaping @Sendable () async -> Void) -> Progress {
        let fortschritt = Progress(totalUnitCount: 1)
        let aufgabe = Task { await arbeit() }
        fortschritt.cancellationHandler = { aufgabe.cancel() }
        return fortschritt
    }

    /// Ordner für heruntergeladene Dateien: derselbe Datenträger wie die Dateien-App (Apple verlangt das für `fetchContents`).
    private func tempOrdner() -> URL {
        let ordner = (try? NSFileProviderManager(for: domain)?.temporaryDirectoryURL()) ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }

    // MARK: Lesen

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        switch containerItemIdentifier {
        case .workingSet: return ArbeitsmengeEnumerator()
        case .trashContainer: return LeererEnumerator()   // Löschen geht in den Papierkorb am PC, nicht in einen Papierkorb der Dateien-App
        default: return OrdnerEnumerator(kennung: Self.server(kennung: containerItemIdentifier))
        }
    }

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let ruf = Rueckruf(completionHandler)
        return laufe {
            if identifier == .rootContainer { return ruf.wert(WurzelPosten(), nil) }
            if identifier == .trashContainer || identifier == .workingSet { return ruf.wert(nil, NSFileProviderError(.noSuchItem)) }   // keine Kennungen des PCs
            do {
                let e = try await Self.client().syncEintrag(id: identifier.rawValue)
                ruf.wert(DateiPosten(e), nil)
            } catch { ruf.wert(nil, Self.nsFehler(error)) }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let ruf = Rueckruf(completionHandler)
        let temp = tempOrdner()
        return laufe {
            do {
                let client = try Self.client()
                let e = try await client.syncEintrag(id: itemIdentifier.rawValue)
                guard !e.ordner, let pfad = e.pfad else { throw HeimFehler.nichtGefunden }
                let ziel = temp.appending(path: UUID().uuidString)
                try await client.dateiLaden(pfad: pfad, nach: ziel)
                ruf.wert(ziel, DateiPosten(e), nil)
            } catch { ruf.wert(nil, nil, Self.nsFehler(error)) }
        }
    }

    // MARK: Schreiben

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let ruf = Rueckruf(completionHandler)
        // Alles Nötige gleich lesen: das Item selbst gehört nicht in die Task.
        let eltern = Self.server(kennung: itemTemplate.parentItemIdentifier)
        let name = itemTemplate.filename
        let istOrdner = itemTemplate.contentType?.conforms(to: .folder) ?? false
        let groesse = itemTemplate.documentSize??.int64Value
        let kannSchonDa = options.contains(.mayAlreadyExist)
        return laufe {
            do {
                let client = try Self.client()
                if istOrdner {
                    do {
                        let neu = try await client.syncOrdner(eltern: eltern, name: name)
                        ruf.wert(DateiPosten(neu), [], false, nil)
                    } catch HeimFehler.konflikt {
                        // Gibt es den Ordner am PC schon, ist es derselbe: nicht doppeln.
                        guard let da = try await client.syncKinder(id: eltern).first(where: { $0.ordner && $0.name == name }) else { throw HeimFehler.konflikt }
                        ruf.wert(DateiPosten(da), [], false, nil)
                    }
                    return
                }
                guard let url else { throw HeimFehler.nichtGefunden }
                if kannSchonDa, let groesse, let da = try await client.syncKinder(id: eltern).first(where: { !$0.ordner && $0.name == name && $0.groesse == groesse }) {
                    ruf.wert(DateiPosten(da), [], false, nil)   // dieselbe Datei liegt schon am PC (etwa nach erneutem Koppeln)
                    return
                }
                let neu = try await client.syncNeu(eltern: eltern, name: name, von: url)
                ruf.wert(DateiPosten(neu), [], false, nil)
            } catch { ruf.wert(nil, [], false, Self.nsFehler(error)) }
        }
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let ruf = Rueckruf(completionHandler)
        let id = item.itemIdentifier.rawValue
        let name = item.filename
        let eltern = Self.server(kennung: item.parentItemIdentifier)
        let basis = SyncRegeln.fassung(ausVersion: version.contentVersion)
        let inhaltNeu = changedFields.contains(.contents) ? newContents : nil
        let umbenannt = changedFields.contains(.filename)
        let verschoben = changedFields.contains(.parentItemIdentifier)
        return laufe {
            do {
                let client = try Self.client()
                var aktuell: SyncEintrag?
                if let inhaltNeu {
                    // Ohne lesbare Basisfassung weiß niemand, ob der PC inzwischen anders ist: wie ein Konflikt behandeln, nichts überschreiben.
                    let versuch: ErsetzenErgebnis
                    if let basis { versuch = try await client.syncErsetzen(id: id, fassung: basis, von: inhaltNeu) } else { versuch = .konflikt(aktuell: nil) }
                    switch versuch {
                    case .ersetzt(let e):
                        aktuell = e
                    case .konflikt(let pc):
                        // Beide Seiten geändert: die Fassung vom Handy bleibt als "name (2).ext" erhalten, der Eintrag des PCs wird nachgeladen. Keine Seite geht verloren.
                        _ = try await client.syncNeu(eltern: eltern, name: name, von: inhaltNeu)
                        let pcEintrag: SyncEintrag
                        if let pc { pcEintrag = pc } else { pcEintrag = try await client.syncEintrag(id: id) }
                        ruf.wert(DateiPosten(pcEintrag), [], true, nil)
                        return
                    }
                }
                if umbenannt || verschoben {
                    aktuell = try await Self.benenneUm(client: client, id: id, eltern: verschoben ? eltern : nil, name: umbenannt ? name : nil)
                }
                let ergebnis: SyncEintrag
                if let aktuell { ergebnis = aktuell } else { ergebnis = try await client.syncEintrag(id: id) }
                ruf.wert(DateiPosten(ergebnis), [], false, nil)
            } catch { ruf.wert(nil, [], false, Self.nsFehler(error)) }
        }
    }

    /// Umbenennen oder Verschieben; ist der Zielname am PC vergeben, nimmt es "name (2).ext" … statt zu scheitern (nichts wird überschrieben).
    private static func benenneUm(client: HeimClient, id: String, eltern: String?, name: String?) async throws -> SyncEintrag {
        do { return try await client.syncUmbenennen(id: id, eltern: eltern, name: name) } catch HeimFehler.konflikt {
            guard let name else { throw HeimFehler.konflikt }
            for alternative in SyncRegeln.alternativeNamen(zu: name) {
                do { return try await client.syncUmbenennen(id: id, eltern: eltern, name: alternative) } catch HeimFehler.konflikt { continue }
            }
            throw HeimFehler.konflikt
        }
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let ruf = Rueckruf(completionHandler)
        let basis = SyncRegeln.fassung(ausVersion: version.contentVersion)
        return laufe {
            do {
                let client = try Self.client()
                // Ordner tragen keine feste Fassung (ihre Zeit ändert sich mit jedem Kind); bei Dateien schützt die Fassung vor dem Löschen einer neueren PC-Fassung.
                let e = try? await client.syncEintrag(id: identifier.rawValue)
                if let e, e.ordner == false, let basis, basis != e.fassung { throw HeimFehler.konflikt }
                try await client.syncPapierkorb(id: identifier.rawValue, fassung: nil)
                ruf.wert(nil)
            } catch HeimFehler.nichtGefunden {
                ruf.wert(nil)   // am PC schon weg: gewollt
            } catch HeimFehler.konflikt {
                ruf.wert(NSFileProviderError(.cannotSynchronize))   // der PC hat die Datei inzwischen geändert; sie bleibt, die nächste Abfrage bringt sie zurück
            } catch { ruf.wert(Self.nsFehler(error)) }
        }
    }
}

// MARK: Enumeratoren

/// Inhalt eines Ordners. Änderungen meldet allein die Arbeitsmenge.
final class OrdnerEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {   // shortcut: nur `let`
    private let kennung: String
    init(kennung: String) { self.kennung = kennung }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let beobachter = Rueckruf(observer)
        let kennung = kennung
        Task {
            do {
                let liste = try await DateienErweiterung.client().syncKinder(id: kennung)
                beobachter.wert.didEnumerate(liste.map { DateiPosten($0) })
                beobachter.wert.finishEnumerating(upTo: nil)
            } catch { beobachter.wert.finishEnumeratingWithError(DateienErweiterung.nsFehler(error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) { completionHandler(nil) }
}

/// Der Papierkorb-Container: bleibt leer.
final class LeererEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {   // shortcut: ohne Felder
    func invalidate() {}
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) { completionHandler(nil) }
}

/// Die Arbeitsmenge: der ganze Baum. IOS fragt hier nach Änderungen (nach `signalEnumerator`, beim Öffnen von Dateien und wenn es das selbst für nötig hält).
final class ArbeitsmengeEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {   // shortcut: ohne Felder
    private static let stueck = 500

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let beobachter = Rueckruf(observer)
        Task {
            do {
                let alles = try await DateienErweiterung.client().syncAenderungen(anker: nil).eintraege
                for anfang in stride(from: 0, to: alles.count, by: Self.stueck) {
                    beobachter.wert.didEnumerate(alles[anfang..<min(anfang + Self.stueck, alles.count)].map { DateiPosten($0) })
                }
                beobachter.wert.finishEnumerating(upTo: nil)
            } catch { beobachter.wert.finishEnumeratingWithError(DateienErweiterung.nsFehler(error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let beobachter = Rueckruf(observer)
        let alt = SyncRegeln.fassung(ausVersion: anchor.rawValue)
        Task {
            do {
                // Ein Anker, den wir nicht lesen können, gilt wie ein abgelaufener: alles neu.
                guard let alt else { throw HeimFehler.abgelehnt(410) }
                let a = try await DateienErweiterung.client().syncAenderungen(anker: alt)
                for anfang in stride(from: 0, to: a.eintraege.count, by: Self.stueck) {
                    beobachter.wert.didUpdate(a.eintraege[anfang..<min(anfang + Self.stueck, a.eintraege.count)].map { DateiPosten($0) })
                }
                if !a.weg.isEmpty { beobachter.wert.didDeleteItems(withIdentifiers: a.weg.map { NSFileProviderItemIdentifier(rawValue: $0) }) }
                beobachter.wert.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(Data(a.anker.utf8)), moreComing: false)
            } catch { beobachter.wert.finishEnumeratingWithError(DateienErweiterung.nsFehler(error)) }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let ruf = Rueckruf(completionHandler)
        Task {
            let a = try? await DateienErweiterung.client().syncAenderungen(anker: nil, nurAnker: true)
            ruf.wert(a.map { NSFileProviderSyncAnchor(Data($0.anker.utf8)) })
        }
    }
}
