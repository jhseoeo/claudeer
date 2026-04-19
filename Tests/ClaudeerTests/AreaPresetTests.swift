import XCTest
@testable import Claudeer

final class AreaPresetTests: XCTestCase {
    let screenSize = CGSize(width: 1920, height: 1080)

    func testBottomPreset() {
        let rect = AreaPreset.bottom.rect(for: screenSize)
        XCTAssertEqual(rect.origin.y, 0)
        XCTAssertEqual(rect.size.width, 1920)
        XCTAssertTrue(rect.size.height < 1080)
    }

    func testFullScreenPreset() {
        let rect = AreaPreset.fullScreen.rect(for: screenSize)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: screenSize))
    }

    func testRightQuarterPreset() {
        let rect = AreaPreset.rightQuarter.rect(for: screenSize)
        XCTAssertEqual(rect.origin.x, 1440) // 1920 * 0.75
        XCTAssertEqual(rect.size.width, 480) // 1920 * 0.25
    }

    func testFromString() {
        XCTAssertEqual(AreaPreset(rawValue: "bottom"), .bottom)
        XCTAssertEqual(AreaPreset(rawValue: "full_screen"), .fullScreen)
        XCTAssertNil(AreaPreset(rawValue: "invalid"))
    }
}
