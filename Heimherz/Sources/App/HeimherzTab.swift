import Foundation

enum HeimherzTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case passwoerter, fotos, dateien, einstellungen
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .passwoerter: return "Passwörter"
        case .fotos: return "Fotos"
        case .dateien: return "Dateien"
        case .einstellungen: return "Einstellungen"
        }
    }

    var symbolName: String {
        switch self {
        case .passwoerter: return "key.fill"
        case .fotos: return "photo.fill"
        case .dateien: return "folder.fill"
        case .einstellungen: return "gearshape.fill"
        }
    }
}
