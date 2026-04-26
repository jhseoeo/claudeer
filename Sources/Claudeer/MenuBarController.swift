import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var preferencesWindow: PreferencesWindow?

    var assetStore: AssetStore?
    var onAreaChanged: ((AreaPreset) -> Void)?
    var onVolumeChanged: ((Float) -> Void)?
    var currentPreset: AreaPreset = .bottom

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Claudeer") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "🐾"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        let view = MenuBarPopoverView(controller: self)
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 320)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openPreferences() {
        guard let store = assetStore else { return }
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(assetStore: store)
        }
        popover?.performClose(nil)
        preferencesWindow?.showAndFocus()
    }
}

struct MenuBarPopoverView: View {
    let controller: MenuBarController
    @State private var selectedPreset: AreaPreset = .bottom
    @State private var volume: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claudeer")
                .font(.headline)

            Divider()

            Text("Area").font(.subheadline.bold())
            ForEach(AreaPreset.allCases, id: \.self) { preset in
                Button(action: {
                    selectedPreset = preset
                    controller.onAreaChanged?(preset)
                }) {
                    HStack {
                        Image(systemName: selectedPreset == preset ? "checkmark.circle.fill" : "circle")
                        Text(preset.displayName)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Text("Volume")
                Slider(value: $volume, in: 0...1) { _ in
                    controller.onVolumeChanged?(Float(volume))
                }
            }

            Divider()

            Button("Preferences...") {
                controller.openPreferences()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .onAppear {
            selectedPreset = controller.currentPreset
        }
    }
}
