import AppKit

class InteractionController: NSObject, InteractionViewDelegate {
    private let overlay: OverlayWindowController
    private let mascotManager: MascotManager
    private let soundPlayer: SoundPlayer

    /// Called when a mascot is double-clicked (used to focus its session's terminal).
    var onMascotDoubleClicked: ((Mascot) -> Void)?

    /// Called when the user picks "Hide this character" from a mascot's right-click menu.
    var onMascotHideRequested: ((Mascot) -> Void)?

    /// Called when the user picks "Rename…" from a mascot's right-click menu.
    var onMascotRenameRequested: ((Mascot) -> Void)?

    private var pollingTimer: Timer?
    private var clickClearWorkItem: DispatchWorkItem?

    private var isMouseDown = false
    private var hasDragged = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownGlobal: NSPoint = .zero
    private weak var activeMascot: Mascot?
    private weak var activeWindow: NSWindow?
    private weak var rightClickedMascot: Mascot?

    private let dragThreshold: CGFloat = 4.0
    private let clickSpriteDuration: TimeInterval = 1.0

    init(
        overlay: OverlayWindowController,
        mascotManager: MascotManager,
        soundPlayer: SoundPlayer
    ) {
        self.overlay = overlay
        self.mascotManager = mascotManager
        self.soundPlayer = soundPlayer
        super.init()
        overlay.interactionDelegate = self
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

    /// Only the overlay window the cursor is hovering a mascot in should receive mouse
    /// events; all others stay click-through. While dragging, the window that captured
    /// the drag keeps receiving events.
    private func updateCursorHover() {
        if isMouseDown {
            setExclusiveReceiver(activeWindow)
            return
        }
        let mouse = NSEvent.mouseLocation
        let host = mascotManager.allMascots
            .first { !$0.isHidden && $0.globalFrame.contains(mouse) }?
            .spriteEngine.view.window
        setExclusiveReceiver(host)
    }

    private func setExclusiveReceiver(_ receiver: NSWindow?) {
        for window in overlay.windows {
            window.ignoresMouseEvents = (window !== receiver)
        }
    }

    private func globalPoint(_ locationInWindow: NSPoint, in view: InteractionView) -> NSPoint? {
        guard let window = view.window else { return nil }
        return NSPoint(
            x: window.frame.minX + locationInWindow.x,
            y: window.frame.minY + locationInWindow.y
        )
    }

    func interactionMouseDown(at locationInWindow: NSPoint, in view: InteractionView) {
        guard let global = globalPoint(locationInWindow, in: view) else { return }
        let target = mascotManager.allMascots.first { !$0.isHidden && $0.globalFrame.contains(global) }
        guard let target = target else { return }

        clickClearWorkItem?.cancel()
        clickClearWorkItem = nil
        target.spriteEngine.clearInteractionSprite()

        isMouseDown = true
        hasDragged = false
        mouseDownGlobal = global
        activeWindow = view.window
        let frame = target.globalFrame
        dragOffset = NSPoint(
            x: frame.origin.x - global.x,
            y: frame.origin.y - global.y
        )
        target.characterController.setBeingDragged(true)
        activeMascot = target
    }

    func interactionMouseDragged(to locationInWindow: NSPoint, in view: InteractionView) {
        guard isMouseDown, let mascot = activeMascot,
              let global = globalPoint(locationInWindow, in: view) else { return }
        let dx = global.x - mouseDownGlobal.x
        let dy = global.y - mouseDownGlobal.y
        let dist = sqrt(dx * dx + dy * dy)

        if !hasDragged && dist >= dragThreshold {
            hasDragged = true
            mascot.spriteEngine.playInteractionSprite(.drag)
            soundPlayer.playInteraction(.dragPress)
        }
        if hasDragged {
            let newGlobalOrigin = NSPoint(
                x: global.x + dragOffset.x,
                y: global.y + dragOffset.y
            )
            mascot.characterController.setSpritePosition(newGlobalOrigin)
        }
    }

    func interactionMouseUp(at locationInWindow: NSPoint, clickCount: Int, in view: InteractionView) {
        guard isMouseDown, let mascot = activeMascot else { return }
        isMouseDown = false

        if hasDragged {
            soundPlayer.playInteraction(.dragRelease)
            mascot.spriteEngine.clearInteractionSprite()
        } else if clickCount >= 2 {
            // Double-click: focus the terminal hosting this mascot's session.
            mascot.spriteEngine.clearInteractionSprite()
            onMascotDoubleClicked?(mascot)
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
        activeWindow = nil
        hasDragged = false
    }

    func interactionRightMouseDown(at locationInWindow: NSPoint, in view: InteractionView) {
        guard let global = globalPoint(locationInWindow, in: view) else { return }
        guard let target = mascotManager.allMascots.first(where: {
            !$0.isHidden && $0.globalFrame.contains(global)
        }) else { return }

        rightClickedMascot = target
        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: "Rename…",
            action: #selector(renameClickedMascot),
            keyEquivalent: ""
        )
        renameItem.target = self
        menu.addItem(renameItem)

        menu.addItem(.separator())

        let item = NSMenuItem(
            title: "Hide this character",
            action: #selector(hideClickedMascot),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)

        let viewPoint = view.convert(locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: view)
    }

    @objc private func renameClickedMascot() {
        guard let mascot = rightClickedMascot else { return }
        onMascotRenameRequested?(mascot)
        rightClickedMascot = nil
    }

    @objc private func hideClickedMascot() {
        guard let mascot = rightClickedMascot else { return }
        onMascotHideRequested?(mascot)
        rightClickedMascot = nil
    }
}
