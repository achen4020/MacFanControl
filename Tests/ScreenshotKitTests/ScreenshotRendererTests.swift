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
}
