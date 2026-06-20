import XCTest
@testable import Claudeer

final class AreaPresetTests: XCTestCase {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testBottomPreset() {
        let rect = AreaPreset.bottom.rect(in: screenFrame)
        XCTAssertEqual(rect.origin.y, 0)
        XCTAssertEqual(rect.size.width, 1920)
        XCTAssertTrue(rect.size.height < 1080)
    }

    func testFullScreenPreset() {
        let rect = AreaPreset.fullScreen.rect(in: screenFrame)
        XCTAssertEqual(rect, screenFrame)
    }

    func testRightQuarterPreset() {
        let rect = AreaPreset.rightQuarter.rect(in: screenFrame)
        XCTAssertEqual(rect.origin.x, 1440) // 1920 * 0.75
        XCTAssertEqual(rect.size.width, 480) // 1920 * 0.25
    }

    func testOffsetScreenFrame() {
        let offset = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let bottom = AreaPreset.bottom.rect(in: offset)
        XCTAssertEqual(bottom.minX, -1920)
        XCTAssertEqual(bottom.minY, 0)
        let right = AreaPreset.rightQuarter.rect(in: offset)
        XCTAssertEqual(right.minX, -1920 + 1920 * 0.75)
    }

    func testFromString() {
        XCTAssertEqual(AreaPreset(rawValue: "bottom"), .bottom)
        XCTAssertEqual(AreaPreset(rawValue: "full_screen"), .fullScreen)
        XCTAssertNil(AreaPreset(rawValue: "invalid"))
    }
}
