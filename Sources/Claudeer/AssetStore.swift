import Foundation

class AssetStore {
    let baseDirectory: URL
    private(set) var config: SpeakiConfig
    var onAssetsChanged: (() -> Void)?

    var spritesDirectory: URL { baseDirectory.appendingPathComponent("sprites") }
    var soundsDirectory: URL { baseDirectory.appendingPathComponent("sounds") }
    var configURL: URL { baseDirectory.appendingPathComponent("config.json") }

    static let spriteExtensions = ["gif", "apng", "png", "jpg"]
    static let soundExtensions = ["wav", "mp3", "aiff", "m4a"]

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(
            at: baseDirectory.appendingPathComponent("sprites"),
            withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: baseDirectory.appendingPathComponent("sounds"),
            withIntermediateDirectories: true)
        self.config = SpeakiConfig.load(
            from: baseDirectory.appendingPathComponent("config.json"))
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Claudeer")
    }

    func currentSpriteURL(for state: SpriteState) -> URL? {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func currentSoundURL(for event: EventType) -> URL? {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func registerSprite(source: URL, for state: SpriteState) throws {
        clearSpriteFiles(for: state)
        let ext = source.pathExtension.lowercased()
        let dest = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        onAssetsChanged?()
    }

    func registerSound(source: URL, for event: EventType) throws {
        clearSoundFiles(for: event)
        let ext = source.pathExtension.lowercased()
        let dest = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        onAssetsChanged?()
    }

    func clearSprite(for state: SpriteState) {
        clearSpriteFiles(for: state)
        onAssetsChanged?()
    }

    func clearSound(for event: EventType) {
        clearSoundFiles(for: event)
        onAssetsChanged?()
    }

    func updateSpeech(for event: EventType, text: String) {
        let s = config.speeches
        let updated: Speeches
        switch event {
        case .sessionStart:
            updated = Speeches(sessionStart: text, needInput: s.needInput, sessionEnd: s.sessionEnd)
        case .needInput:
            updated = Speeches(sessionStart: s.sessionStart, needInput: text, sessionEnd: s.sessionEnd)
        case .sessionEnd:
            updated = Speeches(sessionStart: s.sessionStart, needInput: s.needInput, sessionEnd: text)
        }
        config = SpeakiConfig(defaultArea: config.defaultArea, speeches: updated)
        try? config.save(to: configURL)
        onAssetsChanged?()
    }

    private func clearSpriteFiles(for state: SpriteState) {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func clearSoundFiles(for event: EventType) {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }
}
