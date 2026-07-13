import Foundation
import HelperIPC

public protocol FanHardwareControlling: AnyObject {
    func fanCount() throws -> Int
    func currentRPM(index: Int) throws -> Int?
    func minimumRPM(index: Int) throws -> Int?
    func maximumRPM(index: Int) throws -> Int?
    func targetRPM(index: Int) throws -> Int?
    func mode(index: Int) throws -> Int?
    func setFanSpeed(index: Int, rpm: Int) throws
    func resetFanToAuto(index: Int) throws
    func temperatures() throws -> [HelperTemperatureSnapshot]
}

public enum HelperServiceError: String, Error, Equatable, Sendable {
    case invalidFan = "invalid_fan"
    case invalidRPM = "invalid_rpm"
    case hardwareReadFailed = "hardware_read_failed"
    case hardwareWriteFailed = "hardware_write_failed"
    case hardwareResetFailed = "hardware_reset_failed"
}

public struct HelperOperationResult: Equatable, Sendable {
    public let success: Bool
    public let error: String?

    public init(success: Bool, error: String?) {
        self.success = success
        self.error = error
    }
}

public final class HelperService {
    private let hardware: FanHardwareControlling
    private let lock = NSLock()

    public init(hardware: FanHardwareControlling) {
        self.hardware = hardware
    }

    public func setFanSpeed(index: Int, rpm: Int) -> HelperOperationResult {
        locked {
            let ranges: [ClosedRange<Int>]
            do {
                let count = try hardware.fanCount()
                guard count >= 0 else {
                    return .failure(HelperServiceError.hardwareReadFailed.rawValue)
                }
                guard (0..<count).contains(index) else {
                    return .failure(HelperServiceError.invalidFan.rawValue)
                }
                guard
                    let minimum = try hardware.minimumRPM(index: index),
                    let maximum = try hardware.maximumRPM(index: index),
                    minimum > 0,
                    maximum > 0,
                    minimum <= maximum
                else {
                    return .failure(HelperServiceError.hardwareReadFailed.rawValue)
                }
                ranges = Array(repeating: minimum...maximum, count: count)
            } catch {
                return .failure(HelperServiceError.hardwareReadFailed.rawValue)
            }

            switch FanRequestValidator.validate(index: index, rpm: rpm, ranges: ranges) {
            case .invalidFan:
                return .failure(HelperServiceError.invalidFan.rawValue)
            case .invalidRPM:
                return .failure(HelperServiceError.invalidRPM.rawValue)
            case .valid:
                do {
                    try hardware.setFanSpeed(index: index, rpm: rpm)
                    return .success
                } catch {
                    return .failure(HelperServiceError.hardwareWriteFailed.rawValue)
                }
            }
        }
    }

    public func resetFanToAuto(index: Int) -> HelperOperationResult {
        locked {
            let count: Int
            do {
                count = try hardware.fanCount()
            } catch {
                return .failure(HelperServiceError.hardwareReadFailed.rawValue)
            }
            guard (0..<count).contains(index) else {
                return .failure(HelperServiceError.invalidFan.rawValue)
            }
            do {
                try hardware.resetFanToAuto(index: index)
                return .success
            } catch {
                return .failure("\(HelperServiceError.hardwareResetFailed.rawValue):fans=\(index)")
            }
        }
    }

    public func resetAllFansToAuto() -> HelperOperationResult {
        locked {
            let count: Int
            do {
                count = try hardware.fanCount()
            } catch {
                return .failure(HelperServiceError.hardwareReadFailed.rawValue)
            }
            var failedFans: [Int] = []
            for index in 0..<count {
                do {
                    try hardware.resetFanToAuto(index: index)
                } catch {
                    failedFans.append(index)
                }
            }
            return failedFans.isEmpty
                ? .success
                : .failure("\(HelperServiceError.hardwareResetFailed.rawValue):fans=\(failedFans.map(String.init).joined(separator: ","))")
        }
    }

    public func fanSnapshots() throws -> [HelperFanSnapshot] {
        try locked {
            do {
                return try (0..<hardware.fanCount()).map { index in
                    guard
                        let currentRPM = try hardware.currentRPM(index: index),
                        let minimumRPM = try hardware.minimumRPM(index: index),
                        let maximumRPM = try hardware.maximumRPM(index: index),
                        let mode = try hardware.mode(index: index)
                    else {
                        throw HelperServiceError.hardwareReadFailed
                    }
                    return HelperFanSnapshot(
                        index: index,
                        currentRPM: currentRPM,
                        minimumRPM: minimumRPM,
                        maximumRPM: maximumRPM,
                        targetRPM: try hardware.targetRPM(index: index),
                        mode: mode
                    )
                }
            } catch {
                throw HelperServiceError.hardwareReadFailed
            }
        }
    }

    public func temperatures() throws -> [HelperTemperatureSnapshot] {
        try locked {
            do {
                return try hardware.temperatures()
            } catch {
                throw HelperServiceError.hardwareReadFailed
            }
        }
    }

    public func temperaturePayload() throws -> Data {
        try HelperPayloadCodec.encodeTemperatures(try temperatures())
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

private extension HelperOperationResult {
    static let success = HelperOperationResult(success: true, error: nil)

    static func failure(_ error: String) -> HelperOperationResult {
        HelperOperationResult(success: false, error: error)
    }
}
