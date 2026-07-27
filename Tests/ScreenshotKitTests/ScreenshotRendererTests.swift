import CoreGraphics
import XCTest
@testable import ScreenshotKit

final class ScreenshotRendererTests: XCTestCase {
    func testRenderUsesCropDimensions() throws {
        let image = try makeSolidImage(width: 100, height: 80)
        let state = ScreenshotDocumentState(
            cropRect: CGRect(x: 10, y: 20, width: 40, height: 30)
        )

        let result = try ScreenshotRenderer().render(image: image, state: state)

        XCTAssertEqual(result.width, 40)
        XCTAssertEqual(result.height, 30)
    }

    func testRenderPreservesSourcePixelOrientation() throws {
        let image = try makeAsymmetricImage()
        let state = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        let result = try ScreenshotRenderer().render(image: image, state: state)

        XCTAssertEqual(
            try rgbaPixels(of: result),
            [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 0, 255
            ]
        )
    }

    func testPNGEncodingHasExpectedSignature() throws {
        let image = try makeSolidImage(width: 2, height: 2)

        let data = try ScreenshotRenderer().encode(image, format: .png)

        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    func testMosaicRenderPreservesOutputDimensions() throws {
        let image = try makeSolidImage(width: 60, height: 40)
        let state = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 60, height: 40),
            annotations: [
                .mosaic(
                    id: UUID(),
                    rect: CGRect(x: 10, y: 10, width: 30, height: 20),
                    blockSize: 8
                )
            ]
        )

        let result = try ScreenshotRenderer().render(image: image, state: state)

        XCTAssertEqual(result.width, 60)
        XCTAssertEqual(result.height, 40)
    }

    func testMosaicPreservesSourcePixelOrientation() throws {
        let image = try makeQuadrantImage(width: 4, height: 4)
        let state = ScreenshotDocumentState(
            cropRect: CGRect(x: 0, y: 0, width: 4, height: 4),
            annotations: [
                .mosaic(
                    id: UUID(),
                    rect: CGRect(x: 0, y: 0, width: 4, height: 4),
                    blockSize: 2
                )
            ]
        )

        let result = try ScreenshotRenderer().render(image: image, state: state)

        XCTAssertEqual(try rgbaPixel(in: result, x: 0, y: 0), [255, 0, 0, 255])
        XCTAssertEqual(try rgbaPixel(in: result, x: 3, y: 0), [0, 255, 0, 255])
        XCTAssertEqual(try rgbaPixel(in: result, x: 0, y: 3), [0, 0, 255, 255])
        XCTAssertEqual(try rgbaPixel(in: result, x: 3, y: 3), [255, 255, 0, 255])
    }

    func testClipboardImagePolicyRejectsInvalidAndOversizedImages() {
        let policy = ScreenshotClipboardPolicy(maximumPixels: 100_000_000)

        XCTAssertNoThrow(try policy.validate(width: 10_000, height: 10_000))
        XCTAssertThrowsError(try policy.validate(width: 0, height: 100)) { error in
            XCTAssertEqual(error as? ScreenshotClipboardError, .invalidImage)
        }
        XCTAssertThrowsError(try policy.validate(width: 10_001, height: 10_000)) { error in
            XCTAssertEqual(error as? ScreenshotClipboardError, .imageTooLarge)
        }
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeAsymmetricImage() throws -> CGImage {
        let pixels = Data([
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 0, 255
        ])
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        return try XCTUnwrap(
            CGImage(
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [
                    CGBitmapInfo.byteOrder32Big,
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }

    private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                switch (x < width / 2, y < height / 2) {
                case (true, true): pixels.append(contentsOf: [255, 0, 0, 255])
                case (false, true): pixels.append(contentsOf: [0, 255, 0, 255])
                case (true, false): pixels.append(contentsOf: [0, 0, 255, 255])
                case (false, false): pixels.append(contentsOf: [255, 255, 0, 255])
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [
                    CGBitmapInfo.byteOrder32Big,
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }

    private func rgbaPixels(of image: CGImage) throws -> [UInt8] {
        XCTAssertEqual(image.bitsPerPixel, 32)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let bytes = [UInt8](data)
        return (0..<image.height).flatMap { row in
            let start = row * image.bytesPerRow
            return Array(bytes[start..<(start + image.width * 4)])
        }
    }

    private func rgbaPixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let bytes = [UInt8](data)
        let start = y * image.bytesPerRow + x * 4
        return Array(bytes[start..<(start + 4)])
    }
}
