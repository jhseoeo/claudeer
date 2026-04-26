import AppKit

class SpriteEngine {
    private(set) var currentState: MascotState = .idle
    private var sprites: [MascotState: NSImage] = [:]
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
        sprites.removeAll()
        let extensions = ["gif", "apng", "png", "jpg"]
        for state in MascotState.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(state.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path),
                   let image = NSImage(contentsOf: url) {
                    sprites[state] = image
                    break
                }
            }
        }
        if sprites[.idle] == nil, let first = sprites.values.first {
            sprites[.idle] = first
        }
        setState(currentState)
    }

    func setState(_ state: MascotState) {
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
