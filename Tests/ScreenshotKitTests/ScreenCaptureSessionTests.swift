import XCTest
@testable import ScreenshotKit

final class ScreenCaptureSessionTests: XCTestCase {
    func testSessionRejectsDuplicateStartAndResetsAfterFinish() {
        var state = ScreenCaptureSessionState()

        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())

        state.finish()

        XCTAssertTrue(state.begin())
    }

    func testCaptureErrorsHaveUserFacingDescriptions() {
        XCTAssertEqual(
            ScreenCaptureError.permissionDenied.localizedDescription,
            "未获得屏幕录制权限"
        )
        XCTAssertEqual(ScreenCaptureError.noDisplay.localizedDescription, "未找到鼠标所在显示器")
        XCTAssertEqual(ScreenCaptureError.captureFailed.localizedDescription, "无法读取显示器画面")
    }
}
