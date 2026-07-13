import XCTest
@testable import HelperIPC

final class HelperModelsTests: XCTestCase {
    func testClientFanSnapshotValidationRejectsImpossibleFanData() {
        let valid = HelperFanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 1_000,
            maximumRPM: 5_000,
            targetRPM: nil,
            mode: 0
        )
        let invalidIndex = HelperFanSnapshot(
            index: -1,
            currentRPM: 2_000,
            minimumRPM: 1_000,
            maximumRPM: 5_000,
            targetRPM: nil,
            mode: 0
        )
        let invalidBounds = HelperFanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 5_000,
            maximumRPM: 1_000,
            targetRPM: nil,
            mode: 0
        )

        XCTAssertTrue(valid.isValidForClient)
        XCTAssertFalse(invalidIndex.isValidForClient)
        XCTAssertFalse(invalidBounds.isValidForClient)
    }

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

    func testValidatedFanPayloadAcceptsEmptySnapshotList() throws {
        let payload = try HelperPayloadCodec.encodeFans([])
        let decoded: [HelperFanSnapshot] = try HelperPayloadCodec.decodeValidatedFans(payload)

        XCTAssertEqual(decoded, [])
    }

    func testValidatedFanPayloadRejectsEntireMixedPayload() throws {
        let snapshots = [
            HelperFanSnapshot(
                index: 0,
                currentRPM: 2_000,
                minimumRPM: 1_000,
                maximumRPM: 4_000,
                targetRPM: 2_200,
                mode: 1
            ),
            HelperFanSnapshot(
                index: -1,
                currentRPM: 2_000,
                minimumRPM: 1_000,
                maximumRPM: 4_000,
                targetRPM: 2_200,
                mode: 1
            )
        ]

        XCTAssertThrowsError(
            try HelperPayloadCodec.decodeValidatedFans(HelperPayloadCodec.encodeFans(snapshots))
        )
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
