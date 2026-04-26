import Foundation

class AssetStore {
    let baseDirectory: URL

    var spritesDirectory: URL { baseDirectory.appendingPathComponent("sprites") }
    var soundsDirectory: URL { baseDirectory.appendingPathComponent("sounds") }
    var configURL: URL { baseDirectory.appendingPathComponent("config.json") }

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(
            at: spritesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: soundsDirectory, withIntermediateDirectories: true)
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Claudeer")
    }

    static let spriteExtensions = ["gif", "apng", "png", "jpg"]
    static let soundExtensions = ["wav", "mp3", "aiff", "m4a"]

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
        clearSprite(for: state)
        let ext = source.pathExtension.lowercased()
        let dest = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
    }

    func registerSound(source: URL, for event: EventType) throws {
        clearSound(for: event)
        let ext = source.pathExtension.lowercased()
        let dest = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
    }

    func clearSprite(for state: SpriteState) {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func clearSound(for event: EventType) {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }
}
