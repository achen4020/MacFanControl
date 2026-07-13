import XCTest
@testable import HelperIPC

final class HelperModelsTests: XCTestCase {
    func testFanSnapshotsRoundTripThroughCodec() throws {
        let snapshots = [
            HelperFanSnapshot(
                index: 0,
                currentRPM: 2_100,
                minimumRPM: 1_200,
                maximumRPM: 5_900,
                targetRPM: 3_000,
                mode: 1
            ),
            HelperFanSnapshot(
                index: 1,
                currentRPM: 1_500,
                minimumRPM: 1_000,
                maximumRPM: 5_500,
                targetRPM: nil,
                mode: 0
            )
        ]

        let encoded = try HelperPayloadCodec.encodeFans(snapshots)

        XCTAssertEqual(try HelperPayloadCodec.decodeFans(encoded), snapshots)
    }

    func testTemperatureSnapshotsRoundTripThroughCodec() throws {
        let snapshots = [
            HelperTemperatureSnapshot(key: "TC0P", name: "CPU Proximity", value: 52.5),
            HelperTemperatureSnapshot(key: "TG0P", name: "GPU Proximity", value: 48.25)
        ]

        let encoded = try HelperPayloadCodec.encodeTemperatures(snapshots)

        XCTAssertEqual(try HelperPayloadCodec.decodeTemperatures(encoded), snapshots)
    }

    func testDecodeFansRejectsMalformedJSON() {
        XCTAssertThrowsError(try HelperPayloadCodec.decodeFans(Data("{".utf8)))
    }

    func testDecodeTemperaturesRejectsMalformedJSON() {
        XCTAssertThrowsError(try HelperPayloadCodec.decodeTemperatures(Data("not-json".utf8)))
    }
}
