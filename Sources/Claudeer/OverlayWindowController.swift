import AppKit

/// Decides which overlay view should host content at a given global screen point.
protocol MascotPlacer: AnyObject {
    /// The overlay content view that should host content at `point` (global screen
    /// coordinates) and that view's global origin, so callers can convert
    /// global → window-local. Returns nil when there are no overlay windows.
    func hostView(forGlobalPoint point: NSPoint) -> (view: NSView, globalOrigin: NSPoint)?
}

/// Owns one transparent overlay window per active screen and routes content to the
/// correct window based on global coordinates. This is the macOS-correct way to draw
/// across multiple displays: a single window cannot span displays when "Displays have
/// separate Spaces" is on (the default), so each display gets its own window and a
/// mascot is reparented between them as it crosses the boundary.
class OverlayWindowController: MascotPlacer {
    private(set) var windows: [MascotWindow] = []
    private var targetScreenID: String?
    private var visible = false
    weak var interactionDelegate: InteractionViewDelegate?

    /// Set which display(s) to cover and (re)build the windows. Pass nil for all screens.
    func configure(targetScreenID: String?) {
        self.targetScreenID = targetScreenID
        rebuild()
    }

    /// Rebuild windows to match the current set of active screens. Safe to call on
    /// screen connect/disconnect/rearrange; preserves visibility.
    func rebuild() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()

        for screen in NSScreen.screens(matching: targetScreenID) {
            let window = MascotWindow(screen: screen)
            let contentView = InteractionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            contentView.wantsLayer = true
            contentView.delegate = interactionDelegate
            window.contentView = contentView
            windows.append(window)
        }

        if visible { showAll() }
    }

    func showAll() {
        visible = true
        for window in windows { window.orderFront(nil) }
    }

    func hideAll() {
        visible = false
        for window in windows { window.orderOut(nil) }
    }

    // MARK: - MascotPlacer

    func hostView(forGlobalPoint point: NSPoint) -> (view: NSView, globalOrigin: NSPoint)? {
        guard !windows.isEmpty else { return nil }
        let frames = windows.map { $0.frame }
        guard let index = Self.hostIndex(forGlobalPoint: point, screenFrames: frames),
              let contentView = windows[index].contentView else { return nil }
        return (contentView, frames[index].origin)
    }

    /// Pure selection logic: index of the screen frame containing `point`, else the
    /// nearest frame by center distance. Extracted for unit testing.
    static func hostIndex(forGlobalPoint point: NSPoint, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        if let containing = screenFrames.firstIndex(where: { $0.contains(point) }) {
            return containing
        }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screenFrames.enumerated() {
            let dx = frame.midX - point.x
            let dy = frame.midY - point.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
