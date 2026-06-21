import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var assetStore: AssetStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                spritesSection
                Divider()
                soundsSection
                Divider()
                speechesSection
                Divider()
                movementSection
                Divider()
                screenSection
                Divider()
                flipSection
                Divider()
                labelsSection
                Divider()
                interactionsSection
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    private var spritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprites").font(.headline)
            ForEach(MascotState.allCases, id: \.self) { state in
                SpriteSlotRow(
                    label: state.displayName,
                    currentURL: assetStore.currentSpriteURL(for: state),
                    onChoose: { chooseSprite(for: state) },
                    onClear: { assetStore.clearSprite(for: state) }
                )
                .id(assetStore.changeVersion)
            }
        }
    }

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sounds").font(.headline)
            ForEach(MascotState.allCases, id: \.self) { state in
                SoundSlotRow(
                    label: state.displayName,
                    currentURL: assetStore.currentSoundURL(for: state),
                    loop: assetStore.config.loops.value(for: state),
                    onChoose: { chooseSound(for: state) },
                    onClear: { assetStore.clearSound(for: state) },
                    onLoopChange: { assetStore.updateLoop(for: state, to: $0) }
                )
                .id(assetStore.changeVersion)
            }
        }
    }


    private var speechesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speeches").font(.headline)
            ForEach(MascotState.allCases, id: \.self) { state in
                SpeechRow(assetStore: assetStore, state: state, label: state.displayName)
            }
        }
    }

    private var movementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement").font(.headline)
            ForEach(MascotState.allCases, id: \.self) { state in
                HStack {
                    Text(state.displayName)
                        .frame(width: 80, alignment: .leading)
                    Toggle("Move while \(state.rawValue)", isOn: Binding(
                        get: { assetStore.config.movements.value(for: state) },
                        set: { assetStore.updateMovement(for: state, to: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    Spacer()
                }
            }
            HStack {
                Text("Speed")
                    .frame(width: 80, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { assetStore.config.speed },
                        set: { assetStore.updateSpeed($0) }
                    ),
                    in: SpeakiConfig.speedRange,
                    minimumValueLabel: Text("Slow").font(.caption).foregroundColor(.secondary),
                    maximumValueLabel: Text("Fast").font(.caption).foregroundColor(.secondary),
                    label: { EmptyView() }
                )
            }
        }
    }

    private var screenSection: some View {
        ScreenPickerSection(assetStore: assetStore)
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Labels").font(.headline)
            Toggle("Show session name under each mascot", isOn: Binding(
                get: { assetStore.config.showSessionLabel },
                set: { assetStore.updateShowSessionLabel($0) }
            ))
            .toggleStyle(.checkbox)
        }
    }

    private var flipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flip").font(.headline)
            Toggle("Face movement direction", isOn: Binding(
                get: { assetStore.config.flips.directional },
                set: { assetStore.updateFlipDirectional($0) }
            ))
            .toggleStyle(.checkbox)
            Toggle("Mirror sprite by default", isOn: Binding(
                get: { assetStore.config.flips.mirrored },
                set: { assetStore.updateFlipMirrored($0) }
            ))
            .toggleStyle(.checkbox)
        }
    }

    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interactions").font(.headline)
            Text("Sprites")
                .font(.subheadline)
                .foregroundColor(.secondary)
            ForEach(InteractionSprite.allCases, id: \.self) { key in
                SpriteSlotRow(
                    label: key.displayName,
                    currentURL: assetStore.currentInteractionSpriteURL(for: key),
                    onChoose: { chooseInteractionSprite(for: key) },
                    onClear: { assetStore.clearInteractionSprite(for: key) }
                )
                .id(assetStore.changeVersion)
            }
            Text("Sounds")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            ForEach(InteractionSound.allCases, id: \.self) { key in
                SoundSlotRow(
                    label: key.displayName,
                    currentURL: assetStore.currentInteractionSoundURL(for: key),
                    loop: nil,
                    onChoose: { chooseInteractionSound(for: key) },
                    onClear: { assetStore.clearInteractionSound(for: key) },
                    onLoopChange: nil
                )
                .id(assetStore.changeVersion)
            }
        }
    }

    private func chooseSprite(for state: MascotState) {
        runSpritePanel { url in
            try assetStore.registerSprite(source: url, for: state)
        }
    }

    private func chooseSound(for state: MascotState) {
        runSoundPanel { url in
            try assetStore.registerSound(source: url, for: state)
        }
    }

    private func chooseInteractionSprite(for key: InteractionSprite) {
        runSpritePanel { url in
            try assetStore.registerInteractionSprite(source: url, for: key)
        }
    }

    private func chooseInteractionSound(for key: InteractionSound) {
        runSoundPanel { url in
            try assetStore.registerInteractionSound(source: url, for: key)
        }
    }

    private func runSpritePanel(_ action: (URL) throws -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try action(url) } catch { presentError(error) }
    }

    private func runSoundPanel(_ action: (URL) throws -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try action(url) } catch { presentError(error) }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not register file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct ScreenPickerSection: View {
    @ObservedObject var assetStore: AssetStore
    @State private var availableScreens: [NSScreen] = NSScreen.screens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen").font(.headline)
            HStack {
                Text("Display on")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: selection) {
                    Text("All Screens").tag(String?.none)
                    ForEach(availableScreens, id: \.displayID) { screen in
                        Text(label(for: screen))
                            .tag(screen.stableIdentifier as String?)
                    }
                    if let savedID = assetStore.config.targetScreenID,
                       !availableScreens.contains(where: { $0.stableIdentifier == savedID }) {
                        Text("Saved display (disconnected)")
                            .tag(savedID as String?)
                    }
                }
                .labelsHidden()
            }
            Text("Choose “All Screens” to let the mascot roam everywhere, or pin it to a single display.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            availableScreens = NSScreen.screens
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { assetStore.config.targetScreenID },
            set: { assetStore.updateTargetScreen($0) }
        )
    }

    private func label(for screen: NSScreen) -> String {
        let name = screen.localizedName
        let w = Int(screen.frame.width)
        let h = Int(screen.frame.height)
        return "\(name) (\(w)×\(h))"
    }
}

private struct SpriteSlotRow: View {
    let label: String
    let currentURL: URL?
    let onChoose: () -> Void
    let onClear: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            thumbnailView
                .frame(width: 32, height: 32)
            Text(currentURL?.lastPathComponent ?? "Not registered")
                .foregroundColor(currentURL == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose...", action: onChoose)
            if currentURL != nil {
                Button("Clear", action: onClear)
            }
        }
        .onAppear { loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(3)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.12))
        }
    }

    private func loadThumbnail() {
        thumbnail = currentURL.flatMap { NSImage(contentsOf: $0) }
    }
}

private struct SoundSlotRow: View {
    let label: String
    let currentURL: URL?
    let loop: Bool?
    let onChoose: () -> Void
    let onClear: () -> Void
    let onLoopChange: ((Bool) -> Void)?
    @State private var previewSound: NSSound?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Button(action: playPreview) {
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(currentURL == nil)
            .help(currentURL == nil ? "" : "Preview")
            Text(currentURL?.lastPathComponent ?? "Not registered")
                .foregroundColor(currentURL == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let loop = loop, let onLoopChange = onLoopChange {
                Toggle("Loop", isOn: Binding(get: { loop }, set: onLoopChange))
                    .toggleStyle(.checkbox)
                    .disabled(currentURL == nil)
            }
            Button("Choose...", action: onChoose)
            if currentURL != nil {
                Button("Clear", action: onClear)
            }
        }
    }

    private func playPreview() {
        guard let url = currentURL else { return }
        previewSound?.stop()
        let sound = NSSound(contentsOf: url, byReference: false)
        previewSound = sound
        sound?.play()
    }
}

private struct SpeechRow: View {
    @ObservedObject var assetStore: AssetStore
    let state: MascotState
    let label: String
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { draft = currentText }
                .onChange(of: isFocused) { focused in
                    if !focused { commit() }
                }
                .onSubmit { commit() }
        }
    }

    private var currentText: String {
        switch state {
        case .idle: return assetStore.config.speeches.idle
        case .working: return assetStore.config.speeches.working
        }
    }

    private func commit() {
        if draft != currentText {
            assetStore.updateSpeech(for: state, text: draft)
        }
    }
}
