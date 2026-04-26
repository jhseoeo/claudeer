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
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private var spritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprites").font(.headline)
            ForEach(SpriteState.allCases, id: \.self) { state in
                AssetSlotRow(
                    label: state.rawValue.capitalized,
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
            ForEach(EventType.allCases, id: \.self) { event in
                AssetSlotRow(
                    label: eventLabel(event),
                    currentURL: assetStore.currentSoundURL(for: event),
                    onChoose: { chooseSound(for: event) },
                    onClear: { assetStore.clearSound(for: event) }
                )
                .id(assetStore.changeVersion)
            }
        }
    }

    private var speechesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speeches").font(.headline)
            SpeechRow(assetStore: assetStore, event: .sessionStart, label: "Session Start")
            SpeechRow(assetStore: assetStore, event: .needInput, label: "Need Input")
            SpeechRow(assetStore: assetStore, event: .sessionEnd, label: "Session End")
        }
    }

    private func eventLabel(_ event: EventType) -> String {
        switch event {
        case .sessionStart: return "Session Start"
        case .needInput: return "Need Input"
        case .sessionEnd: return "Session End"
        }
    }

    private func chooseSprite(for state: SpriteState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try assetStore.registerSprite(source: url, for: state)
        } catch {
            presentError(error)
        }
    }

    private func chooseSound(for event: EventType) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try assetStore.registerSound(source: url, for: event)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not register file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct AssetSlotRow: View {
    let label: String
    let currentURL: URL?
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Text(currentURL?.lastPathComponent ?? "Not registered")
                .foregroundColor(currentURL == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose...", action: onChoose)
            if currentURL != nil {
                Button("Clear", action: onClear)
            }
        }
    }
}

private struct SpeechRow: View {
    @ObservedObject var assetStore: AssetStore
    let event: EventType
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
        switch event {
        case .sessionStart: return assetStore.config.speeches.sessionStart
        case .needInput: return assetStore.config.speeches.needInput
        case .sessionEnd: return assetStore.config.speeches.sessionEnd
        }
    }

    private func commit() {
        if draft != currentText {
            assetStore.updateSpeech(for: event, text: draft)
        }
    }
}
