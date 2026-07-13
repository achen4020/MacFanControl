import AppKit
import ScreenshotKit

@MainActor
final class SelectionOverlayController {
    private var window: NSWindow?
    private var completion: ((ScreenshotSelection?) -> Void)?

    func present(
        capture: CapturedDisplay,
        completion: @escaping (ScreenshotSelection?) -> Void
    ) {
        close(result: nil, notify: false)
        self.completion = completion

        let screenFrame = capture.geometry.frameInPoints
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.hidesOnDeactivate = false

        let overlay = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            image: capture.image
        )
        overlay.onComplete = { [weak self] selection in
            self?.close(result: selection)
        }
        overlay.onCancel = { [weak self] in
            self?.close(result: nil)
        }
        window.contentView = overlay
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlay)
    }

    func cancel() {
        close(result: nil)
    }

    private func close(result: ScreenshotSelection?, notify: Bool = true) {
        let callback = completion
        completion = nil

        if let overlay = window?.contentView as? SelectionOverlayView {
            overlay.onComplete = nil
            overlay.onCancel = nil
        }
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil

        if notify {
            callback?(result)
        }
    }
}
