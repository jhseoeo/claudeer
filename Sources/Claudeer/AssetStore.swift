import Combine
import Foundation

class AssetStore: ObservableObject {
    let baseDirectory: URL
    @Published private(set) var config: SpeakiConfig
    @Published private(set) var changeVersion: Int = 0
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

    func currentSpriteURL(for state: MascotState) -> URL? {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func currentSoundURL(for state: MascotState) -> URL? {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func registerSprite(source: URL, for state: MascotState) throws {
        clearSpriteFiles(for: state)
        let ext = source.pathExtension.lowercased()
        let dest = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        notify()
    }

    func registerSound(source: URL, for state: MascotState) throws {
        clearSoundFiles(for: state)
        let ext = source.pathExtension.lowercased()
        let dest = soundsDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        notify()
    }

    func clearSprite(for state: MascotState) {
        clearSpriteFiles(for: state)
        notify()
    }

    func clearSound(for state: MascotState) {
        clearSoundFiles(for: state)
        notify()
    }

    func updateSpeech(for state: MascotState, text: String) {
        let s = config.speeches
        let updated: Speeches
        switch state {
        case .idle:
            updated = Speeches(idle: text, working: s.working)
        case .working:
            updated = Speeches(idle: s.idle, working: text)
        }
        config = SpeakiConfig(defaultArea: config.defaultArea, speeches: updated, loops: config.loops)
        try? config.save(to: configURL)
        notify()
    }

    func updateLoop(for state: MascotState, to value: Bool) {
        let l = config.loops
        let updated: LoopSettings
        switch state {
        case .idle:
            updated = LoopSettings(idle: value, working: l.working)
        case .working:
            updated = LoopSettings(idle: l.idle, working: value)
        }
        config = SpeakiConfig(defaultArea: config.defaultArea, speeches: config.speeches, loops: updated)
        try? config.save(to: configURL)
        notify()
    }

    private func clearSpriteFiles(for state: MascotState) {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func clearSoundFiles(for state: MascotState) {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func notify() {
        changeVersion += 1
        onAssetsChanged?()
    }
}
