import Foundation

enum MascotState: String, Codable, CaseIterable {
    case idle
    case working

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        }
    }
}
