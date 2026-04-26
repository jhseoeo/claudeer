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
        let pngFile = store.spritesDirectory.appendingPathComponent("working.png")
        try Data("fake".utf8).write(to: pngFile)
        XCTAssertEqual(store.currentSpriteURL(for: .working), pngFile)
    }

    func testCurrentSoundURLReturnsNilWhenMissing() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertNil(store.currentSoundURL(for: .working))
    }

    func testCurrentSoundURLFindsExistingFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let soundFile = store.soundsDirectory.appendingPathComponent("idle.wav")
        try Data("fake".utf8).write(to: soundFile)
        XCTAssertEqual(store.currentSoundURL(for: .idle), soundFile)
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

        try store.registerSound(source: source, for: .working)

        let dest = store.soundsDirectory.appendingPathComponent("working.wav")
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
        store.clearSprite(for: .working)
        XCTAssertNil(store.currentSpriteURL(for: .working))
    }

    func testClearSoundRemovesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let file = store.soundsDirectory.appendingPathComponent("idle.mp3")
        try Data("data".utf8).write(to: file)

        store.clearSound(for: .idle)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testInitLoadsDefaultConfigWhenAbsent() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.config.defaultArea, SpeakiConfig.default.defaultArea)
        XCTAssertEqual(store.config.speeches.idle, SpeakiConfig.default.speeches.idle)
    }

    func testInitLoadsExistingConfig() throws {
        let custom = SpeakiConfig(
            defaultArea: "top",
            speeches: Speeches(idle: "A", working: "B"),
            loops: LoopSettings(idle: true, working: false),
            movements: MovementSettings(idle: false, working: true),
            speed: 4.0
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        try custom.save(to: configURL)

        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.config.defaultArea, "top")
        XCTAssertEqual(store.config.speeches.idle, "A")
        XCTAssertTrue(store.config.loops.idle)
        XCTAssertFalse(store.config.movements.idle)
        XCTAssertTrue(store.config.movements.working)
        XCTAssertEqual(store.config.speed, 4.0)
    }

    func testUpdateLoopPersistsAndPreservesSpeeches() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateSpeech(for: .idle, text: "Custom idle")
        store.updateLoop(for: .working, to: true)

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertEqual(reloaded.speeches.idle, "Custom idle")
        XCTAssertTrue(reloaded.loops.working)
        XCTAssertFalse(reloaded.loops.idle)
    }

    func testUpdateSpeechPreservesLoops() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateLoop(for: .idle, to: true)
        store.updateSpeech(for: .working, text: "Hi")

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertTrue(reloaded.loops.idle)
        XCTAssertEqual(reloaded.speeches.working, "Hi")
    }

    func testUpdateMovementPersistsAndPreservesOthers() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateSpeech(for: .working, text: "Yo")
        store.updateLoop(for: .idle, to: true)
        store.updateMovement(for: .idle, to: false)

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertFalse(reloaded.movements.idle)
        XCTAssertTrue(reloaded.movements.working)
        XCTAssertEqual(reloaded.speeches.working, "Yo")
        XCTAssertTrue(reloaded.loops.idle)
    }

    func testUpdateSpeedPersistsAndPreservesOthers() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateLoop(for: .working, to: true)
        store.updateMovement(for: .idle, to: false)
        store.updateSpeed(3.0)

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertEqual(reloaded.speed, 3.0)
        XCTAssertTrue(reloaded.loops.working)
        XCTAssertFalse(reloaded.movements.idle)
    }

    func testUpdateSpeechPersistsToDisk() throws {
        let store = AssetStore(baseDirectory: tempDir)
        store.updateSpeech(for: .working, text: "Custom message")

        let reloaded = SpeakiConfig.load(from: store.configURL)
        XCTAssertEqual(reloaded.speeches.working, "Custom message")
        XCTAssertEqual(reloaded.speeches.idle, SpeakiConfig.default.speeches.idle)
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

        store.updateSpeech(for: .idle, text: "Hi")
        XCTAssertEqual(fired, 1)
    }

    func testRegisterInteractionSpriteCopiesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let source = tempDir.appendingPathComponent("source.gif")
        try Data("data".utf8).write(to: source)

        try store.registerInteractionSprite(source: source, for: .drag)

        let dest = store.spritesDirectory.appendingPathComponent("drag.gif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(store.currentInteractionSpriteURL(for: .drag), dest)
    }

    func testRegisterInteractionSoundCopiesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let source = tempDir.appendingPathComponent("ding.wav")
        try Data("audio".utf8).write(to: source)

        try store.registerInteractionSound(source: source, for: .dragPress)

        let dest = store.soundsDirectory.appendingPathComponent("drag_press.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(store.currentInteractionSoundURL(for: .dragPress), dest)
    }

    func testClearInteractionSpriteRemovesFile() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let file = store.spritesDirectory.appendingPathComponent("click.png")
        try Data("data".utf8).write(to: file)

        store.clearInteractionSprite(for: .click)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(store.currentInteractionSpriteURL(for: .click))
    }

    func testInteractionAssetsCoexistWithStateAssets() throws {
        let store = AssetStore(baseDirectory: tempDir)
        let idleSource = tempDir.appendingPathComponent("a.png")
        let dragSource = tempDir.appendingPathComponent("b.png")
        try Data("idle".utf8).write(to: idleSource)
        try Data("drag".utf8).write(to: dragSource)

        try store.registerSprite(source: idleSource, for: .idle)
        try store.registerInteractionSprite(source: dragSource, for: .drag)

        XCTAssertNotNil(store.currentSpriteURL(for: .idle))
        XCTAssertNotNil(store.currentInteractionSpriteURL(for: .drag))

        store.clearInteractionSprite(for: .drag)
        XCTAssertNotNil(store.currentSpriteURL(for: .idle))
        XCTAssertNil(store.currentInteractionSpriteURL(for: .drag))
    }
}
