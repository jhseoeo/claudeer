import AppKit

class Mascot {
    let sessionID: String
    let spriteEngine: SpriteEngine
    let characterController: CharacterController
    let speechBubble: SpeechBubbleView
    private(set) var state: MascotState = .idle
    private weak var placer: MascotPlacer?

    init(
        sessionID: String,
        spriteSize: NSSize,
        initialPosition: NSPoint,
        placer: MascotPlacer
    ) {
        self.sessionID = sessionID
        self.placer = placer
        let frame = NSRect(origin: initialPosition, size: spriteSize)
        self.spriteEngine = SpriteEngine(frame: frame)
        self.spriteEngine.placer = placer
        self.characterController = CharacterController(spriteEngine: spriteEngine)
        self.speechBubble = SpeechBubbleView()
        self.speechBubble.isHidden = true

        // Place the sprite into the overlay window covering its initial position.
        spriteEngine.setPosition(initialPosition)
    }

    /// The sprite's frame in global screen coordinates (for cross-window hit testing).
    var globalFrame: NSRect {
        NSRect(origin: spriteEngine.position, size: spriteEngine.size)
    }

    func start() {
        characterController.start()
    }

    func teardown() {
        characterController.stop()
        speechBubble.dismiss()
        spriteEngine.view.removeFromSuperview()
        speechBubble.removeFromSuperview()
    }

    func applyTransition(to newState: MascotState, speech: String) {
        guard state != newState else { return }
        state = newState
        spriteEngine.setState(newState)
        characterController.transitionTo(newState)

        let pos = spriteEngine.position
        let globalAnchor = NSPoint(
            x: pos.x + spriteEngine.size.width / 2,
            y: pos.y + spriteEngine.size.height
        )
        guard let host = placer?.hostView(forGlobalPoint: globalAnchor) else { return }
        if speechBubble.superview !== host.view {
            host.view.addSubview(speechBubble)
        }
        let localAnchor = NSPoint(
            x: globalAnchor.x - host.globalOrigin.x,
            y: globalAnchor.y - host.globalOrigin.y
        )
        speechBubble.show(text: speech, above: localAnchor)
    }
}
