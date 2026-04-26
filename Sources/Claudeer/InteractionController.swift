import AppKit

class InteractionController: InteractionViewDelegate {
    private weak var window: NSWindow?
    private let spriteEngine: SpriteEngine
    private let soundPlayer: SoundPlayer
    private let characterController: CharacterController

    private var pollingTimer: Timer?
    private var clickClearWorkItem: DispatchWorkItem?

    private var isMouseDown = false
    private var hasDragged = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownLocation: NSPoint = .zero

    private let dragThreshold: CGFloat = 4.0
    private let clickSpriteDuration: TimeInterval = 1.0

    init(
        window: NSWindow,
        interactionView: InteractionView,
        spriteEngine: SpriteEngine,
        soundPlayer: SoundPlayer,
        characterController: CharacterController
    ) {
        self.window = window
        self.spriteEngine = spriteEngine
        self.soundPlayer = soundPlayer
        self.characterController = characterController
        interactionView.delegate = self
    }

    func start() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateCursorHover()
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func updateCursorHover() {
        guard let window = window else { return }
        if isMouseDown {
            window.ignoresMouseEvents = false
            return
        }
        let mouse = NSEvent.mouseLocation
        let mouseInWindow = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let inside = characterController.spriteFrame.contains(mouseInWindow)
        window.ignoresMouseEvents = !inside
    }

    func interactionMouseDown(at locationInWindow: NSPoint) {
        clickClearWorkItem?.cancel()
        clickClearWorkItem = nil
        spriteEngine.clearInteractionSprite()

        isMouseDown = true
        hasDragged = false
        mouseDownLocation = locationInWindow
        let sprite = characterController.spriteFrame
        dragOffset = NSPoint(
            x: sprite.origin.x - locationInWindow.x,
            y: sprite.origin.y - locationInWindow.y
        )
        characterController.setBeingDragged(true)
    }

    func interactionMouseDragged(to locationInWindow: NSPoint) {
        guard isMouseDown else { return }
        let dx = locationInWindow.x - mouseDownLocation.x
        let dy = locationInWindow.y - mouseDownLocation.y
        let dist = sqrt(dx * dx + dy * dy)

        if !hasDragged && dist >= dragThreshold {
            hasDragged = true
            spriteEngine.playInteractionSprite(.drag)
            soundPlayer.playInteraction(.dragPress)
        }
        if hasDragged {
            let newOrigin = NSPoint(
                x: locationInWindow.x + dragOffset.x,
                y: locationInWindow.y + dragOffset.y
            )
            characterController.setSpritePosition(newOrigin)
        }
    }

    func interactionMouseUp(at locationInWindow: NSPoint) {
        guard isMouseDown else { return }
        isMouseDown = false

        if hasDragged {
            soundPlayer.playInteraction(.dragRelease)
            spriteEngine.clearInteractionSprite()
        } else {
            soundPlayer.playInteraction(.click)
            spriteEngine.playInteractionSprite(.click)
            let work = DispatchWorkItem { [weak self] in
                self?.spriteEngine.clearInteractionSprite()
                self?.clickClearWorkItem = nil
            }
            clickClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + clickSpriteDuration, execute: work)
        }
        characterController.setBeingDragged(false)
        hasDragged = false
    }
}
