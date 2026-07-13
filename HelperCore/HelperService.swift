import Foundation
import HelperIPC

public protocol FanHardwareControlling: AnyObject {
    func fanCount() -> Int
    func currentRPM(index: Int) -> Int?
    func minimumRPM(index: Int) -> Int?
    func maximumRPM(index: Int) -> Int?
    func targetRPM(index: Int) -> Int?
    func mode(index: Int) -> Int?
    func setFanSpeed(index: Int, rpm: Int) throws
    func resetFanToAuto(index: Int) throws
    func temperatures() -> [HelperTemperatureSnapshot]
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
            let ranges = (0..<hardware.fanCount()).map { fanIndex in
                let minimum = hardware.minimumRPM(index: fanIndex) ?? 0
                let maximum = hardware.maximumRPM(index: fanIndex) ?? 0
                return min(minimum, maximum)...max(minimum, maximum)
            }

            switch FanRequestValidator.validate(index: index, rpm: rpm, ranges: ranges) {
            case .invalidFan:
                return .failure("Invalid fan index: \(index)")
            case .invalidRPM:
                return .failure("RPM \(rpm) is outside the allowed range")
            case .valid:
                do {
                    try hardware.setFanSpeed(index: index, rpm: rpm)
                    return .success
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
        }
    }

    public func resetFanToAuto(index: Int) -> HelperOperationResult {
        locked {
            guard (0..<hardware.fanCount()).contains(index) else {
                return .failure("Invalid fan index: \(index)")
            }
            do {
                try hardware.resetFanToAuto(index: index)
                return .success
            } catch {
                return .failure(error.localizedDescription)
            }
        }
    }

    public func resetAllFansToAuto() -> HelperOperationResult {
        locked {
            var errors: [String] = []
            for index in 0..<hardware.fanCount() {
                do {
                    try hardware.resetFanToAuto(index: index)
                } catch {
                    errors.append("Fan \(index): \(error.localizedDescription)")
                }
            }
            return errors.isEmpty ? .success : .failure(errors.joined(separator: "; "))
        }
    }

    public func fanSnapshots() -> [HelperFanSnapshot] {
        locked {
            (0..<hardware.fanCount()).map { index in
                HelperFanSnapshot(
                    index: index,
                    currentRPM: hardware.currentRPM(index: index) ?? 0,
                    minimumRPM: hardware.minimumRPM(index: index) ?? 0,
                    maximumRPM: hardware.maximumRPM(index: index) ?? 0,
                    targetRPM: hardware.targetRPM(index: index),
                    mode: hardware.mode(index: index) ?? 0
                )
            }
        }
    }

    public func temperatures() -> [HelperTemperatureSnapshot] {
        locked { hardware.temperatures() }
    }

    public func temperaturePayload() throws -> Data {
        try HelperPayloadCodec.encodeTemperatures(temperatures())
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
