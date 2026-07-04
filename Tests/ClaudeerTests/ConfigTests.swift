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
          },
          "loops": {
            "idle": false,
            "working": true
          },
          "movements": {
            "idle": false,
            "working": true
          },
          "speed": 3.5,
          "flips": {
            "directional": true,
            "mirrored": true
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertEqual(config.speeches.idle, "Need input!")
        XCTAssertEqual(config.speeches.working, "On it!")
        XCTAssertFalse(config.loops.idle)
        XCTAssertTrue(config.loops.working)
        XCTAssertFalse(config.movements.idle)
        XCTAssertTrue(config.movements.working)
        XCTAssertEqual(config.speed, 3.5)
        XCTAssertTrue(config.flips.directional)
        XCTAssertTrue(config.flips.mirrored)
    }

    func testParseConfigWithoutLoopsDefaultsOff() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertFalse(config.loops.idle)
        XCTAssertFalse(config.loops.working)
    }

    func testParseConfigWithoutMovementsDefaultsAllOn() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertTrue(config.movements.idle)
        XCTAssertTrue(config.movements.working)
    }

    func testParseConfigWithoutSpeedDefaultsToDefault() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertEqual(config.speed, SpeakiConfig.defaultSpeed)
    }

    func testParseConfigWithoutFlipsDefaultsOff() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertFalse(config.flips.directional)
        XCTAssertFalse(config.flips.mirrored)
    }

    func testDefaultConfig() {
        let config = SpeakiConfig.default
        XCTAssertEqual(config.defaultArea, "bottom")
        XCTAssertFalse(config.speeches.idle.isEmpty)
        XCTAssertFalse(config.speeches.working.isEmpty)
        XCTAssertFalse(config.loops.idle)
        XCTAssertFalse(config.loops.working)
        XCTAssertTrue(config.movements.idle)
        XCTAssertTrue(config.movements.working)
        XCTAssertEqual(config.speed, SpeakiConfig.defaultSpeed)
        XCTAssertFalse(config.flips.directional)
        XCTAssertFalse(config.flips.mirrored)
    }

    func testSaveAndReload() throws {
        let original = SpeakiConfig(
            defaultArea: "top",
            speeches: Speeches(idle: "Halp", working: "Yo"),
            loops: LoopSettings(idle: true, working: false),
            movements: MovementSettings(idle: false, working: true),
            speed: 4.0,
            flips: FlipSettings(directional: true, mirrored: false)
        )
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try original.save(to: tmpURL)
        let reloaded = SpeakiConfig.load(from: tmpURL)

        XCTAssertEqual(reloaded.defaultArea, "top")
        XCTAssertEqual(reloaded.speeches.idle, "Halp")
        XCTAssertEqual(reloaded.speeches.working, "Yo")
        XCTAssertTrue(reloaded.loops.idle)
        XCTAssertFalse(reloaded.loops.working)
        XCTAssertFalse(reloaded.movements.idle)
        XCTAssertTrue(reloaded.movements.working)
        XCTAssertEqual(reloaded.speed, 4.0)
        XCTAssertTrue(reloaded.flips.directional)
        XCTAssertFalse(reloaded.flips.mirrored)
    }

    func testParseConfigWithNtfy() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" },
          "ntfy": {
            "enabled": true,
            "server": "https://ntfy.example.com",
            "topic": "my-claude",
            "token": "tk_secret"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertTrue(config.ntfy.enabled)
        XCTAssertEqual(config.ntfy.server, "https://ntfy.example.com")
        XCTAssertEqual(config.ntfy.topic, "my-claude")
        XCTAssertEqual(config.ntfy.token, "tk_secret")
    }

    func testParseConfigWithoutNtfyDefaultsOff() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertFalse(config.ntfy.enabled)
        XCTAssertEqual(config.ntfy.server, "https://ntfy.sh")
        XCTAssertTrue(config.ntfy.topic.isEmpty)
        XCTAssertNil(config.ntfy.token)
    }

    func testDefaultConfigNtfyOff() {
        let config = SpeakiConfig.default
        XCTAssertFalse(config.ntfy.enabled)
        XCTAssertEqual(config.ntfy.server, "https://ntfy.sh")
        XCTAssertTrue(config.ntfy.topic.isEmpty)
    }

    func testSaveAndReloadNtfy() throws {
        let original = SpeakiConfig(
            defaultArea: "bottom",
            speeches: Speeches(idle: "a", working: "b"),
            loops: .off,
            movements: .allOn,
            speed: 2.0,
            flips: .off,
            ntfy: NtfySettings(enabled: true, server: "https://n.example", topic: "t", token: "k")
        )
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try original.save(to: tmpURL)
        let reloaded = SpeakiConfig.load(from: tmpURL)

        XCTAssertTrue(reloaded.ntfy.enabled)
        XCTAssertEqual(reloaded.ntfy.server, "https://n.example")
        XCTAssertEqual(reloaded.ntfy.topic, "t")
        XCTAssertEqual(reloaded.ntfy.token, "k")
    }

    func testParseConfigWithFlockingAndCursorGather() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" },
          "flocking": { "enabled": false },
          "cursor_gather": { "enabled": true, "radius": 320 }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertFalse(config.flocking.enabled)
        XCTAssertTrue(config.cursorGather.enabled)
        XCTAssertEqual(config.cursorGather.radius, 320)
    }

    func testParseConfigWithoutFlockingUsesDefaults() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertTrue(config.flocking.enabled)          // default ON
        XCTAssertFalse(config.cursorGather.enabled)      // default OFF
        XCTAssertEqual(config.cursorGather.radius, 250)
    }

    func testConfigRoundTripsFlockingAndCursor() throws {
        let config = SpeakiConfig(
            defaultArea: "bottom",
            speeches: Speeches(idle: "a", working: "b"),
            loops: .off, movements: .allOn, speed: 2.0, flips: .off,
            flocking: FlockingSettings(enabled: false),
            cursorGather: CursorGatherSettings(enabled: true, radius: 300)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SpeakiConfig.self, from: data)
        XCTAssertFalse(decoded.flocking.enabled)
        XCTAssertTrue(decoded.cursorGather.enabled)
        XCTAssertEqual(decoded.cursorGather.radius, 300)
    }
}
