import XCTest
@testable import Claudeer

final class NtfyNotifierTests: XCTestCase {
    /// Capture the outgoing request instead of hitting the network.
    private func makeNotifier(_ settings: NtfySettings, capture: @escaping (URLRequest) -> Void) -> NtfyNotifier {
        NtfyNotifier(settings: settings, transport: capture)
    }

    func testDisabledSendsNothing() {
        var sent = 0
        let notifier = makeNotifier(
            NtfySettings(enabled: false, server: "https://ntfy.sh", topic: "t", token: nil)
        ) { _ in sent += 1 }
        notifier.notify(title: "x", body: "y")
        XCTAssertEqual(sent, 0)
    }

    func testEmptyTopicSendsNothing() {
        var sent = 0
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.sh", topic: "   ", token: nil)
        ) { _ in sent += 1 }
        notifier.notify(title: "x", body: "y")
        XCTAssertEqual(sent, 0)
    }

    func testEnabledPostsToServerRootAsJSON() throws {
        var captured: URLRequest?
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.example.com", topic: "my-topic", token: nil)
        ) { captured = $0 }
        notifier.notify(title: "Session", body: "Need your input!")

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://ntfy.example.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRequestBodyCarriesTopicTitleMessage() throws {
        var captured: URLRequest?
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.sh", topic: "my-topic", token: nil)
        ) { captured = $0 }
        notifier.notify(title: "claudeer", body: "Need your input!")

        let body = try XCTUnwrap(captured?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(json?["topic"], "my-topic")
        XCTAssertEqual(json?["title"], "claudeer")
        XCTAssertEqual(json?["message"], "Need your input!")
    }

    func testTokenAddsBearerAuthorization() throws {
        var captured: URLRequest?
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.sh", topic: "t", token: "tk_secret")
        ) { captured = $0 }
        notifier.notify(title: "x", body: "y")

        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tk_secret")
    }

    func testNoTokenOmitsAuthorization() throws {
        var captured: URLRequest?
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.sh", topic: "t", token: nil)
        ) { captured = $0 }
        notifier.notify(title: "x", body: "y")

        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"))
    }

    func testUnicodeTitleSurvivesInJSONBody() throws {
        var captured: URLRequest?
        let notifier = makeNotifier(
            NtfySettings(enabled: true, server: "https://ntfy.sh", topic: "t", token: nil)
        ) { captured = $0 }
        notifier.notify(title: "작업 끝났어", body: "입력이 필요해요")

        let body = try XCTUnwrap(captured?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(json?["title"], "작업 끝났어")
        XCTAssertEqual(json?["message"], "입력이 필요해요")
    }
}
