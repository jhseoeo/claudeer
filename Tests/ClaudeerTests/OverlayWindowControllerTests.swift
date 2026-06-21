import XCTest
@testable import Claudeer

final class OverlayWindowControllerTests: XCTestCase {
    // Two 2560x1440 displays side by side, primary at origin.
    let frames = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 0, width: 2560, height: 1440)
    ]

    func testPointInsideFirstScreen() {
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 1200, y: 100), screenFrames: frames),
            0
        )
    }

    func testPointInsideSecondScreen() {
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 3760, y: 100), screenFrames: frames),
            1
        )
    }

    func testPointLeftOfAllScreensFallsBackToNearest() {
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: -500, y: 100), screenFrames: frames),
            0
        )
    }

    func testPointRightOfAllScreensFallsBackToNearest() {
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 9000, y: 100), screenFrames: frames),
            1
        )
    }

    func testBoundaryBelongsToContainingScreen() {
        // x exactly at the seam is inside the right screen (CGRect.contains is min-inclusive).
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 2560, y: 700), screenFrames: frames),
            1
        )
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 0, y: 0), screenFrames: [])
        )
    }

    func testStackedScreensWithVerticalOffset() {
        // Secondary positioned above-left (negative-y style arrangement).
        let stacked = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        ]
        XCTAssertEqual(
            OverlayWindowController.hostIndex(forGlobalPoint: CGPoint(x: 500, y: 1500), screenFrames: stacked),
            1
        )
    }
}
