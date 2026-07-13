import Foundation
import CoreGraphics

public struct ScreenshotModifier: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = ScreenshotModifier(rawValue: 1 << 0)
    public static let shift = ScreenshotModifier(rawValue: 1 << 1)
    public static let option = ScreenshotModifier(rawValue: 1 << 2)
    public static let command = ScreenshotModifier(rawValue: 1 << 3)
}

public struct ScreenshotHotKey: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ScreenshotModifier

    public init(keyCode: UInt32, modifiers: ScreenshotModifier) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = ScreenshotHotKey(
        keyCode: 0,
        modifiers: [.control, .shift]
    )

    public var displayText: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        value += Self.keyNames[keyCode] ?? "#\(keyCode)"
        return value
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space"
    ]
}

public struct ScreenshotSelection: Equatable, Sendable {
    public let rect: CGRect

    public init?(start: CGPoint, end: CGPoint, minimumSize: CGFloat = 4) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard rect.width >= minimumSize, rect.height >= minimumSize else {
            return nil
        }
        self.rect = rect
    }
}

public enum ScreenshotTool: String, CaseIterable, Sendable {
    case select
    case crop
    case rectangle
    case arrow
    case pen
    case text
    case mosaic
}

public struct ScreenshotColor: Equatable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = ScreenshotColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
}

public struct AnnotationStyle: Equatable, Sendable {
    public var color: ScreenshotColor
    public var lineWidth: CGFloat
    public var opacity: CGFloat

    public init(color: ScreenshotColor, lineWidth: CGFloat, opacity: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
    }

    public static let `default` = AnnotationStyle(
        color: .red,
        lineWidth: 5,
        opacity: 1
    )
}

public enum ScreenshotAnnotation: Equatable, Sendable {
    case rectangle(id: UUID, rect: CGRect, style: AnnotationStyle)
    case arrow(id: UUID, start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case pen(id: UUID, points: [CGPoint], style: AnnotationStyle)
    case text(id: UUID, rect: CGRect, value: String, fontSize: CGFloat, style: AnnotationStyle)
    case mosaic(id: UUID, rect: CGRect, blockSize: CGFloat)

    public var id: UUID {
        switch self {
        case let .rectangle(id, _, _),
             let .arrow(id, _, _, _),
             let .pen(id, _, _),
             let .text(id, _, _, _, _),
             let .mosaic(id, _, _):
            return id
        }
    }

    public var bounds: CGRect {
        switch self {
        case let .rectangle(_, rect, _),
             let .text(_, rect, _, _, _),
             let .mosaic(_, rect, _):
            return rect.standardized
        case let .arrow(_, start, end, _):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case let .pen(_, points, _):
            guard let first = points.first else { return .null }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
        }
    }

    public func translatedBy(x: CGFloat, y: CGFloat) -> ScreenshotAnnotation {
        let offset = CGVector(dx: x, dy: y)
        switch self {
        case let .rectangle(id, rect, style):
            return .rectangle(id: id, rect: rect.offsetBy(dx: x, dy: y), style: style)
        case let .arrow(id, start, end, style):
            return .arrow(
                id: id,
                start: CGPoint(x: start.x + offset.dx, y: start.y + offset.dy),
                end: CGPoint(x: end.x + offset.dx, y: end.y + offset.dy),
                style: style
            )
        case let .pen(id, points, style):
            return .pen(
                id: id,
                points: points.map { CGPoint(x: $0.x + offset.dx, y: $0.y + offset.dy) },
                style: style
            )
        case let .text(id, rect, value, fontSize, style):
            return .text(
                id: id,
                rect: rect.offsetBy(dx: x, dy: y),
                value: value,
                fontSize: fontSize,
                style: style
            )
        case let .mosaic(id, rect, blockSize):
            return .mosaic(id: id, rect: rect.offsetBy(dx: x, dy: y), blockSize: blockSize)
        }
    }

    public func resized(to newBounds: CGRect) -> ScreenshotAnnotation {
        let target = newBounds.standardized
        let oldBounds = bounds

        func mapped(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: oldBounds.width > 0
                    ? target.minX + (point.x - oldBounds.minX) * target.width / oldBounds.width
                    : target.midX,
                y: oldBounds.height > 0
                    ? target.minY + (point.y - oldBounds.minY) * target.height / oldBounds.height
                    : target.midY
            )
        }

        switch self {
        case let .rectangle(id, _, style):
            return .rectangle(id: id, rect: target, style: style)
        case let .arrow(id, start, end, style):
            return .arrow(id: id, start: mapped(start), end: mapped(end), style: style)
        case let .pen(id, points, style):
            return .pen(id: id, points: points.map(mapped), style: style)
        case let .text(id, _, value, fontSize, style):
            return .text(
                id: id,
                rect: target,
                value: value,
                fontSize: fontSize,
                style: style
            )
        case let .mosaic(id, _, blockSize):
            return .mosaic(id: id, rect: target, blockSize: blockSize)
        }
    }
}

public struct ScreenshotDocumentState: Equatable, Sendable {
    public var cropRect: CGRect
    public var annotations: [ScreenshotAnnotation]

    public init(cropRect: CGRect, annotations: [ScreenshotAnnotation] = []) {
        self.cropRect = cropRect
        self.annotations = annotations
    }

    public func adding(_ annotation: ScreenshotAnnotation) -> ScreenshotDocumentState {
        var copy = self
        copy.annotations.append(annotation)
        return copy
    }

    public func withCropRect(_ cropRect: CGRect) -> ScreenshotDocumentState {
        var copy = self
        copy.cropRect = cropRect
        return copy
    }

    public func replacing(_ annotation: ScreenshotAnnotation) -> ScreenshotDocumentState {
        var copy = self
        guard let index = copy.annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return copy
        }
        copy.annotations[index] = annotation
        return copy
    }

    public func removingAnnotation(id: UUID) -> ScreenshotDocumentState {
        var copy = self
        copy.annotations.removeAll { $0.id == id }
        return copy
    }
}
