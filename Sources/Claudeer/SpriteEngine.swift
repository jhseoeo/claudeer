import AppKit

class SpriteEngine {
    private(set) var currentState: MascotState = .idle
    private var sprites: [MascotState: SpriteFrames] = [:]
    private var spritesMirrored: [MascotState: SpriteFrames] = [:]
    private var interactionSprites: [InteractionSprite: SpriteFrames] = [:]
    private var interactionSpritesMirrored: [InteractionSprite: SpriteFrames] = [:]
    private var override: InteractionSprite?
    private let spriteView: SpriteLayerView
    private var flips: FlipSettings = .off
    private var isFacingLeft: Bool = false

    /// Routes the sprite view into the overlay window covering its current position.
    weak var placer: MascotPlacer?
    /// Called after every placement so siblings (e.g. the name label) can follow.
    var onPlaced: (() -> Void)?
    private var globalPosition: NSPoint

    init(frame: NSRect) {
        spriteView = SpriteLayerView(frame: frame)
        globalPosition = frame.origin
    }

    var view: NSView { spriteView }

    var size: NSSize {
        spriteView.frame.size
    }

    func loadSprites(from directory: URL) {
        sprites.removeAll()
        spritesMirrored.removeAll()
        interactionSprites.removeAll()
        interactionSpritesMirrored.removeAll()
        let extensions = ["gif", "apng", "png", "jpg"]
        for state in MascotState.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(state.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path),
                   let frames = SpriteFrames.load(from: url) {
                    sprites[state] = frames
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
                   let frames = SpriteFrames.load(from: url) {
                    interactionSprites[key] = frames
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

    /// Sets the sprite's position in global screen coordinates, reparenting the view
    /// into whichever overlay window covers that point.
    func setPosition(_ point: NSPoint) {
        globalPosition = point
        placeView()
    }

    var position: NSPoint {
        globalPosition
    }

    private func placeView() {
        let center = NSPoint(
            x: globalPosition.x + size.width / 2,
            y: globalPosition.y + size.height / 2
        )
        guard let host = placer?.hostView(forGlobalPoint: center) else {
            spriteView.setFrameOrigin(globalPosition)
            return
        }
        if spriteView.superview !== host.view {
            host.view.addSubview(spriteView)
        }
        spriteView.setFrameOrigin(NSPoint(
            x: globalPosition.x - host.globalOrigin.x,
            y: globalPosition.y - host.globalOrigin.y
        ))
        onPlaced?()
    }

    func setFlips(_ settings: FlipSettings) {
        flips = settings
        updateDisplayedImage()
    }

    func setFacing(left: Bool) {
        guard isFacingLeft != left else { return }
        isFacingLeft = left
        updateDisplayedImage()
    }

    var shouldRenderMirrored: Bool {
        if flips.directional {
            return flips.mirrored != isFacingLeft
        } else {
            return flips.mirrored
        }
    }

    private func updateDisplayedImage() {
        let frames: SpriteFrames?
        if let override, let base = interactionSprites[override] {
            frames = shouldRenderMirrored
                ? mirroredInteractionSprite(for: override, base: base)
                : base
        } else {
            let base = sprites[currentState] ?? sprites[.idle]
            frames = base.map {
                shouldRenderMirrored ? mirroredStateSprite(for: currentState, base: $0) : $0
            }
        }
        spriteView.spriteFrames = frames
    }

    private func mirroredStateSprite(for state: MascotState, base: SpriteFrames) -> SpriteFrames {
        if let cached = spritesMirrored[state] { return cached }
        let mirrored = base.horizontallyFlipped()
        spritesMirrored[state] = mirrored
        return mirrored
    }

    private func mirroredInteractionSprite(for key: InteractionSprite, base: SpriteFrames) -> SpriteFrames {
        if let cached = interactionSpritesMirrored[key] { return cached }
        let mirrored = base.horizontallyFlipped()
        interactionSpritesMirrored[key] = mirrored
        return mirrored
    }
}

struct SpriteFrames {
    let cgImages: [CGImage]
    let durations: [TimeInterval]
    let pointSize: NSSize

    var isAnimated: Bool { cgImages.count > 1 }
    var totalDuration: TimeInterval { durations.reduce(0, +) }

    static func load(from url: URL) -> SpriteFrames? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let pointSize = image.size

        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           let frameCount = bitmap.value(forProperty: .frameCount) as? Int,
           frameCount > 1 {
            var cgImages: [CGImage] = []
            var durations: [TimeInterval] = []
            for i in 0..<frameCount {
                bitmap.setProperty(.currentFrame, withValue: i)
                guard let cg = bitmap.cgImage else { continue }
                cgImages.append(cg)
                let duration = (bitmap.value(forProperty: .currentFrameDuration) as? TimeInterval) ?? 0.1
                durations.append(max(duration, 0.02))
            }
            bitmap.setProperty(.currentFrame, withValue: 0)
            if !cgImages.isEmpty {
                return SpriteFrames(cgImages: cgImages, durations: durations, pointSize: pointSize)
            }
        }

        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return SpriteFrames(cgImages: [cg], durations: [0], pointSize: pointSize)
        }
        return nil
    }

    func horizontallyFlipped() -> SpriteFrames {
        let flipped = cgImages.compactMap(SpriteFrames.flip)
        return SpriteFrames(cgImages: flipped, durations: durations, pointSize: pointSize)
    }

    private static func flip(_ cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

class SpriteLayerView: NSView {
    private let imageLayer = CALayer()
    private let animationKey = "spriteFrames"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspect
        updateLayerFrame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var frame: NSRect {
        didSet { updateLayerFrame() }
    }

    private func updateLayerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    var spriteFrames: SpriteFrames? {
        didSet { applySpriteFrames() }
    }

    private func applySpriteFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.removeAnimation(forKey: animationKey)
        guard let frames = spriteFrames, !frames.cgImages.isEmpty else {
            imageLayer.contents = nil
            CATransaction.commit()
            return
        }
        imageLayer.contents = frames.cgImages.first
        if frames.isAnimated && frames.totalDuration > 0 {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames.cgImages
            animation.duration = frames.totalDuration
            animation.repeatCount = .infinity
            animation.calculationMode = .discrete
            var cumulative: TimeInterval = 0
            var keyTimes: [NSNumber] = [0.0]
            for d in frames.durations.dropLast() {
                cumulative += d
                keyTimes.append(NSNumber(value: cumulative / frames.totalDuration))
            }
            animation.keyTimes = keyTimes
            imageLayer.add(animation, forKey: animationKey)
        }
        CATransaction.commit()
    }
}
