import AppKit
import Combine
import ScreenshotKit

@MainActor
final class ScreenshotEditorViewModel: ObservableObject {
    let image: CGImage

    @Published var tool: ScreenshotTool = .select
    @Published var style: AnnotationStyle = .default
    @Published private(set) var history: ScreenshotHistory
    @Published var selectedAnnotationID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var isDirty = false

    init(image: CGImage) {
        self.image = image
        history = ScreenshotHistory(
            initial: ScreenshotDocumentState(
                cropRect: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        )
    }

    var state: ScreenshotDocumentState {
        history.current
    }

    var canUndo: Bool {
        history.canUndo
    }

    var canRedo: Bool {
        history.canRedo
    }

    func apply(_ state: ScreenshotDocumentState) {
        guard state != history.current else { return }
        var updated = history
        updated.apply(state)
        history = updated
        isDirty = true
    }

    func add(_ annotation: ScreenshotAnnotation) {
        apply(state.adding(annotation))
        selectedAnnotationID = annotation.id
    }

    func replace(_ annotation: ScreenshotAnnotation) {
        apply(state.replacing(annotation))
        selectedAnnotationID = annotation.id
    }

    func deleteSelected() {
        guard let selectedAnnotationID else { return }
        apply(state.removingAnnotation(id: selectedAnnotationID))
        self.selectedAnnotationID = nil
    }

    func annotation(id: UUID) -> ScreenshotAnnotation? {
        state.annotations.first { $0.id == id }
    }

    func undo() {
        guard history.canUndo else { return }
        var updated = history
        updated.undo()
        history = updated
        selectedAnnotationID = nil
        isDirty = true
    }

    func redo() {
        guard history.canRedo else { return }
        var updated = history
        updated.redo()
        history = updated
        selectedAnnotationID = nil
        isDirty = true
    }

    func markSaved() {
        isDirty = false
    }
}
