import XCTest
@testable import Claudeer

final class WindowFocuserTests: XCTestCase {
    // Typical chain: claude(100) -> shell(90) -> Terminal.app(80) -> launchd(1).
    func testFindsAppAncestor() {
        let parents: [Int: Int] = [100: 90, 90: 80, 80: 1]
        XCTAssertEqual(
            WindowFocuser.ancestorPID(startPID: 100, parentOf: { parents[$0] }, isApp: { $0 == 80 }),
            80
        )
    }

    func testReturnsStartWhenItIsApp() {
        XCTAssertEqual(
            WindowFocuser.ancestorPID(startPID: 42, parentOf: { _ in nil }, isApp: { $0 == 42 }),
            42
        )
    }

    func testPicksNearestAppAncestor() {
        // VS Code style: both a helper (90) and the main app (80) are "apps";
        // the nearest ancestor wins.
        let parents: [Int: Int] = [100: 90, 90: 80, 80: 1]
        let appPIDs: Set<Int> = [90, 80]
        XCTAssertEqual(
            WindowFocuser.ancestorPID(startPID: 100, parentOf: { parents[$0] }, isApp: { appPIDs.contains($0) }),
            90
        )
    }

    func testNoAppAncestorReturnsNil() {
        let parents: [Int: Int] = [5: 4, 4: 3, 3: 1]
        XCTAssertNil(
            WindowFocuser.ancestorPID(startPID: 5, parentOf: { parents[$0] }, isApp: { _ in false })
        )
    }

    func testStopsBeforeLaunchd() {
        // launchd (pid 1) is never a focus target even if it would "match".
        let parents: [Int: Int] = [10: 1]
        XCTAssertNil(
            WindowFocuser.ancestorPID(startPID: 10, parentOf: { parents[$0] }, isApp: { $0 == 1 })
        )
    }

    func testRespectsMaxDepth() {
        // Match would occur at depth 100, but maxDepth caps the walk first.
        XCTAssertNil(
            WindowFocuser.ancestorPID(startPID: 1000, parentOf: { $0 - 1 }, isApp: { $0 == 900 }, maxDepth: 10)
        )
    }

    // Validates the live sysctl path resolves a real parent pid.
    func testParentPIDOfSelfResolves() {
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let parent = WindowFocuser.parentPID(of: me)
        XCTAssertNotNil(parent)
        XCTAssertGreaterThan(parent ?? 0, 0)
    }

    func testParentPIDOfBogusPIDIsNil() {
        // An unused high pid has no process record.
        XCTAssertNil(WindowFocuser.parentPID(of: 999_999))
    }

    // MARK: - folderName (cwd -> window-title needle)

    func testFolderNameBasic() {
        XCTAssertEqual(WindowFocuser.folderName("/Users/jhseo/Programming/claudeer"), "claudeer")
    }

    func testFolderNameTrailingSlash() {
        XCTAssertEqual(WindowFocuser.folderName("/Users/jhseo/Programming/comfyui/"), "comfyui")
    }

    func testFolderNameMultipleTrailingSlashes() {
        XCTAssertEqual(WindowFocuser.folderName("/a/b/c///"), "c")
    }

    func testFolderNameNilAndEmpty() {
        XCTAssertNil(WindowFocuser.folderName(nil))
        XCTAssertNil(WindowFocuser.folderName(""))
    }

    func testFolderNameRootIsNil() {
        XCTAssertNil(WindowFocuser.folderName("/"))
    }
}
