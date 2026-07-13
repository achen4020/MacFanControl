import CoreGraphics

public struct DisplayGeometry: Equatable, Sendable {
    public let frameInPoints: CGRect
    public let pixelSize: CGSize

    public init(frameInPoints: CGRect, pixelSize: CGSize) {
        self.frameInPoints = frameInPoints
        self.pixelSize = pixelSize
    }

    public func pixelRect(forLocalSelection selection: CGRect) -> CGRect {
        guard frameInPoints.width > 0,
              frameInPoints.height > 0,
              pixelSize.width > 0,
              pixelSize.height > 0 else {
            return .null
        }

        let scaleX = pixelSize.width / frameInPoints.width
        let scaleY = pixelSize.height / frameInPoints.height
        let rawRect = CGRect(
            x: selection.minX * scaleX,
            y: pixelSize.height - selection.maxY * scaleY,
            width: selection.width * scaleX,
            height: selection.height * scaleY
        ).integral

        return rawRect.intersection(CGRect(origin: .zero, size: pixelSize))
    }
}
