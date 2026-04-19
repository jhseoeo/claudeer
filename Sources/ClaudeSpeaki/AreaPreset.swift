import Foundation

enum AreaPreset: String, CaseIterable {
    case fullScreen = "full_screen"
    case bottom
    case top
    case menubar
    case rightQuarter = "right_quarter"
    case leftQuarter = "left_quarter"

    var displayName: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .menubar: return "Menu Bar"
        case .rightQuarter: return "Right 1/4"
        case .leftQuarter: return "Left 1/4"
        }
    }

    func rect(for screenSize: CGSize) -> CGRect {
        let w = screenSize.width
        let h = screenSize.height
        switch self {
        case .fullScreen:
            return CGRect(x: 0, y: 0, width: w, height: h)
        case .bottom:
            return CGRect(x: 0, y: 0, width: w, height: h * 0.15)
        case .top:
            return CGRect(x: 0, y: h * 0.85, width: w, height: h * 0.15)
        case .menubar:
            return CGRect(x: 0, y: h * 0.92, width: w, height: h * 0.08)
        case .rightQuarter:
            return CGRect(x: w * 0.75, y: 0, width: w * 0.25, height: h)
        case .leftQuarter:
            return CGRect(x: 0, y: 0, width: w * 0.25, height: h)
        }
    }
}
