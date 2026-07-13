import CoreGraphics
import XCTest
@testable import ScreenshotKit

final class ScreenshotGeometryTests: XCTestCase {
    func testDefaultHotKeyIsControlShiftA() {
        XCTAssertEqual(ScreenshotHotKey.default.keyCode, 0)
        XCTAssertEqual(ScreenshotHotKey.default.modifiers, [.control, .shift])
    }

    func testSelectionRequiresFourPoints() {
        XCTAssertNil(ScreenshotSelection(start: .zero, end: CGPoint(x: 3, y: 8)))
        XCTAssertNotNil(ScreenshotSelection(start: .zero, end: CGPoint(x: 4, y: 4)))
    }
}
