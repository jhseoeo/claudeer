import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var preferencesWindow: PreferencesWindow?

    var assetStore: AssetStore?
    var sessionTracker: SessionTracker?
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

        let view = MenuBarPopoverView(
            controller: self,
            sessionTracker: sessionTracker ?? SessionTracker()
        )
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
    @ObservedObject var sessionTracker: SessionTracker
    @State private var selectedPreset: AreaPreset = .bottom
    @State private var volume: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claudeer")
                .font(.headline)

            Divider()

            sessionsSection

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
        .frame(width: 260)
        .onAppear {
            selectedPreset = controller.currentPreset
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if sessionTracker.sessions.isEmpty {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Sessions (\(sessionTracker.sessions.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(sessionTracker.sessions) { session in
                    SessionRow(
                        session: session,
                        customName: sessionTracker.customName(for: session.id),
                        isHidden: sessionTracker.isHidden(session.id),
                        onToggleHidden: { sessionTracker.toggleHidden(session.id) }
                    )
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    let customName: String?
    let isHidden: Bool
    let onToggleHidden: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.state == .working ? "bolt.fill" : "pause.circle")
                .foregroundColor(session.state == .working ? .accentColor : .secondary)
                .frame(width: 12)
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: onToggleHidden) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isHidden ? "Show mascot" : "Hide mascot")
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .help(tooltip)
    }

    private var label: String {
        if let custom = customName, !custom.isEmpty { return custom }
        if let cwd = session.cwd, let last = cwd.split(separator: "/").last {
            return String(last)
        }
        return String(session.id.prefix(8))
    }

    private var tooltip: String {
        var parts: [String] = []
        if let cwd = session.cwd { parts.append("cwd: \(cwd)") }
        if let pid = session.pid { parts.append("pid: \(pid)") }
        parts.append("session: \(session.id)")
        parts.append("state: \(session.state.rawValue)")
        return parts.joined(separator: "\n")
    }
}
