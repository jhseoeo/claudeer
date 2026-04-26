import XCTest
@testable import Claudeer

final class ConfigTests: XCTestCase {
    func testParseConfig() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": {
            "idle": "Need input!",
            "working": "On it!"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertEqual(config.speeches.idle, "Need input!")
        XCTAssertEqual(config.speeches.working, "On it!")
    }

    func testDefaultConfig() {
        let config = SpeakiConfig.default
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertFalse(config.speeches.idle.isEmpty)
        XCTAssertFalse(config.speeches.working.isEmpty)
    }

    func testSaveAndReload() throws {
        let original = SpeakiConfig(
            defaultArea: "top",
            speeches: Speeches(idle: "Halp", working: "Yo")
        )
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try original.save(to: tmpURL)
        let reloaded = SpeakiConfig.load(from: tmpURL)

        XCTAssertEqual(reloaded.defaultArea, "top")
        XCTAssertEqual(reloaded.speeches.idle, "Halp")
        XCTAssertEqual(reloaded.speeches.working, "Yo")
    }
}
