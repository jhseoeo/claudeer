import AppKit
import CoreGraphics

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

    func rect(in screenFrame: CGRect) -> CGRect {
        let x = screenFrame.minX
        let y = screenFrame.minY
        let w = screenFrame.width
        let h = screenFrame.height
        switch self {
        case .fullScreen:
            return CGRect(x: x, y: y, width: w, height: h)
        case .bottom:
            return CGRect(x: x, y: y, width: w, height: h * 0.15)
        case .top:
            return CGRect(x: x, y: y + h * 0.85, width: w, height: h * 0.15)
        case .menubar:
            return CGRect(x: x, y: y + h * 0.92, width: w, height: h * 0.08)
        case .rightQuarter:
            return CGRect(x: x + w * 0.75, y: y, width: w * 0.25, height: h)
        case .leftQuarter:
            return CGRect(x: x, y: y, width: w * 0.25, height: h)
        }
    }

    func rects(for screens: [NSScreen]) -> [CGRect] {
        screens.map { rect(in: $0.frame) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    var stableIdentifier: String? {
        let id = displayID
        guard id != 0,
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(id)
        else { return nil }
        let uuid = uuidRef.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func boundingFrame() -> CGRect {
        screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    static func screens(matching identifier: String?) -> [NSScreen] {
        guard let identifier = identifier else { return screens }
        if let match = screens.first(where: { $0.stableIdentifier == identifier }) {
            return [match]
        }
        return screens
    }
}
