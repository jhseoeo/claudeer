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
        findAsset(directory: spritesDirectory, baseName: state.rawValue, extensions: Self.spriteExtensions)
    }

    func currentSoundURL(for state: MascotState) -> URL? {
        findAsset(directory: soundsDirectory, baseName: state.rawValue, extensions: Self.soundExtensions)
    }

    func currentInteractionSpriteURL(for key: InteractionSprite) -> URL? {
        findAsset(directory: spritesDirectory, baseName: key.rawValue, extensions: Self.spriteExtensions)
    }

    func currentInteractionSoundURL(for key: InteractionSound) -> URL? {
        findAsset(directory: soundsDirectory, baseName: key.rawValue, extensions: Self.soundExtensions)
    }

    func registerSprite(source: URL, for state: MascotState) throws {
        try registerAsset(source: source, directory: spritesDirectory, baseName: state.rawValue, extensions: Self.spriteExtensions)
        notify()
    }

    func registerSound(source: URL, for state: MascotState) throws {
        try registerAsset(source: source, directory: soundsDirectory, baseName: state.rawValue, extensions: Self.soundExtensions)
        notify()
    }

    func registerInteractionSprite(source: URL, for key: InteractionSprite) throws {
        try registerAsset(source: source, directory: spritesDirectory, baseName: key.rawValue, extensions: Self.spriteExtensions)
        notify()
    }

    func registerInteractionSound(source: URL, for key: InteractionSound) throws {
        try registerAsset(source: source, directory: soundsDirectory, baseName: key.rawValue, extensions: Self.soundExtensions)
        notify()
    }

    func clearSprite(for state: MascotState) {
        clearAssetFiles(directory: spritesDirectory, baseName: state.rawValue, extensions: Self.spriteExtensions)
        notify()
    }

    func clearSound(for state: MascotState) {
        clearAssetFiles(directory: soundsDirectory, baseName: state.rawValue, extensions: Self.soundExtensions)
        notify()
    }

    func clearInteractionSprite(for key: InteractionSprite) {
        clearAssetFiles(directory: spritesDirectory, baseName: key.rawValue, extensions: Self.spriteExtensions)
        notify()
    }

    func clearInteractionSound(for key: InteractionSound) {
        clearAssetFiles(directory: soundsDirectory, baseName: key.rawValue, extensions: Self.soundExtensions)
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
        setConfig(speeches: updated)
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
        setConfig(loops: updated)
    }

    func updateMovement(for state: MascotState, to value: Bool) {
        let m = config.movements
        let updated: MovementSettings
        switch state {
        case .idle:
            updated = MovementSettings(idle: value, working: m.working)
        case .working:
            updated = MovementSettings(idle: m.idle, working: value)
        }
        setConfig(movements: updated)
    }

    func updateSpeed(_ value: Double) {
        setConfig(speed: value)
    }

    private func setConfig(
        speeches: Speeches? = nil,
        loops: LoopSettings? = nil,
        movements: MovementSettings? = nil,
        speed: Double? = nil
    ) {
        config = SpeakiConfig(
            defaultArea: config.defaultArea,
            speeches: speeches ?? config.speeches,
            loops: loops ?? config.loops,
            movements: movements ?? config.movements,
            speed: speed ?? config.speed
        )
        try? config.save(to: configURL)
        notify()
    }

    private func findAsset(directory: URL, baseName: String, extensions: [String]) -> URL? {
        for ext in extensions {
            let url = directory.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func clearAssetFiles(directory: URL, baseName: String, extensions: [String]) {
        for ext in extensions {
            let url = directory.appendingPathComponent("\(baseName).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func registerAsset(source: URL, directory: URL, baseName: String, extensions: [String]) throws {
        clearAssetFiles(directory: directory, baseName: baseName, extensions: extensions)
        let ext = source.pathExtension.lowercased()
        let dest = directory.appendingPathComponent("\(baseName).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
    }

    private func notify() {
        changeVersion += 1
        onAssetsChanged?()
    }
}
