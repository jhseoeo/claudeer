import XCTest
@testable import Claudeer

final class AssetStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInitCreatesDirectories() {
        _ = AssetStore(baseDirectory: tempDir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("sprites").path,
            isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("sounds").path,
            isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testPathGetters() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.spritesDirectory, tempDir.appendingPathComponent("sprites"))
        XCTAssertEqual(store.soundsDirectory, tempDir.appendingPathComponent("sounds"))
    }

    func testCurrentSpriteURLReturnsNilWhenMissing() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertNil(store.currentSpriteURL(for: .idle))
    }

    func testCurrentSpriteURLFindsExistingFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let spriteFile = store.spritesDirectory.appendingPathComponent("idle.gif")
        try Data("fake".utf8).write(to: spriteFile)
        XCTAssertEqual(store.currentSpriteURL(for: .idle), spriteFile)
    }

    func testCurrentSpriteURLPicksFirstMatchingExtension() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let pngFile = store.spritesDirectory.appendingPathComponent("walk.png")
        try Data("fake".utf8).write(to: pngFile)
        XCTAssertEqual(store.currentSpriteURL(for: .walk), pngFile)
    }

    func testCurrentSoundURLReturnsNilWhenMissing() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertNil(store.currentSoundURL(for: .needInput))
    }

    func testCurrentSoundURLFindsExistingFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let soundFile = store.soundsDirectory.appendingPathComponent("session_start.wav")
        try Data("fake".utf8).write(to: soundFile)
        XCTAssertEqual(store.currentSoundURL(for: .sessionStart), soundFile)
    }

    func testRegisterSpriteCopiesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let source = tempDir.appendingPathComponent("source.gif")
        try Data("data".utf8).write(to: source)

        try store.registerSprite(source: source, for: .idle)

        let dest = store.spritesDirectory.appendingPathComponent("idle.gif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(try Data(contentsOf: dest), Data("data".utf8))
    }

    func testRegisterSpriteReplacesDifferentExtension() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let oldFile = store.spritesDirectory.appendingPathComponent("idle.png")
        try Data("old".utf8).write(to: oldFile)

        let source = tempDir.appendingPathComponent("source.gif")
        try Data("new".utf8).write(to: source)
        try store.registerSprite(source: source, for: .idle)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        let newFile = store.spritesDirectory.appendingPathComponent("idle.gif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
    }

    func testRegisterSoundCopiesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let source = tempDir.appendingPathComponent("ding.wav")
        try Data("audio".utf8).write(to: source)

        try store.registerSound(source: source, for: .needInput)

        let dest = store.soundsDirectory.appendingPathComponent("need_input.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testClearSpriteRemovesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let file = store.spritesDirectory.appendingPathComponent("idle.gif")
        try Data("data".utf8).write(to: file)

        store.clearSprite(for: .idle)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(store.currentSpriteURL(for: .idle))
    }

    func testClearSpriteWhenAbsentIsNoOp() {
        let store = AssetStore(baseDirectory: tempDir)
        store.clearSprite(for: .alert)
        XCTAssertNil(store.currentSpriteURL(for: .alert))
    }

    func testClearSoundRemovesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let file = store.soundsDirectory.appendingPathComponent("session_end.mp3")
        try Data("data".utf8).write(to: file)

        store.clearSound(for: .sessionEnd)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testInitLoadsDefaultConfigWhenAbsent() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.config.defaultArea, SpeakiConfig.default.defaultArea)
        XCTAssertEqual(store.config.speeches.sessionStart, SpeakiConfig.default.speeches.sessionStart)
    }

    func testInitLoadsExistingConfig() throws {
        let custom = SpeakiConfig(
            defaultArea: "top",
            speeches: Speeches(sessionStart: "A", needInput: "B", sessionEnd: "C")
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        try custom.save(to: configURL)

        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.config.defaultArea, "top")
        XCTAssertEqual(store.config.speeches.sessionStart, "A")
    }

    func testUpdateSpeechPersistsToDisk() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateSpeech(for: .needInput, text: "Custom message")

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertEqual(reloaded.speeches.needInput, "Custom message")
        XCTAssertEqual(reloaded.speeches.sessionStart, SpeakiConfig.default.speeches.sessionStart)
    }

    func testOnAssetsChangedFiresAfterRegister() throws {
        let store = AssetStore(baseDirectory: tempDir)
        var fired = 0
        store.onAssetsChanged = { fired += 1 }

        let source = tempDir.appendingPathComponent("s.gif")
        try Data("d".utf8).write(to: source)
        try store.registerSprite(source: source, for: .idle)

        XCTAssertEqual(fired, 1)
    }

    func testOnAssetsChangedFiresAfterClear() {
        let store = AssetStore(baseDirectory: tempDir)
        var fired = 0
        store.onAssetsChanged = { fired += 1 }

        store.clearSprite(for: .idle)
        XCTAssertEqual(fired, 1)
    }

    func testOnAssetsChangedFiresAfterUpdateSpeech() {
        let store = AssetStore(baseDirectory: tempDir)
        var fired = 0
        store.onAssetsChanged = { fired += 1 }

        store.updateSpeech(for: .sessionStart, text: "Hi")
        XCTAssertEqual(fired, 1)
    }
}
