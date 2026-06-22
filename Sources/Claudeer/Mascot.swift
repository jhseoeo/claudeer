import AppKit

class Mascot {
    let sessionID: String
    let spriteEngine: SpriteEngine
    let characterController: CharacterController
    let speechBubble: SpeechBubbleView
    private(set) var state: MascotState = .idle
    private weak var placer: MascotPlacer?

    private let nameLabel = NameLabelView()
    private var displayName = ""
    private var showLabel = true
    private(set) var isHidden = false

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
        self.nameLabel.isHidden = true

        // Keep the name label glued under the sprite as it moves / changes windows.
        self.spriteEngine.onPlaced = { [weak self] in self?.layoutNameLabel() }

        // Place the sprite into the overlay window covering its initial position.
        spriteEngine.setPosition(initialPosition)
    }

    /// The sprite's frame in global screen coordinates (for cross-window hit testing).
    var globalFrame: NSRect {
        NSRect(origin: spriteEngine.position, size: spriteEngine.size)
    }

    /// Set the session name shown under the mascot. Falls back to a short id.
    func setName(_ name: String?) {
        let resolved = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (resolved?.isEmpty == false) ? resolved! : String(sessionID.prefix(8))
        if text != displayName {
            displayName = text
            nameLabel.setText(text)
        }
        updateLabelVisibility()
        layoutNameLabel()
    }

    func setLabelVisible(_ visible: Bool) {
        showLabel = visible
        updateLabelVisibility()
        layoutNameLabel()
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        spriteEngine.view.isHidden = hidden
        if hidden {
            speechBubble.dismiss()
            nameLabel.isHidden = true
            characterController.setPaused(true)
        } else {
            characterController.setPaused(false)
            updateLabelVisibility()
            layoutNameLabel()
        }
    }

    func start() {
        characterController.start()
    }

    func teardown() {
        characterController.stop()
        speechBubble.dismiss()
        spriteEngine.view.removeFromSuperview()
        speechBubble.removeFromSuperview()
        nameLabel.removeFromSuperview()
    }

    func applyTransition(to newState: MascotState, speech: String) {
        guard state != newState else { return }
        state = newState
        spriteEngine.setState(newState)
        characterController.transitionTo(newState)

        guard !isHidden else { return }

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

    private func updateLabelVisibility() {
        nameLabel.isHidden = !showLabel || displayName.isEmpty
    }

    private func layoutNameLabel() {
        guard showLabel, !displayName.isEmpty, let placer = placer else { return }
        let pos = spriteEngine.position
        let size = spriteEngine.size
        let center = NSPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        guard let host = placer.hostView(forGlobalPoint: center) else { return }

        let labelSize = nameLabel.frame.size
        // Centered horizontally, just below the sprite's feet, in global coords.
        let globalX = pos.x + size.width / 2 - labelSize.width / 2
        let globalY = pos.y - labelSize.height - 2
        // Convert to host-window-local and clamp so it stays on that screen.
        let bounds = host.view.bounds
        let localX = min(max(globalX - host.globalOrigin.x, 0), max(0, bounds.width - labelSize.width))
        let localY = min(max(globalY - host.globalOrigin.y, 0), max(0, bounds.height - labelSize.height))

        if nameLabel.superview !== host.view {
            host.view.addSubview(nameLabel)
        }
        nameLabel.setFrameOrigin(NSPoint(x: localX, y: localY))
    }
}
