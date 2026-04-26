import XCTest
@testable import Claudeer

final class SessionTrackerTests: XCTestCase {
    func testRecordAddsNewSession() {
        let tracker = SessionTracker()
        let event = SpeakiEvent(state: .working, sessionId: "abc", pid: 100, cwd: "/home/user/proj")

        tracker.record(event)

        XCTAssertEqual(tracker.sessions.count, 1)
        let session = tracker.sessions[0]
        XCTAssertEqual(session.id, "abc")
        XCTAssertEqual(session.pid, 100)
        XCTAssertEqual(session.cwd, "/home/user/proj")
        XCTAssertEqual(session.state, .working)
    }

    func testRecordUpdatesExistingSession() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 100, cwd: "/p"))
        tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 100, cwd: "/p"))

        XCTAssertEqual(tracker.sessions.count, 1)
        XCTAssertEqual(tracker.sessions[0].state, .working)
    }

    func testRecordPreservesCwdWhenNotProvided() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 100, cwd: "/p"))
        tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: nil, cwd: nil))

        XCTAssertEqual(tracker.sessions[0].cwd, "/p")
        XCTAssertEqual(tracker.sessions[0].pid, 100)
    }

    func testSessionsSortedByLastSeenDescending() {
        let tracker = SessionTracker()
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        tracker.record(SpeakiEvent(state: .idle, sessionId: "old", pid: 1, cwd: nil), at: t1)
        tracker.record(SpeakiEvent(state: .idle, sessionId: "new", pid: 2, cwd: nil), at: t2)

        XCTAssertEqual(tracker.sessions.map { $0.id }, ["new", "old"])
    }

    func testPruneDeadProcessesRemovesDead() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "alive", pid: 100, cwd: nil))
        tracker.record(SpeakiEvent(state: .working, sessionId: "dead", pid: 200, cwd: nil))

        let pruned = tracker.pruneDeadProcesses(isAlive: { $0 == 100 })

        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned[0].id, "dead")
        XCTAssertEqual(tracker.sessions.count, 1)
        XCTAssertEqual(tracker.sessions[0].id, "alive")
    }

    func testPruneKeepsSessionsWithoutPid() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "no_pid", pid: nil, cwd: nil))

        let pruned = tracker.pruneDeadProcesses(isAlive: { _ in false })

        XCTAssertTrue(pruned.isEmpty)
        XCTAssertEqual(tracker.sessions.count, 1)
    }

    func testAnyWorkingDetectsWorking() {
        let tracker = SessionTracker()
        XCTAssertFalse(tracker.anyWorking)

        tracker.record(SpeakiEvent(state: .idle, sessionId: "a", pid: nil, cwd: nil))
        XCTAssertFalse(tracker.anyWorking)

        tracker.record(SpeakiEvent(state: .working, sessionId: "b", pid: nil, cwd: nil))
        XCTAssertTrue(tracker.anyWorking)
    }
}
