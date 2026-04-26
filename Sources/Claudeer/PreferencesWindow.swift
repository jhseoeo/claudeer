import AppKit
import SwiftUI

class PreferencesWindow: NSWindow {
    init(assetStore: AssetStore) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Claudeer Preferences"
        isReleasedWhenClosed = false
        center()

        let view = PreferencesView(assetStore: assetStore)
        contentViewController = NSHostingController(rootView: view)
    }

    func showAndFocus() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
