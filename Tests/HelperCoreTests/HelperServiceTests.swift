import XCTest
import HelperIPC
@testable import MacFanControlHelperCore

final class HelperServiceTests: XCTestCase {
    func testInvalidFanDoesNotWrite() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 2, rpm: 2_000)

        XCTAssertFalse(result.success)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testInvalidRPMDoesNotWrite() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 999)

        XCTAssertFalse(result.success)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testValidRequestWritesOnlyRequestedFan() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 1, rpm: 3_200)

        XCTAssertEqual(result, HelperOperationResult(success: true, error: nil))
        XCTAssertEqual(hardware.speedWrites, [FanWrite(index: 1, rpm: 3_200)])
    }

    func testResetAllAttemptsEveryFanAfterFailure() {
        let hardware = FakeFanHardware()
        hardware.resetFailureIndices = [1]
        let service = HelperService(hardware: hardware)

        let result = service.resetAllFansToAuto()

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(hardware.resetWrites, [0, 1])
    }

    func testFanSnapshotsContainAllFanFields() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        XCTAssertEqual(service.fanSnapshots(), [
            HelperFanSnapshot(index: 0, currentRPM: 1_500, minimumRPM: 1_000, maximumRPM: 4_000, targetRPM: 1_800, mode: 0),
            HelperFanSnapshot(index: 1, currentRPM: 2_500, minimumRPM: 2_000, maximumRPM: 5_000, targetRPM: 2_800, mode: 1),
        ])
    }

    func testTemperaturesAreReturnedAsPayload() throws {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let payload = try service.temperaturePayload()

        XCTAssertEqual(try HelperPayloadCodec.decodeTemperatures(payload), hardware.temperatureValues)
    }

    func testHardwareWriteErrorReturnsFailure() {
        let hardware = FakeFanHardware()
        hardware.speedWriteError = TestError.writeFailed
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
    }
}

private struct FanWrite: Equatable {
    let index: Int
    let rpm: Int
}

private enum TestError: Error {
    case writeFailed
    case resetFailed
}

private final class FakeFanHardware: FanHardwareControlling {
    let fanCount = 2
    let currentRPMValues = [1_500, 2_500]
    let minimumRPMValues = [1_000, 2_000]
    let maximumRPMValues = [4_000, 5_000]
    let targetRPMValues: [Int?] = [1_800, 2_800]
    let modeValues = [0, 1]
    let temperatureValues = [
        HelperTemperatureSnapshot(key: "TC0P", name: "CPU Proximity", value: 52.5),
    ]
    var speedWrites: [FanWrite] = []
    var resetWrites: [Int] = []
    var resetFailureIndices: Set<Int> = []
    var speedWriteError: Error?

    func currentRPM(index: Int) -> Int? { currentRPMValues[safe: index] }
    func minimumRPM(index: Int) -> Int? { minimumRPMValues[safe: index] }
    func maximumRPM(index: Int) -> Int? { maximumRPMValues[safe: index] }
    func targetRPM(index: Int) -> Int? { targetRPMValues[safe: index] ?? nil }
    func mode(index: Int) -> Int? { modeValues[safe: index] }

    func setFanSpeed(index: Int, rpm: Int) throws {
        if let speedWriteError { throw speedWriteError }
        speedWrites.append(FanWrite(index: index, rpm: rpm))
    }

    func resetFanToAuto(index: Int) throws {
        resetWrites.append(index)
        if resetFailureIndices.contains(index) { throw TestError.resetFailed }
    }

    func temperatures() -> [HelperTemperatureSnapshot] { temperatureValues }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
