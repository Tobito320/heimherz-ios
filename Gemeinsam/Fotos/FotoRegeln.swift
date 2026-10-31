import CryptoKit
import Foundation
import Photos

/// Welche Datei eines Assets es ist. Der Name im Pfad (`foto-0`) besteht aus `kuerzel` und dem Index unter gleichen Arten.
enum FotoArt: String, Sendable, CaseIterable {
    case foto, video, live, alternative, ton

    var kuerzel: String { rawValue }

    /// Nur die Originale (SPEC 11): bearbeitete Fassungen und Anpassungsdaten gehören nicht dazu.
    init?(_ typ: PHAssetResourceType) {
        switch typ {
        case .photo: self = .foto
        case .video: self = .video
        case .pairedVideo: self = .live
        case .alternatePhoto: self = .alternative
        case .audio: self = .ton
        default: return nil
        }
    }

    var istVideo: Bool { self == .video || self == .live }
}

/// Eine Datei eines Assets, wie sie zum PC geht: `PUT /v1/fotos/<kennung>/<name>`.
struct FotoRessource: Sendable, Hashable {
    let assetId: String
    let kennung: String
    let name: String
    let art: FotoArt
    let dateiname: String
    let aufnahme: Date?
    /// Das Asset ist ein Video (nicht Foto und nicht Live Photo); bestimmt die Phase im Abgleich (erst Fotos, dann Videos).
    var assetIstVideo = false

    /// Der Eintrag in `GET /v1/fotos/bekannt` und in `FotoStand`.
    var schluessel: String { FotoRegeln.schluessel(kennung: kennung, name: name) }
}

/// Ein Asset ohne seine Dateien (billig zu bilden): `kennung` aus `localIdentifier`.
struct FotoKopf: Sendable, Hashable {
    let assetId: String
    let kennung: String
    /// `PHAssetMediaType.video`; ein Live Photo bleibt ein Foto (es geht als Ganzes in die Foto-Phase). Die Größe wäre genauer, steht aber nur über einen privaten Schlüssel bereit.
    var istVideo = false
}

/// Reine Regeln, die App und Erweiterung teilen. Beide müssen für dieselbe Datei denselben Schlüssel bilden, sonst gäbe es Doppelte.
enum FotoRegeln {
    /// SHA-256 von `localIdentifier`, b64url ohne Füllzeichen (43 Zeichen).
    static func kennung(assetId: String) -> String {
        Data(SHA256.hash(data: Data(assetId.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func schluessel(kennung: String, name: String) -> String { "\(kennung)/\(name)" }

    static func kennung(vonSchluessel schluessel: String) -> String { String(schluessel.prefix { $0 != "/" }) }

    /// Schlüssel aus dem Pfad einer Upload-Anfrage (`/v1/fotos/<kennung>/<name>`), damit die Erweiterung einen Job seiner Datei zuordnet.
    static func schluessel(pfad: String) -> String? {
        let teile = pfad.split(separator: "/").map(String.init)
        guard teile.count == 4, teile[0] == "v1", teile[1] == "fotos" else { return nil }
        return schluessel(kennung: teile[2], name: teile[3])
    }

    /// Die Dateien eines Assets in fester Reihenfolge; der Index zählt je Art von 0. Arten, die nicht zu den Originalen zählen, fallen weg.
    static func ressourcen(kopf: FotoKopf, aufnahme: Date?, teile: [(art: FotoArt, dateiname: String)]) -> [FotoRessource] {
        var zaehler: [FotoArt: Int] = [:]
        return teile.map { teil in
            let i = zaehler[teil.art, default: 0]
            zaehler[teil.art] = i + 1
            return FotoRessource(assetId: kopf.assetId, kennung: kopf.kennung, name: "\(teil.art.kuerzel)-\(i)", art: teil.art, dateiname: teil.dateiname, aufnahme: aufnahme, assetIstVideo: kopf.istVideo)
        }
    }

    /// Beim Öffnen der App startet der Abgleich von selbst (SPEC 31, Ziel 2): gekoppelt, volle Erlaubnis, kein Lauf, und der Nutzer hat nicht angehalten.
    static func startetVonSelbst(gekoppelt: Bool, erlaubnisVoll: Bool, laeuft: Bool, vomNutzerAngehalten: Bool) -> Bool {
        gekoppelt && erlaubnisVoll && !laeuft && !vomNutzerAngehalten
    }

    /// Die Foto-Erweiterung ist Standard an, sobald gekoppelt und die volle Erlaubnis da ist, außer der Nutzer hat sie selbst ausgeschaltet.
    static func erweiterungSollAn(gekoppelt: Bool, erlaubnisVoll: Bool, nutzerHatAusgeschaltet: Bool) -> Bool {
        gekoppelt && erlaubnisVoll && !nutzerHatAusgeschaltet
    }

    /// Der Nachtlauf braucht keinen Strom mehr; im Stromsparmodus läuft er nur am Ladegerät.
    static func nachtlaufErlaubt(stromsparmodus: Bool, amStrom: Bool) -> Bool { !stromsparmodus || amStrom }

    static func kopf(assetId: String, istVideo: Bool = false) -> FotoKopf { FotoKopf(assetId: assetId, kennung: kennung(assetId: assetId), istVideo: istVideo) }
}

/// PhotoKit-Anbindung (App und Erweiterung): Assets neueste zuerst, Dateien eines Assets. Liest nur, ändert und löscht nie etwas.
enum FotoBibliothek {
    static func abfrage() -> PHFetchResult<PHAsset> {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.includeHiddenAssets = true
        o.includeAllBurstAssets = true
        return PHAsset.fetchAssets(with: o)
    }

    /// Die Dateien eines Assets samt PhotoKit-Objekt (nur lokal benutzen, nicht Sendable).
    static func ressourcen(_ asset: PHAsset) -> [(ressource: FotoRessource, objekt: PHAssetResource)] {
        let kopf = FotoRegeln.kopf(assetId: asset.localIdentifier, istVideo: asset.mediaType == .video)
        let objekte = PHAssetResource.assetResources(for: asset).compactMap { o in FotoArt(o.type).map { (art: $0, objekt: o) } }
        let liste = FotoRegeln.ressourcen(kopf: kopf, aufnahme: asset.creationDate, teile: objekte.map { (art: $0.art, dateiname: $0.objekt.originalFilename) })
        return zip(liste, objekte).map { (ressource: $0, objekt: $1.objekt) }
    }
}
