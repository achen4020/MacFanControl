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

    func testDocumentReplacesAndRemovesAnnotationByID() {
        let id = UUID()
        let original = ScreenshotAnnotation.rectangle(
            id: id,
            rect: CGRect(x: 10, y: 10, width: 20, height: 20),
            style: .default
        )
        let moved = ScreenshotAnnotation.rectangle(
            id: id,
            rect: CGRect(x: 30, y: 40, width: 20, height: 20),
            style: .default
        )
        let state = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            annotations: [original]
        )

        XCTAssertEqual(state.replacing(moved).annotations, [moved])
        XCTAssertTrue(state.removingAnnotation(id: id).annotations.isEmpty)
        XCTAssertEqual(original.id, id)
    }

    func testAnnotationBoundsAndTranslationUseDocumentCoordinates() {
        let id = UUID()
        let arrow = ScreenshotAnnotation.arrow(
            id: id,
            start: CGPoint(x: 40, y: 10),
            end: CGPoint(x: 10, y: 30),
            style: .default
        )

        XCTAssertEqual(arrow.bounds, CGRect(x: 10, y: 10, width: 30, height: 20))
        XCTAssertEqual(
            arrow.translatedBy(x: 5, y: -5),
            .arrow(
                id: id,
                start: CGPoint(x: 45, y: 5),
                end: CGPoint(x: 15, y: 25),
                style: .default
            )
        )
    }
}
