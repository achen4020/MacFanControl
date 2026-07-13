import XCTest
import HelperIPC
import SMCKit
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

    func testMissingMinimumFailsClosedWithoutWriting() {
        let hardware = FakeFanHardware()
        hardware.minimumRPMValues[0] = nil
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result.error, HelperServiceError.hardwareReadFailed.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testMissingMaximumFailsClosedWithoutWriting() {
        let hardware = FakeFanHardware()
        hardware.maximumRPMValues[0] = nil
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result.error, HelperServiceError.hardwareReadFailed.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testMissingBothBoundsFailsClosedWithoutWriting() {
        let hardware = FakeFanHardware()
        hardware.minimumRPMValues[0] = nil
        hardware.maximumRPMValues[0] = nil
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result.error, HelperServiceError.hardwareReadFailed.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testInvertedBoundsFailClosedWithoutWriting() {
        let hardware = FakeFanHardware()
        hardware.minimumRPMValues[0] = 4_000
        hardware.maximumRPMValues[0] = 1_000
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result.error, HelperServiceError.hardwareReadFailed.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testZeroBoundFailsClosedWithoutWriting() {
        let hardware = FakeFanHardware()
        hardware.minimumRPMValues[0] = 0
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result.error, HelperServiceError.hardwareReadFailed.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testZeroRPMIsRejectedWithoutWriting() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 0)

        XCTAssertEqual(result.error, HelperServiceError.invalidRPM.rawValue)
        XCTAssertEqual(hardware.speedWrites, [])
    }

    func testValidRequestWritesOnlyRequestedFan() {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 1, rpm: 3_200)

        XCTAssertEqual(result, HelperOperationResult(success: true, error: nil))
        XCTAssertEqual(hardware.speedWrites, [FanWrite(index: 1, rpm: 3_200)])
    }

    func testValidRequestIgnoresUnrelatedFanRangeReadFailure() {
        let hardware = FakeFanHardware()
        hardware.rangeReadFailureIndices = [1]
        let service = HelperService(hardware: hardware)

        let result = service.setFanSpeed(index: 0, rpm: 2_000)

        XCTAssertEqual(result, HelperOperationResult(success: true, error: nil))
        XCTAssertEqual(hardware.speedWrites, [FanWrite(index: 0, rpm: 2_000)])
    }

    func testResetAllAttemptsEveryFanAfterFailure() {
        let hardware = FakeFanHardware()
        hardware.reportedFanCount = 3
        hardware.resetFailureIndices = [1]
        let service = HelperService(hardware: hardware)

        let result = service.resetAllFansToAuto()

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(hardware.resetWrites, [0, 1, 2])
    }

    func testResetAllAggregatesMultipleFailuresWithFanNumbers() {
        let hardware = FakeFanHardware()
        hardware.reportedFanCount = 3
        hardware.resetFailureIndices = [0, 2]
        let service = HelperService(hardware: hardware)

        let result = service.resetAllFansToAuto()

        XCTAssertEqual(result.error, "\(HelperServiceError.hardwareResetFailed.rawValue):fans=0,2")
        XCTAssertEqual(hardware.resetWrites, [0, 1, 2])
    }

    func testFanSnapshotsContainAllFanFields() throws {
        let hardware = FakeFanHardware()
        let service = HelperService(hardware: hardware)

        XCTAssertEqual(try service.fanSnapshots(), [
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
        XCTAssertEqual(result.error, HelperServiceError.hardwareWriteFailed.rawValue)
    }

    func testFanSnapshotReadErrorIsThrown() {
        let hardware = FakeFanHardware()
        hardware.readError = TestError.readFailed
        let service = HelperService(hardware: hardware)

        XCTAssertThrowsError(try service.fanSnapshots()) { error in
            XCTAssertEqual(error as? HelperServiceError, .hardwareReadFailed)
        }
    }

    func testFanSnapshotMissingRequiredReadingIsThrown() {
        let hardware = FakeFanHardware()
        hardware.minimumRPMValues[0] = nil
        let service = HelperService(hardware: hardware)

        XCTAssertThrowsError(try service.fanSnapshots()) { error in
            XCTAssertEqual(error as? HelperServiceError, .hardwareReadFailed)
        }
    }

    func testTemperatureReadErrorIsThrown() {
        let hardware = FakeFanHardware()
        hardware.readError = TestError.readFailed
        let service = HelperService(hardware: hardware)

        XCTAssertThrowsError(try service.temperaturePayload()) { error in
            XCTAssertEqual(error as? HelperServiceError, .hardwareReadFailed)
        }
    }

    func testFanlessHardwareProducesEmptySnapshotWithoutReadFailure() throws {
        let hardware = FakeFanHardware()
        hardware.reportedFanCount = 0
        let service = HelperService(hardware: hardware)

        XCTAssertEqual(try service.fanSnapshots(), [])
        XCTAssertEqual(service.setFanSpeed(index: 0, rpm: 2_000).error, HelperServiceError.invalidFan.rawValue)
    }

    func testSMCAdapterPreservesTemperatureKeyAndDisplayName() throws {
        let manager = FakeSMCManager()
        manager.temperatureSensors = [
            SMCTemperatureSensor(key: "TC0P", name: "CPU Proximity", value: 52.5),
        ]
        let hardware = SMCFanHardware(manager: manager)

        XCTAssertEqual(try hardware.temperatures(), [
            HelperTemperatureSnapshot(key: "TC0P", name: "CPU Proximity", value: 52.5),
        ])
    }

    func testSMCAdapterPropagatesReadFailureToService() {
        let manager = FakeSMCManager()
        manager.readError = TestError.readFailed
        let service = HelperService(hardware: SMCFanHardware(manager: manager))

        XCTAssertThrowsError(try service.fanSnapshots()) { error in
            XCTAssertEqual(error as? HelperServiceError, .hardwareReadFailed)
        }
    }

    func testIntelPolicySkipsTestModeWrite() throws {
        var writeAttempts = 0
        let policy = SMCTestModePolicy(requiresTestMode: false)

        try policy.unlock {
            writeAttempts += 1
            throw TestError.writeFailed
        }
        try policy.lock {
            writeAttempts += 1
            throw TestError.writeFailed
        }

        XCTAssertEqual(writeAttempts, 0)
    }

    func testAppleSiliconPolicyPropagatesUnlockFailure() {
        let policy = SMCTestModePolicy(requiresTestMode: true)

        XCTAssertThrowsError(try policy.unlock {
            throw TestError.writeFailed
        })
    }

    func testAppleSiliconPolicyPropagatesLockFailure() {
        let policy = SMCTestModePolicy(requiresTestMode: true)

        XCTAssertThrowsError(try policy.lock {
            throw TestError.writeFailed
        })
    }

    func testTemperatureDiscoverySkipsUnavailableKeyAndKeepsIdentity() throws {
        let manager = FakeSMCManager()
        manager.temperatureDescriptors = [
            SMCTemperatureSensorDescriptor(key: "MISSING", name: "Missing"),
            SMCTemperatureSensorDescriptor(key: "TC0P", name: "CPU Proximity"),
        ]
        manager.temperatureRead = { key in
            if key == "MISSING" { throw SMCError.smcError(1) }
            return 52.5
        }

        XCTAssertEqual(try SMCFanHardware(manager: manager).temperatures(), [
            HelperTemperatureSnapshot(key: "TC0P", name: "CPU Proximity", value: 52.5),
        ])
    }

    func testTemperatureDiscoveryPropagatesUnderlyingCallFailure() {
        let manager = FakeSMCManager()
        manager.temperatureDescriptors = [SMCTemperatureSensorDescriptor(key: "TC0P", name: "CPU Proximity")]
        manager.temperatureRead = { _ in throw SMCError.callFailed(-1) }

        XCTAssertThrowsError(try SMCFanHardware(manager: manager).temperatures()) { error in
            guard case SMCError.callFailed(-1) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private struct FanWrite: Equatable {
    let index: Int
    let rpm: Int
}

private enum TestError: Error {
    case readFailed
    case writeFailed
    case resetFailed
}

private final class FakeFanHardware: FanHardwareControlling {
    var reportedFanCount = 2
    let currentRPMValues = [1_500, 2_500]
    var minimumRPMValues: [Int?] = [1_000, 2_000]
    var maximumRPMValues: [Int?] = [4_000, 5_000]
    let targetRPMValues: [Int?] = [1_800, 2_800]
    let modeValues = [0, 1]
    let temperatureValues = [
        HelperTemperatureSnapshot(key: "TC0P", name: "CPU Proximity", value: 52.5),
    ]
    var speedWrites: [FanWrite] = []
    var resetWrites: [Int] = []
    var resetFailureIndices: Set<Int> = []
    var speedWriteError: Error?
    var readError: Error?
    var rangeReadFailureIndices: Set<Int> = []

    func fanCount() throws -> Int { try checkRead(); return reportedFanCount }
    func currentRPM(index: Int) throws -> Int? { try checkRead(); return currentRPMValues[safe: index] }
    func minimumRPM(index: Int) throws -> Int? { try checkRangeRead(index: index); return minimumRPMValues[safe: index] ?? nil }
    func maximumRPM(index: Int) throws -> Int? { try checkRangeRead(index: index); return maximumRPMValues[safe: index] ?? nil }
    func targetRPM(index: Int) throws -> Int? { try checkRead(); return targetRPMValues[safe: index] ?? nil }
    func mode(index: Int) throws -> Int? { try checkRead(); return modeValues[safe: index] }

    func setFanSpeed(index: Int, rpm: Int) throws {
        if let speedWriteError { throw speedWriteError }
        speedWrites.append(FanWrite(index: index, rpm: rpm))
    }

    func resetFanToAuto(index: Int) throws {
        resetWrites.append(index)
        if resetFailureIndices.contains(index) { throw TestError.resetFailed }
    }

    func temperatures() throws -> [HelperTemperatureSnapshot] { try checkRead(); return temperatureValues }

    private func checkRead() throws {
        if let readError { throw readError }
    }

    private func checkRangeRead(index: Int) throws {
        try checkRead()
        if rangeReadFailureIndices.contains(index) { throw TestError.readFailed }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class FakeSMCManager: SMCManaging {
    var temperatureSensors: [SMCTemperatureSensor] = []
    var temperatureDescriptors: [SMCTemperatureSensorDescriptor] = []
    var temperatureRead: ((String) throws -> Double?)?
    var readError: Error?

    func readFanCount() throws -> Int {
        if let readError { throw readError }
        return 0
    }
    func readFanSpeed(index: Int) throws -> Int? { nil }
    func readFanMinSpeed(index: Int) throws -> Int? { nil }
    func readFanMaxSpeed(index: Int) throws -> Int? { nil }
    func readFanTargetSpeed(index: Int) throws -> Int? { nil }
    func readFanMode(index: Int) throws -> Int? { nil }
    func setFanSpeed(index: Int, speed: Int) throws {}
    func resetFanToAuto(index: Int) throws {}
    func readAllTemperatureSensors() throws -> [SMCTemperatureSensor] {
        if let temperatureRead {
            return try SMCTemperatureDiscovery.read(
                descriptors: temperatureDescriptors,
                readTemperature: temperatureRead
            )
        }
        return temperatureSensors
    }
}
