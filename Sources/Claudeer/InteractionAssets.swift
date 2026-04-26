import Foundation

enum InteractionSprite: String, CaseIterable {
    case drag
    case click

    var displayName: String {
        switch self {
        case .drag: return "Drag"
        case .click: return "Click"
        }
    }
}

enum InteractionSound: String, CaseIterable {
    case dragPress = "drag_press"
    case dragRelease = "drag_release"
    case click

    var displayName: String {
        switch self {
        case .dragPress: return "Drag press"
        case .dragRelease: return "Drag release"
        case .click: return "Click"
        }
    }
}
