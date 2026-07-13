import AppKit
import ScreenshotKit

final class SelectionOverlayView: NSView {
    var onComplete: ((ScreenshotSelection) -> Void)?
    var onCancel: (() -> Void)?

    private let image: CGImage
    private lazy var displayImage = NSImage(
        cgImage: image,
        size: bounds.size
    )
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(frame: CGRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint,
              let selection = ScreenshotSelection(
                start: startPoint,
                end: clampedPoint(convert(event.locationInWindow, from: nil))
              ) else {
            onCancel?()
            return
        }
        onComplete?(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        displayImage.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.52).setFill()
        bounds.fill()

        guard let selectionRect else {
            drawInstruction()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        displayImage.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2
        border.stroke()

        drawSizeLabel(for: selectionRect)
        if let currentPoint {
            drawMagnifier(around: currentPoint)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.maxX - textSize.width - 16, y: rect.minY + 8)
        origin.x = max(8, min(origin.x, bounds.maxX - textSize.width - 16))
        origin.y = max(8, min(origin.y, bounds.maxY - textSize.height - 12))
        let background = CGRect(
            x: origin.x - 6,
            y: origin.y - 4,
            width: textSize.width + 12,
            height: textSize.height + 8
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawMagnifier(around point: CGPoint) {
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let centerX = point.x * scaleX
        let centerY = CGFloat(image.height) - point.y * scaleY
        let sampleWidth = max(1, 15 * scaleX)
        let sampleHeight = max(1, 15 * scaleY)
        let sampleRect = CGRect(
            x: centerX - sampleWidth / 2,
            y: centerY - sampleHeight / 2,
            width: sampleWidth,
            height: sampleHeight
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard !sampleRect.isNull, let sample = image.cropping(to: sampleRect) else { return }

        let size = CGSize(width: 120, height: 120)
        var origin = CGPoint(x: point.x + 18, y: point.y - size.height - 18)
        if origin.x + size.width > bounds.maxX { origin.x = point.x - size.width - 18 }
        if origin.y < bounds.minY { origin.y = point.y + 18 }
        let frame = CGRect(origin: origin, size: size)

        NSColor.white.setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: sample, size: sampleRect.size).draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemRed.setStroke()
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: frame.midX, y: frame.minY))
        crosshair.line(to: CGPoint(x: frame.midX, y: frame.maxY))
        crosshair.move(to: CGPoint(x: frame.minX, y: frame.midY))
        crosshair.line(to: CGPoint(x: frame.maxX, y: frame.midY))
        crosshair.lineWidth = 1
        crosshair.stroke()
    }

    private func drawInstruction() {
        let text = "拖动选择区域 · Esc 或右键取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: 22)
        let background = CGRect(
            x: origin.x - 12,
            y: origin.y - 7,
            width: size.width + 24,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 16, yRadius: 16).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
