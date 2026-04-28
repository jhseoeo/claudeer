import AppKit

class InteractionController: InteractionViewDelegate {
    private weak var window: NSWindow?
    private let mascotManager: MascotManager
    private let soundPlayer: SoundPlayer

    private var pollingTimer: Timer?
    private var clickClearWorkItem: DispatchWorkItem?

    private var isMouseDown = false
    private var hasDragged = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownLocation: NSPoint = .zero
    private weak var activeMascot: Mascot?

    private let dragThreshold: CGFloat = 4.0
    private let clickSpriteDuration: TimeInterval = 1.0

    init(
        window: NSWindow,
        interactionView: InteractionView,
        mascotManager: MascotManager,
        soundPlayer: SoundPlayer
    ) {
        self.window = window
        self.mascotManager = mascotManager
        self.soundPlayer = soundPlayer
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
        let inside = mascotManager.allMascots.contains {
            $0.spriteEngine.view.frame.contains(mouseInWindow)
        }
        window.ignoresMouseEvents = !inside
    }

    func interactionMouseDown(at locationInWindow: NSPoint) {
        let target = mascotManager.allMascots.first {
            $0.spriteEngine.view.frame.contains(locationInWindow)
        }
        guard let target = target else { return }

        clickClearWorkItem?.cancel()
        clickClearWorkItem = nil
        target.spriteEngine.clearInteractionSprite()

        isMouseDown = true
        hasDragged = false
        mouseDownLocation = locationInWindow
        let frame = target.spriteEngine.view.frame
        dragOffset = NSPoint(
            x: frame.origin.x - locationInWindow.x,
            y: frame.origin.y - locationInWindow.y
        )
        target.characterController.setBeingDragged(true)
        activeMascot = target
    }

    func interactionMouseDragged(to locationInWindow: NSPoint) {
        guard isMouseDown, let mascot = activeMascot else { return }
        let dx = locationInWindow.x - mouseDownLocation.x
        let dy = locationInWindow.y - mouseDownLocation.y
        let dist = sqrt(dx * dx + dy * dy)

        if !hasDragged && dist >= dragThreshold {
            hasDragged = true
            mascot.spriteEngine.playInteractionSprite(.drag)
            soundPlayer.playInteraction(.dragPress)
        }
        if hasDragged {
            let newOrigin = NSPoint(
                x: locationInWindow.x + dragOffset.x,
                y: locationInWindow.y + dragOffset.y
            )
            mascot.characterController.setSpritePosition(newOrigin)
        }
    }

    func interactionMouseUp(at locationInWindow: NSPoint) {
        guard isMouseDown, let mascot = activeMascot else { return }
        isMouseDown = false

        if hasDragged {
            soundPlayer.playInteraction(.dragRelease)
            mascot.spriteEngine.clearInteractionSprite()
        } else {
            soundPlayer.playInteraction(.click)
            mascot.spriteEngine.playInteractionSprite(.click)
            let work = DispatchWorkItem { [weak self, weak mascot] in
                mascot?.spriteEngine.clearInteractionSprite()
                self?.clickClearWorkItem = nil
            }
            clickClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + clickSpriteDuration, execute: work)
        }
        mascot.characterController.setBeingDragged(false)
        activeMascot = nil
        hasDragged = false
    }
}
