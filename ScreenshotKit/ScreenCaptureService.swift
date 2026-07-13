import AppKit
import CoreGraphics

public struct CapturedDisplay {
    public let image: CGImage
    public let displayID: CGDirectDisplayID
    public let geometry: DisplayGeometry

    public init(image: CGImage, displayID: CGDirectDisplayID, geometry: DisplayGeometry) {
        self.image = image
        self.displayID = displayID
        self.geometry = geometry
    }
}

public protocol ScreenCaptureProviding {
    func hasPermission() -> Bool
    func requestPermission() -> Bool
    func captureDisplay(containing point: CGPoint) throws -> CapturedDisplay
}

public struct ScreenCaptureSessionState: Sendable {
    public private(set) var isActive = false

    public init() {}

    public mutating func begin() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    public mutating func finish() {
        isActive = false
    }
}

public enum ScreenCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case noDisplay
    case captureFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得屏幕录制权限"
        case .noDisplay:
            return "未找到鼠标所在显示器"
        case .captureFailed:
            return "无法读取显示器画面"
        }
    }
}

public final class CoreGraphicsScreenCaptureProvider: ScreenCaptureProviding {
    public init() {}

    public func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureDisplay(containing point: CGPoint) throws -> CapturedDisplay {
        guard hasPermission() else {
            throw ScreenCaptureError.permissionDenied
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber else {
            throw ScreenCaptureError.noDisplay
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let image = CGDisplayCreateImage(displayID) else {
            throw ScreenCaptureError.captureFailed
        }

        return CapturedDisplay(
            image: image,
            displayID: displayID,
            geometry: DisplayGeometry(
                frameInPoints: screen.frame,
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        )
    }
}
