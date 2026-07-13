import XCTest
@testable import HelperIPC

final class FanRequestValidatorTests: XCTestCase {
    private let ranges = [1_200...5_900, 1_000...5_500]

    func testAcceptsExistingFanAtInclusiveRPMBounds() {
        XCTAssertEqual(FanRequestValidator.validate(index: 0, rpm: 1_200, ranges: ranges), .valid)
        XCTAssertEqual(FanRequestValidator.validate(index: 1, rpm: 5_500, ranges: ranges), .valid)
    }

    func testRejectsNegativeAndOutOfBoundsFanIndexes() {
        XCTAssertEqual(FanRequestValidator.validate(index: -1, rpm: 2_000, ranges: ranges), .invalidFan)
        XCTAssertEqual(FanRequestValidator.validate(index: 2, rpm: 2_000, ranges: ranges), .invalidFan)
    }

    func testRejectsRPMOutsideSelectedFanRange() {
        XCTAssertEqual(FanRequestValidator.validate(index: 0, rpm: 1_199, ranges: ranges), .invalidRPM)
        XCTAssertEqual(FanRequestValidator.validate(index: 1, rpm: 5_501, ranges: ranges), .invalidRPM)
    }
}
