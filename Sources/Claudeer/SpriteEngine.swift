import AppKit

enum SpriteState: String, CaseIterable {
    case idle
    case walk
    case alert
}

class SpriteEngine {
    private(set) var currentState: SpriteState = .idle
    private var sprites: [SpriteState: NSImage] = [:]
    private let imageView: NSImageView

    init(frame: NSRect) {
        imageView = NSImageView(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.wantsLayer = true
    }

    var view: NSView { imageView }

    var size: NSSize {
        imageView.frame.size
    }

    func loadSprites(from directory: URL) {
        let extensions = ["gif", "apng", "png"]
        for state in SpriteState.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(state.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path),
                   let image = NSImage(contentsOf: url) {
                    sprites[state] = image
                    break
                }
            }
        }
        // Ensure idle exists — use first available sprite as fallback
        if sprites[.idle] == nil, let first = sprites.values.first {
            sprites[.idle] = first
        }
        setState(.idle)
    }

    func setState(_ state: SpriteState) {
        currentState = state
        let image = sprites[state] ?? sprites[.idle]
        imageView.image = image
    }

    func setPosition(_ point: NSPoint) {
        imageView.setFrameOrigin(point)
    }

    var position: NSPoint {
        imageView.frame.origin
    }
}
