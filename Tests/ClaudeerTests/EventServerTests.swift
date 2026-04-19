import XCTest
@testable import Claudeer

final class EventServerTests: XCTestCase {
    func testParseEvent() throws {
        let json = """
        {"event": "need_input", "session_id": "abc123", "pid": 12345}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SpeakiEvent.self, from: json)
        XCTAssertEqual(event.event, .needInput)
        XCTAssertEqual(event.sessionId, "abc123")
        XCTAssertEqual(event.pid, 12345)
    }

    func testParseSessionStart() throws {
        let json = """
        {"event": "session_start", "session_id": "xyz"}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SpeakiEvent.self, from: json)
        XCTAssertEqual(event.event, .sessionStart)
        XCTAssertNil(event.pid)
    }
}
