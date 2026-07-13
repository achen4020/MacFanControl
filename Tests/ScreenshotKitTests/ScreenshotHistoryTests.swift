import CoreGraphics
import XCTest
@testable import ScreenshotKit

final class ScreenshotHistoryTests: XCTestCase {
    func testUndoAndRedoRestoreDocumentSnapshots() {
        let base = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        var history = ScreenshotHistory(initial: base)
        let annotation = ScreenshotAnnotation.rectangle(
            id: UUID(),
            rect: CGRect(x: 10, y: 10, width: 20, height: 20),
            style: .default
        )

        history.apply(base.adding(annotation))
        XCTAssertEqual(history.current.annotations.count, 1)

        history.undo()
        XCTAssertTrue(history.current.annotations.isEmpty)

        history.redo()
        XCTAssertEqual(history.current.annotations.count, 1)
    }

    func testNewEditClearsRedoStack() {
        let base = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        var history = ScreenshotHistory(initial: base)

        history.apply(base.withCropRect(CGRect(x: 0, y: 0, width: 90, height: 90)))
        history.undo()
        XCTAssertTrue(history.canRedo)

        history.apply(base.withCropRect(CGRect(x: 0, y: 0, width: 80, height: 80)))
        XCTAssertFalse(history.canRedo)
    }

    func testApplyingUnchangedStateDoesNotCreateUndoEntry() {
        let base = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        var history = ScreenshotHistory(initial: base)

        history.apply(base)

        XCTAssertFalse(history.canUndo)
    }
}
