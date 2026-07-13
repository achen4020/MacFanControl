import AppKit
import ScreenshotKit
import SwiftUI

struct ScreenshotCanvasView: NSViewRepresentable {
    @ObservedObject var viewModel: ScreenshotEditorViewModel

    func makeNSView(context: Context) -> ScreenshotCanvasNSView {
        ScreenshotCanvasNSView(viewModel: viewModel)
    }

    func updateNSView(_ nsView: ScreenshotCanvasNSView, context: Context) {
        nsView.viewModel = viewModel
        nsView.needsDisplay = true
    }
}

final class ScreenshotCanvasNSView: NSView {
    private enum ResizeHandle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    var viewModel: ScreenshotEditorViewModel

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var penPoints: [CGPoint] = []
    private var movingOriginal: ScreenshotAnnotation?
    private var resizingOriginal: ScreenshotAnnotation?
    private var activeResizeHandle: ResizeHandle?
    private var previewAnnotation: ScreenshotAnnotation?
    private var previewCropRect: CGRect?

    init(viewModel: ScreenshotEditorViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let base = viewModel.image.cropping(to: viewModel.state.cropRect.integral),
              !imageRect.isEmpty else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: base, size: viewModel.state.cropRect.size).draw(in: imageRect)

        for annotation in viewModel.state.annotations {
            draw(annotation)
        }
        if let previewAnnotation {
            draw(previewAnnotation)
        }
        if let previewCropRect {
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: viewRect(from: previewCropRect))
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }
        drawSelection()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = documentPoint(from: convert(event.locationInWindow, from: nil))
        guard viewModel.state.cropRect.contains(point) else { return }
        dragStart = point
        dragCurrent = point
        previewAnnotation = nil
        previewCropRect = nil
        penPoints = [point]

        if viewModel.tool == .select {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let id = viewModel.selectedAnnotationID,
               let selected = viewModel.annotation(id: id),
               let handle = resizeHandle(at: viewPoint, annotation: selected) {
                resizingOriginal = selected
                activeResizeHandle = handle
                movingOriginal = nil
                needsDisplay = true
                return
            }
            let hit = annotation(at: point)
            viewModel.selectedAnnotationID = hit?.id
            movingOriginal = hit
        } else if viewModel.tool == .text {
            beginTextEntry(at: point)
            dragStart = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = clampedDocumentPoint(convert(event.locationInWindow, from: nil))
        dragCurrent = point

        switch viewModel.tool {
        case .select:
            if let resizingOriginal, let activeResizeHandle {
                let bounds = resizedBounds(
                    resizingOriginal.bounds,
                    handle: activeResizeHandle,
                    point: point
                )
                if bounds.width >= 2, bounds.height >= 2 {
                    previewAnnotation = resizingOriginal.resized(to: bounds)
                }
            } else if let movingOriginal {
                previewAnnotation = movingOriginal.translatedBy(
                    x: point.x - dragStart.x,
                    y: point.y - dragStart.y
                )
            }
        case .rectangle:
            previewAnnotation = .rectangle(
                id: UUID(), rect: normalizedRect(dragStart, point), style: viewModel.style
            )
        case .arrow:
            previewAnnotation = .arrow(
                id: UUID(), start: dragStart, end: point, style: viewModel.style
            )
        case .pen:
            if penPoints.last.map({ hypot($0.x - point.x, $0.y - point.y) >= 1 }) ?? true {
                penPoints.append(point)
            }
            previewAnnotation = .pen(id: UUID(), points: penPoints, style: viewModel.style)
        case .crop:
            previewCropRect = normalizedRect(dragStart, point)
                .intersection(viewModel.state.cropRect)
        case .mosaic:
            previewAnnotation = .mosaic(
                id: UUID(),
                rect: normalizedRect(dragStart, point),
                blockSize: 12
            )
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let end = clampedDocumentPoint(convert(event.locationInWindow, from: nil))
        let rect = normalizedRect(dragStart, end)

        switch viewModel.tool {
        case .select:
            if let previewAnnotation { viewModel.replace(previewAnnotation) }
        case .rectangle where rect.width >= 2 && rect.height >= 2:
            viewModel.add(.rectangle(id: UUID(), rect: rect, style: viewModel.style))
        case .arrow where hypot(end.x - dragStart.x, end.y - dragStart.y) >= 2:
            viewModel.add(.arrow(id: UUID(), start: dragStart, end: end, style: viewModel.style))
        case .pen where penPoints.count >= 2:
            viewModel.add(.pen(id: UUID(), points: penPoints, style: viewModel.style))
        case .crop:
            let crop = rect.intersection(viewModel.state.cropRect).integral
            if crop.width >= 4, crop.height >= 4 {
                viewModel.apply(viewModel.state.withCropRect(crop))
                viewModel.selectedAnnotationID = nil
                viewModel.tool = .select
            }
        case .mosaic where rect.width >= 2 && rect.height >= 2:
            viewModel.add(.mosaic(id: UUID(), rect: rect, blockSize: 12))
        default:
            break
        }

        self.dragStart = nil
        dragCurrent = nil
        penPoints.removeAll(keepingCapacity: true)
        movingOriginal = nil
        resizingOriginal = nil
        activeResizeHandle = nil
        previewAnnotation = nil
        previewCropRect = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            viewModel.deleteSelected()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private var imageRect: CGRect {
        let crop = viewModel.state.cropRect
        guard crop.width > 0, crop.height > 0 else { return .zero }
        let available = bounds.insetBy(dx: 28, dy: 28)
        let scale = min(available.width / crop.width, available.height / crop.height)
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        return CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func documentPoint(from viewPoint: CGPoint) -> CGPoint {
        let crop = viewModel.state.cropRect
        let imageRect = imageRect
        return CGPoint(
            x: crop.minX + (viewPoint.x - imageRect.minX) * crop.width / imageRect.width,
            y: crop.minY + (viewPoint.y - imageRect.minY) * crop.height / imageRect.height
        )
    }

    private func viewPoint(from documentPoint: CGPoint) -> CGPoint {
        let crop = viewModel.state.cropRect
        let imageRect = imageRect
        return CGPoint(
            x: imageRect.minX + (documentPoint.x - crop.minX) * imageRect.width / crop.width,
            y: imageRect.minY + (documentPoint.y - crop.minY) * imageRect.height / crop.height
        )
    }

    private func viewRect(from documentRect: CGRect) -> CGRect {
        let start = viewPoint(from: documentRect.origin)
        let end = viewPoint(from: CGPoint(x: documentRect.maxX, y: documentRect.maxY))
        return CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
    }

    private func clampedDocumentPoint(_ viewPoint: CGPoint) -> CGPoint {
        let point = documentPoint(from: viewPoint)
        let crop = viewModel.state.cropRect
        return CGPoint(
            x: min(max(point.x, crop.minX), crop.maxX),
            y: min(max(point.y, crop.minY), crop.maxY)
        )
    }

    private func normalizedRect(_ first: CGPoint, _ second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x), y: min(first.y, second.y),
            width: abs(second.x - first.x), height: abs(second.y - first.y)
        )
    }

    private func annotation(at point: CGPoint) -> ScreenshotAnnotation? {
        let tolerance = max(4, viewModel.state.cropRect.width / max(imageRect.width, 1) * 6)
        return viewModel.state.annotations.reversed().first {
            $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    private func draw(_ annotation: ScreenshotAnnotation) {
        switch annotation {
        case let .rectangle(_, rect, style):
            configure(style)
            let path = NSBezierPath(rect: viewRect(from: rect))
            path.lineWidth = scaledLineWidth(style.lineWidth)
            path.stroke()
        case let .arrow(_, start, end, style):
            configure(style)
            drawArrow(from: viewPoint(from: start), to: viewPoint(from: end), style: style)
        case let .pen(_, points, style):
            guard let first = points.first else { return }
            configure(style)
            let path = NSBezierPath()
            path.move(to: viewPoint(from: first))
            for point in points.dropFirst() { path.line(to: viewPoint(from: point)) }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = scaledLineWidth(style.lineWidth)
            path.stroke()
        case let .text(_, rect, value, fontSize, style):
            let color = nsColor(style.color).withAlphaComponent(style.opacity)
            value.draw(
                in: viewRect(from: rect),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: max(8, scaledLineWidth(fontSize))),
                    .foregroundColor: color
                ]
            )
        case .mosaic:
            if case let .mosaic(_, rect, blockSize) = annotation {
                drawMosaic(rect: rect, blockSize: blockSize)
            }
        }
    }

    private func configure(_ style: AnnotationStyle) {
        nsColor(style.color).withAlphaComponent(style.opacity).setStroke()
    }

    private func nsColor(_ color: ScreenshotColor) -> NSColor {
        NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    private func scaledLineWidth(_ value: CGFloat) -> CGFloat {
        value * imageRect.width / max(viewModel.state.cropRect.width, 1)
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, style: AnnotationStyle) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = scaledLineWidth(style.lineWidth)
        path.lineCapStyle = .round
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, path.lineWidth * 4)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - length * cos(angle - .pi / 6),
            y: end.y - length * sin(angle - .pi / 6)
        ))
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - length * cos(angle + .pi / 6),
            y: end.y - length * sin(angle + .pi / 6)
        ))
        head.lineWidth = path.lineWidth
        head.lineCapStyle = .round
        head.stroke()
    }

    private func drawSelection() {
        guard let id = viewModel.selectedAnnotationID,
              let annotation = viewModel.annotation(id: id) else { return }
        let rect = viewRect(from: annotation.bounds).insetBy(dx: -4, dy: -4)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()

        NSColor.white.setFill()
        for point in handlePoints(for: rect).map(\.point) {
            NSBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
        }
    }

    private func resizeHandle(
        at point: CGPoint,
        annotation: ScreenshotAnnotation
    ) -> ResizeHandle? {
        let rect = viewRect(from: annotation.bounds).insetBy(dx: -4, dy: -4)
        return handlePoints(for: rect).first {
            CGRect(x: $0.point.x - 7, y: $0.point.y - 7, width: 14, height: 14).contains(point)
        }?.handle
    }

    private func handlePoints(for rect: CGRect) -> [(handle: ResizeHandle, point: CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
    }

    private func resizedBounds(
        _ original: CGRect,
        handle: ResizeHandle,
        point: CGPoint
    ) -> CGRect {
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .left: minX = point.x
        case .right: maxX = point.x
        case .bottomLeft: minX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomRight: maxX = point.x; maxY = point.y
        }
        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        ).intersection(viewModel.state.cropRect)
    }

    private func drawMosaic(rect: CGRect, blockSize: CGFloat) {
        let area = rect.integral.intersection(
            CGRect(x: 0, y: 0, width: viewModel.image.width, height: viewModel.image.height)
        )
        guard !area.isNull,
              let source = viewModel.image.cropping(to: area) else { return }

        let width = max(1, Int(ceil(area.width / max(2, blockSize))))
        let height = max(1, Int(ceil(area.height / max(2, blockSize))))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelated = context.makeImage() else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: pixelated, size: CGSize(width: width, height: height))
            .draw(in: viewRect(from: area))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func beginTextEntry(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "添加文字"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "输入标注文字"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        viewModel.add(
            .text(
                id: UUID(),
                rect: CGRect(x: point.x, y: point.y, width: 220, height: 48),
                value: value,
                fontSize: 24,
                style: viewModel.style
            )
        )
    }
}
