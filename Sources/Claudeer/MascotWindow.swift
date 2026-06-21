import AppKit

/// A transparent, click-through overlay window covering exactly one screen.
/// Multiple displays are handled by one MascotWindow per NSScreen
/// (a single window cannot span displays when "Displays have separate Spaces"
/// is enabled, which is the macOS default), coordinated by OverlayWindowController.
class MascotWindow: NSWindow {
    let displayID: CGDirectDisplayID

    init(screen: NSScreen) {
        self.displayID = screen.displayID
        super.init(
            contentRect: screen.frame,
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
}
