import Foundation

public enum ScreenshotClipboardError: LocalizedError, Equatable {
    case noImage
    case invalidImage
    case imageTooLarge
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .noImage:
            return "剪贴板中没有可用图片"
        case .invalidImage:
            return "剪贴板图片无效"
        case .imageTooLarge:
            return "图片超过一亿像素，请缩小后重试"
        case .writeFailed:
            return "无法写入系统剪贴板"
        }
    }
}

public struct ScreenshotClipboardPolicy: Sendable {
    public let maximumPixels: Int

    public init(maximumPixels: Int = 100_000_000) {
        self.maximumPixels = maximumPixels
    }

    public func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ScreenshotClipboardError.invalidImage
        }
        guard height <= maximumPixels,
              width <= maximumPixels / height else {
            throw ScreenshotClipboardError.imageTooLarge
        }
    }
}
