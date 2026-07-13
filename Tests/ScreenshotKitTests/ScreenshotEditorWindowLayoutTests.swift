import AppKit
import XCTest
@testable import ScreenshotKit

@MainActor
final class ScreenshotEditorWindowLayoutTests: XCTestCase {
    func testApplyingLayoutRestoresVisibleContentSizeAfterControllerInstallation() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSViewController()

        ScreenshotEditorWindowLayout.apply(to: window)

        XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 960, height: 680))
        XCTAssertEqual(window.minSize, NSSize(width: 720, height: 520))
    }
}
