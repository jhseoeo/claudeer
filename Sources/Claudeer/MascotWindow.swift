import AppKit

class MascotWindow: NSWindow {
    init() {
        let initialFrame = MascotWindow.unionFrame() ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = false
        hasShadow = false
    }

    func refreshFrameToAllScreens() {
        guard let frame = MascotWindow.unionFrame() else { return }
        setFrame(frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private static func unionFrame() -> NSRect? {
        let frame = NSScreen.boundingFrame()
        return frame.isNull || frame.isEmpty ? nil : frame
    }
}
