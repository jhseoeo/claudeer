import AppKit

class Mascot {
    let sessionID: String
    let spriteEngine: SpriteEngine
    let characterController: CharacterController
    let speechBubble: SpeechBubbleView
    private(set) var state: MascotState = .idle

    init(
        sessionID: String,
        spriteSize: NSSize,
        initialPosition: NSPoint,
        container: NSView
    ) {
        self.sessionID = sessionID
        let frame = NSRect(origin: initialPosition, size: spriteSize)
        self.spriteEngine = SpriteEngine(frame: frame)
        self.characterController = CharacterController(spriteEngine: spriteEngine)
        self.speechBubble = SpeechBubbleView()
        self.speechBubble.isHidden = true

        container.addSubview(spriteEngine.view)
        container.addSubview(speechBubble)
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
        let above = NSPoint(
            x: pos.x + spriteEngine.size.width / 2,
            y: pos.y + spriteEngine.size.height
        )
        speechBubble.show(text: speech, above: above)
    }
}
