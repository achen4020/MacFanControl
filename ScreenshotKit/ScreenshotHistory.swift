public struct ScreenshotHistory: Sendable {
    public private(set) var current: ScreenshotDocumentState
    private var undoStack: [ScreenshotDocumentState] = []
    private var redoStack: [ScreenshotDocumentState] = []

    public init(initial: ScreenshotDocumentState) {
        current = initial
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public mutating func apply(_ next: ScreenshotDocumentState) {
        guard next != current else { return }
        undoStack.append(current)
        current = next
        redoStack.removeAll(keepingCapacity: true)
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        current = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        current = next
    }
}
