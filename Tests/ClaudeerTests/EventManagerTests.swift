import XCTest
@testable import Claudeer

final class EventManagerTests: XCTestCase {
    func testNotifiesOnWorkingToIdleTransition() {
        XCTAssertTrue(EventManager.shouldNotifyIdle(previousState: .working, eventState: .idle))
    }

    func testDoesNotNotifyWhenAlreadyIdle() {
        // e.g. SessionStart on a fresh mascot (idle -> idle): no real transition.
        XCTAssertFalse(EventManager.shouldNotifyIdle(previousState: .idle, eventState: .idle))
    }

    func testDoesNotNotifyOnIdleToWorking() {
        XCTAssertFalse(EventManager.shouldNotifyIdle(previousState: .idle, eventState: .working))
    }

    func testDoesNotNotifyWhileStayingWorking() {
        XCTAssertFalse(EventManager.shouldNotifyIdle(previousState: .working, eventState: .working))
    }

    func testNotificationTitlePrefersCustomName() {
        XCTAssertEqual(
            EventManager.notificationTitle(customName: "Custom", eventName: "Auto", sessionId: "abcdef123"),
            "Custom")
    }

    func testNotificationTitleFallsBackToEventName() {
        XCTAssertEqual(
            EventManager.notificationTitle(customName: nil, eventName: "Auto", sessionId: "abcdef123"),
            "Auto")
    }

    func testNotificationTitleFallsBackToShortId() {
        XCTAssertEqual(
            EventManager.notificationTitle(customName: "   ", eventName: nil, sessionId: "abcdef123456"),
            "abcdef12")
    }
}
