import Foundation

enum HeimherzTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case passwoerter, fotos, dateien, mehr
    var id: String { rawValue }

    var titel: String {
        switch self {
        case .passwoerter: return "Passwörter"
        case .fotos: return "Fotos"
        case .dateien: return "Dateien"
        case .mehr: return "Mehr"
        }
    }

    var symbolName: String {
        switch self {
        case .passwoerter: return "key.fill"
        case .fotos: return "photo.fill"
        case .dateien: return "folder.fill"
        case .mehr: return "ellipsis.circle.fill"
        }
    }
}
