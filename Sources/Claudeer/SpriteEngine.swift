import AppKit

class SpriteEngine {
    private(set) var currentState: MascotState = .idle
    private var sprites: [MascotState: NSImage] = [:]
    private var interactionSprites: [InteractionSprite: NSImage] = [:]
    private var override: InteractionSprite?
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
        interactionSprites.removeAll()
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
        for key in InteractionSprite.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(key.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path),
                   let image = NSImage(contentsOf: url) {
                    interactionSprites[key] = image
                    break
                }
            }
        }
        updateDisplayedImage()
    }

    func setState(_ state: MascotState) {
        currentState = state
        updateDisplayedImage()
    }

    func playInteractionSprite(_ key: InteractionSprite) {
        guard interactionSprites[key] != nil else { return }
        override = key
        updateDisplayedImage()
    }

    func clearInteractionSprite() {
        override = nil
        updateDisplayedImage()
    }

    func setPosition(_ point: NSPoint) {
        imageView.setFrameOrigin(point)
    }

    var position: NSPoint {
        imageView.frame.origin
    }

    private func updateDisplayedImage() {
        if let override, let image = interactionSprites[override] {
            imageView.image = image
        } else {
            imageView.image = sprites[currentState] ?? sprites[.idle]
        }
    }
}
