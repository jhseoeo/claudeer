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
        statusItem?.autosaveName = "Claudeer"
        statusItem?.isVisible = true
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
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = hosting
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Claudeer")
                .font(.headline)

            Divider()

            Picker("Area", selection: $selectedPreset) {
                ForEach(AreaPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: selectedPreset) { newValue in
                controller.onAreaChanged?(newValue)
            }

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
            .buttonStyle(.bordered)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 240)
        .onAppear {
            selectedPreset = controller.currentPreset
        }
    }
}
