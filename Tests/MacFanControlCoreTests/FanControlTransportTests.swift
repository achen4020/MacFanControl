import XCTest
@testable import MacFanControlCore

final class FanControlTransportTests: XCTestCase {
    func testAppleSiliconAlwaysUsesHelperWhenConnectionNeedsReestablishing() {
        XCTAssertEqual(
            FanControlTransport.resolve(
                isAppleSilicon: true,
                helperAvailable: false
            ),
            .helper
        )
    }

    func testIntelWithoutHelperUsesLegacySMC() {
        XCTAssertEqual(
            FanControlTransport.resolve(
                isAppleSilicon: false,
                helperAvailable: false
            ),
            .legacySMC
        )
    }

    func testIntelWithHelperUsesHelper() {
        XCTAssertEqual(
            FanControlTransport.resolve(
                isAppleSilicon: false,
                helperAvailable: true
            ),
            .helper
        )
    }
}
