import AppKit
import ScreenshotKit
import SwiftUI

struct ScreenshotHotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: ScreenshotHotKey
    let onRecorded: (ScreenshotHotKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecorded = context.coordinator.record
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        context.coordinator.parent = self
        view.hotKey = hotKey
        view.onRecorded = context.coordinator.record
    }

    final class Coordinator {
        var parent: ScreenshotHotKeyRecorder

        init(parent: ScreenshotHotKeyRecorder) {
            self.parent = parent
        }

        func record(_ value: ScreenshotHotKey) {
            parent.hotKey = value
            parent.onRecorded(value)
        }
    }
}

final class RecorderView: NSView {
    var hotKey: ScreenshotHotKey = .default {
        didSet { needsDisplay = true }
    }
    var onRecorded: ((ScreenshotHotKey) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 30) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }

        let modifiers = screenshotModifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let value = ScreenshotHotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        isRecording = false
        onRecorded?(value)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor)
            .setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "请按新的快捷键" : hotKey.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private func screenshotModifiers(from flags: NSEvent.ModifierFlags) -> ScreenshotModifier {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: ScreenshotModifier = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
