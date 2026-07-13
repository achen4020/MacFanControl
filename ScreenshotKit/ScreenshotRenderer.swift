import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScreenshotImageFormat: Equatable {
    case png
    case jpeg(quality: CGFloat)
}

public enum ScreenshotOutputError: LocalizedError, Equatable {
    case invalidCrop
    case renderingFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCrop:
            return "截图裁剪区域无效"
        case .renderingFailed:
            return "图片渲染失败"
        case .encodingFailed:
            return "图片编码失败"
        }
    }
}

public final class ScreenshotRenderer {
    public init() {}

    public func render(
        image: CGImage,
        state: ScreenshotDocumentState
    ) throws -> CGImage {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = state.cropRect.integral.intersection(imageBounds)
        guard !crop.isNull,
              crop.width >= 1,
              crop.height >= 1,
              let base = image.cropping(to: crop) else {
            throw ScreenshotOutputError.invalidCrop
        }

        guard let context = CGContext(
            data: nil,
            width: base.width,
            height: base.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotOutputError.renderingFailed
        }

        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.clip(to: crop)

        for annotation in state.annotations {
            draw(annotation, source: image, in: context)
        }

        guard let result = context.makeImage() else {
            throw ScreenshotOutputError.renderingFailed
        }
        return result
    }

    public func encode(
        _ image: CGImage,
        format: ScreenshotImageFormat
    ) throws -> Data {
        let data = NSMutableData()
        let type: UTType
        let properties: CFDictionary?

        switch format {
        case .png:
            type = .png
            properties = nil
        case let .jpeg(quality):
            type = .jpeg
            properties = [
                kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
            ] as CFDictionary
        }

        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotOutputError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotOutputError.encodingFailed
        }
        return data as Data
    }

    private func draw(
        _ annotation: ScreenshotAnnotation,
        source: CGImage,
        in context: CGContext
    ) {
        switch annotation {
        case let .rectangle(_, rect, style):
            configure(style, in: context)
            context.stroke(rect)
        case let .arrow(_, start, end, style):
            configure(style, in: context)
            drawArrow(from: start, to: end, lineWidth: style.lineWidth, in: context)
        case let .pen(_, points, style):
            guard let first = points.first else { return }
            configure(style, in: context)
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        case let .text(_, rect, value, fontSize, style):
            drawText(value, rect: rect, fontSize: fontSize, style: style, in: context)
        case let .mosaic(_, rect, blockSize):
            drawMosaic(rect: rect, blockSize: blockSize, source: source, in: context)
        }
    }

    private func configure(_ style: AnnotationStyle, in context: CGContext) {
        context.setStrokeColor(
            CGColor(
                red: style.color.red,
                green: style.color.green,
                blue: style.color.blue,
                alpha: style.color.alpha * style.opacity
            )
        )
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, lineWidth * 4)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - length * cos(angle - .pi / 6),
            y: end.y - length * sin(angle - .pi / 6)
        ))
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - length * cos(angle + .pi / 6),
            y: end.y - length * sin(angle + .pi / 6)
        ))
        context.strokePath()
    }

    private func drawText(
        _ value: String,
        rect: CGRect,
        fontSize: CGFloat,
        style: AnnotationStyle,
        in context: CGContext
    ) {
        let color = CGColor(
            red: style.color.red,
            green: style.color.green,
            blue: style.color.blue,
            alpha: style.color.alpha * style.opacity
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString,
                fontSize,
                nil
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: value, attributes: attributes)
        )

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawMosaic(
        rect: CGRect,
        blockSize: CGFloat,
        source: CGImage,
        in context: CGContext
    ) {
        let sourceBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let area = rect.integral.intersection(sourceBounds)
        guard !area.isNull,
              let cropped = source.cropping(to: area) else { return }

        let block = max(2, blockSize)
        let width = max(1, Int(ceil(area.width / block)))
        let height = max(1, Int(ceil(area.height / block)))
        guard let smallContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        smallContext.interpolationQuality = .medium
        smallContext.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelated = smallContext.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(pixelated, in: area)
        context.restoreGState()
    }
}
