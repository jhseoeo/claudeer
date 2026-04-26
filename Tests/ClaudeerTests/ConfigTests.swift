import XCTest
@testable import Claudeer

final class ConfigTests: XCTestCase {
    func testParseConfig() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": {
            "session_start": "Hi!",
            "need_input": "Input please",
            "session_end": "Bye"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertEqual(config.speeches.sessionStart, "Hi!")
        XCTAssertEqual(config.speeches.needInput, "Input please")
        XCTAssertEqual(config.speeches.sessionEnd, "Bye")
    }

    func testDefaultConfig() {
        let config = SpeakiConfig.default
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertFalse(config.speeches.needInput.isEmpty)
    }

    func testSaveAndReload() throws {
        let original = SpeakiConfig(
            defaultArea: "top",
            speeches: Speeches(sessionStart: "Yo", needInput: "Halp", sessionEnd: "Cya")
        )
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try original.save(to: tmpURL)
        let reloaded = SpeakiConfig.load(from: tmpURL)

        XCTAssertEqual(reloaded.defaultArea, "top")
        XCTAssertEqual(reloaded.speeches.sessionStart, "Yo")
        XCTAssertEqual(reloaded.speeches.needInput, "Halp")
        XCTAssertEqual(reloaded.speeches.sessionEnd, "Cya")
    }
}
