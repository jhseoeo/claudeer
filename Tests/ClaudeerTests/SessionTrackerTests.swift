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

    func testHideShowToggleAndIsHidden() {
        let tracker = SessionTracker()
        XCTAssertFalse(tracker.isHidden("a"))

        tracker.hide("a")
        XCTAssertTrue(tracker.isHidden("a"))
        XCTAssertEqual(tracker.hiddenSessionIDs, ["a"])

        tracker.show("a")
        XCTAssertFalse(tracker.isHidden("a"))

        tracker.toggleHidden("a")
        XCTAssertTrue(tracker.isHidden("a"))
        tracker.toggleHidden("a")
        XCTAssertFalse(tracker.isHidden("a"))
    }

    func testRecordDoesNotClearHiddenState() {
        let tracker = SessionTracker()
        tracker.hide("abc")
        // A new event for a hidden session must NOT un-hide it (sticky).
        tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 100, cwd: "/p"))
        XCTAssertTrue(tracker.isHidden("abc"))
    }

    func testPruneRemovesHiddenStateForDeadSession() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "dead", pid: 200, cwd: nil))
        tracker.hide("dead")

        _ = tracker.pruneDeadProcesses(isAlive: { _ in false })

        XCTAssertFalse(tracker.isHidden("dead"))
        XCTAssertTrue(tracker.hiddenSessionIDs.isEmpty)
    }

    // MARK: - Auto name (SessionInfo.name)

    func testRecordStoresEventName() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "My Session"))
        XCTAssertEqual(tracker.sessions[0].name, "My Session")
    }

    func testRecordPreservesNameWhenNotProvided() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "My Session"))
        tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 1, cwd: "/p", name: nil))
        XCTAssertEqual(tracker.sessions[0].name, "My Session")
    }

    // MARK: - Custom names

    func testSetCustomNameAndResolve() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
        tracker.setCustomName("Custom", for: "abc")
        XCTAssertEqual(tracker.customName(for: "abc"), "Custom")
        XCTAssertEqual(tracker.displayName(for: "abc"), "Custom")
    }

    func testDisplayNameFallsBackToAutoName() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
        XCTAssertEqual(tracker.displayName(for: "abc"), "Auto")
        XCTAssertNil(tracker.customName(for: "abc"))
    }

    func testEmptyCustomNameRevertsToAuto() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
        tracker.setCustomName("Custom", for: "abc")
        tracker.setCustomName("   ", for: "abc")
        XCTAssertNil(tracker.customName(for: "abc"))
        XCTAssertEqual(tracker.displayName(for: "abc"), "Auto")
    }

    func testCustomNameIsTrimmed() {
        let tracker = SessionTracker()
        tracker.setCustomName("  Custom  ", for: "abc")
        XCTAssertEqual(tracker.customName(for: "abc"), "Custom")
    }

    func testRecordDoesNotClearCustomName() {
        let tracker = SessionTracker()
        tracker.setCustomName("Custom", for: "abc")
        tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
        XCTAssertEqual(tracker.displayName(for: "abc"), "Custom")
    }

    func testDisplayNameNilWhenNothingKnown() {
        let tracker = SessionTracker()
        XCTAssertNil(tracker.displayName(for: "unknown"))
    }

    func testPruneRemovesCustomNameForDeadSession() {
        let tracker = SessionTracker()
        tracker.record(SpeakiEvent(state: .idle, sessionId: "dead", pid: 200, cwd: nil, name: "Auto"))
        tracker.setCustomName("Custom", for: "dead")

        _ = tracker.pruneDeadProcesses(isAlive: { _ in false })

        XCTAssertNil(tracker.customName(for: "dead"))
        XCTAssertTrue(tracker.customNames.isEmpty)
    }
}
