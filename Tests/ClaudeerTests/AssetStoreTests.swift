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
}
