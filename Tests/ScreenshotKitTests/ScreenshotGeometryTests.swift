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

    func testSelectionNormalizesReverseDrag() {
        XCTAssertEqual(
            ScreenshotSelection(
                start: CGPoint(x: 90, y: 70),
                end: CGPoint(x: 10, y: 20)
            )?.rect,
            CGRect(x: 10, y: 20, width: 80, height: 50)
        )
    }

    func testPixelRectFlipsYAxisAndAppliesRetinaScale() {
        let geometry = DisplayGeometry(
            frameInPoints: CGRect(x: 1440, y: 100, width: 1000, height: 800),
            pixelSize: CGSize(width: 2000, height: 1600)
        )

        XCTAssertEqual(
            geometry.pixelRect(
                forLocalSelection: CGRect(x: 100, y: 200, width: 300, height: 100)
            ),
            CGRect(x: 200, y: 1000, width: 600, height: 200)
        )
    }

    func testPixelRectClampsToImageBounds() {
        let geometry = DisplayGeometry(
            frameInPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            pixelSize: CGSize(width: 200, height: 200)
        )

        XCTAssertEqual(
            geometry.pixelRect(
                forLocalSelection: CGRect(x: -5, y: 90, width: 20, height: 20)
            ),
            CGRect(x: 0, y: 0, width: 30, height: 20)
        )
    }
}
