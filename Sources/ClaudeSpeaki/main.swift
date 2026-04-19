import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mascotWindow: MascotWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        mascotWindow = MascotWindow()
        mascotWindow?.makeKeyAndOrderFront(nil)

        print("Claude Speaki started — overlay window active")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
