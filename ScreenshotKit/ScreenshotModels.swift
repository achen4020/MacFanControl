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
}
