import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import UniformTypeIdentifiers

/// Ein aus der Fotoauswahl geholtes Foto oder Video als Datei im Temp-Ordner. Bewusst kein `Data`: ein Video würde sonst ganz in den Speicher geladen.
struct AusgewaehlteDatei: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { empfangen in
            // Die Datei von iOS gilt nur in diesem Block: sofort in den eigenen Temp-Ordner kopieren.
            let ordner = FileManager.default.temporaryDirectory.appending(path: "heimherz-auswahl-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let ziel = ordner.appending(path: empfangen.file.lastPathComponent)
            try FileManager.default.copyItem(at: empfangen.file, to: ziel)
            return AusgewaehlteDatei(url: ziel)
        }
    }
}
