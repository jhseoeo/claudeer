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
}
