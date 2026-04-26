import XCTest
@testable import Claudeer

final class EventServerTests: XCTestCase {
    func testParseWorkingEvent() throws {
        let json = """
        {"state": "working", "session_id": "abc123", "pid": 12345}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SpeakiEvent.self, from: json)
        XCTAssertEqual(event.state, .working)
        XCTAssertEqual(event.sessionId, "abc123")
        XCTAssertEqual(event.pid, 12345)
    }

    func testParseIdleEvent() throws {
        let json = """
        {"state": "idle", "session_id": "xyz"}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SpeakiEvent.self, from: json)
        XCTAssertEqual(event.state, .idle)
        XCTAssertNil(event.pid)
    }
}
