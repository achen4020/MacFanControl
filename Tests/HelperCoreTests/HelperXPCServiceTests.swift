import XCTest
import HelperIPC
@testable import MacFanControlHelperCore

final class HelperXPCServiceTests: XCTestCase {
    func testGetFanDataEncodesServiceSnapshots() throws {
        let hardware = ForwardingFakeHardware()
        let xpcService = HelperXPCService(service: HelperService(hardware: hardware), version: "2.3.4")
        var receivedData: Data?
        var receivedError: String?

        xpcService.getFanData { data, error in
            receivedData = data
            receivedError = error
        }

        XCTAssertNil(receivedError)
        XCTAssertEqual(try HelperPayloadCodec.decodeFans(try XCTUnwrap(receivedData)), [hardware.snapshot])
    }

    func testReadFailureReturnsStableErrorAndNoPayload() {
        let hardware = ForwardingFakeHardware()
        hardware.readFails = true
        let xpcService = HelperXPCService(service: HelperService(hardware: hardware))

        xpcService.getFanData { data, error in
            XCTAssertNil(data)
            XCTAssertEqual(error, HelperServiceError.hardwareReadFailed.rawValue)
        }
    }

    func testMutationsForwardOperationResults() {
        let hardware = ForwardingFakeHardware()
        let xpcService = HelperXPCService(service: HelperService(hardware: hardware))

        xpcService.setFanSpeed(index: 0, rpm: 2_400) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
        }
        xpcService.resetFanToAuto(index: 0) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
        }
        xpcService.resetAllFansToAuto { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
        }

        XCTAssertEqual(hardware.speedWrites, [2_400])
        XCTAssertEqual(hardware.resetWrites, [0, 0])
    }

    func testTemperaturesAreEncoded() throws {
        let hardware = ForwardingFakeHardware()
        let xpcService = HelperXPCService(service: HelperService(hardware: hardware))
        var receivedData: Data?

        xpcService.getTemperatures { data, error in
            XCTAssertNil(error)
            receivedData = data
        }

        XCTAssertEqual(
            try HelperPayloadCodec.decodeTemperatures(try XCTUnwrap(receivedData)),
            hardware.temperatureSnapshots
        )
    }

    func testVersionIsStable() {
        let xpcService = HelperXPCService(
            service: HelperService(hardware: ForwardingFakeHardware()),
            version: "2.3.4"
        )

        xpcService.getVersion { XCTAssertEqual($0, "2.3.4") }
    }

    func testLegacyRemovalForwardsAuthenticatedXPCRequest() {
        let remover = ForwardingFakeLegacyRemover()
        let hardware = ForwardingFakeHardware()
        let xpcService = HelperXPCService(
            service: HelperService(hardware: hardware),
            legacyRemover: remover
        )

        xpcService.removeLegacyHelper { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
        }
        XCTAssertEqual(remover.callCount, 1)
        XCTAssertEqual(hardware.resetWrites, [0])
    }

    func testLegacyRemovalStopsWhenFanResetFails() {
        let remover = ForwardingFakeLegacyRemover()
        let hardware = ForwardingFakeHardware()
        hardware.resetFails = true
        let xpcService = HelperXPCService(
            service: HelperService(hardware: hardware),
            legacyRemover: remover
        )

        xpcService.removeLegacyHelper { success, error in
            XCTAssertFalse(success)
            XCTAssertEqual(error, "hardware_reset_failed:fans=0")
        }
        XCTAssertEqual(remover.callCount, 0)
    }
}

private final class ForwardingFakeLegacyRemover: LegacyHelperRemoving {
    var callCount = 0

    func remove() -> HelperOperationResult {
        callCount += 1
        return HelperOperationResult(success: true, error: nil)
    }
}

private final class ForwardingFakeHardware: FanHardwareControlling {
    let snapshot = HelperFanSnapshot(
        index: 0,
        currentRPM: 1_600,
        minimumRPM: 1_000,
        maximumRPM: 4_000,
        targetRPM: 1_800,
        mode: 0
    )
    let temperatureSnapshots = [HelperTemperatureSnapshot(key: "TC0P", name: "CPU", value: 52.5)]
    var readFails = false
    var resetFails = false
    var speedWrites: [Int] = []
    var resetWrites: [Int] = []

    func fanCount() throws -> Int { try checkRead(); return 1 }
    func currentRPM(index: Int) throws -> Int? { try checkRead(); return snapshot.currentRPM }
    func minimumRPM(index: Int) throws -> Int? { try checkRead(); return snapshot.minimumRPM }
    func maximumRPM(index: Int) throws -> Int? { try checkRead(); return snapshot.maximumRPM }
    func targetRPM(index: Int) throws -> Int? { try checkRead(); return snapshot.targetRPM }
    func mode(index: Int) throws -> Int? { try checkRead(); return snapshot.mode }
    func setFanSpeed(index: Int, rpm: Int) throws { speedWrites.append(rpm) }
    func resetFanToAuto(index: Int) throws {
        if resetFails { throw ForwardingTestError.resetFailed }
        resetWrites.append(index)
    }
    func temperatures() throws -> [HelperTemperatureSnapshot] { try checkRead(); return temperatureSnapshots }

    private func checkRead() throws {
        if readFails { throw ForwardingTestError.readFailed }
    }
}

private enum ForwardingTestError: Error {
    case readFailed
    case resetFailed
}
