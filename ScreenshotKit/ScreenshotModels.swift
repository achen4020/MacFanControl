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
