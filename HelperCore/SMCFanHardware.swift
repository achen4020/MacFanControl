import HelperIPC
import SMCKit

public protocol SMCManaging: AnyObject {
    func readFanCount() throws -> Int
    func readFanSpeed(index: Int) throws -> Int?
    func readFanMinSpeed(index: Int) throws -> Int?
    func readFanMaxSpeed(index: Int) throws -> Int?
    func readFanTargetSpeed(index: Int) throws -> Int?
    func readFanMode(index: Int) throws -> Int?
    func setFanSpeed(index: Int, speed: Int) throws
    func resetFanToAuto(index: Int) throws
    func readAllTemperatureSensors() throws -> [SMCTemperatureSensor]
}

extension SMCManager: SMCManaging {}

public final class SMCFanHardware: FanHardwareControlling {
    private let manager: SMCManaging

    public init(manager: SMCManaging = SMCManager.shared) {
        self.manager = manager
    }

    public func fanCount() throws -> Int {
        try manager.readFanCount()
    }

    public func currentRPM(index: Int) throws -> Int? {
        try manager.readFanSpeed(index: index)
    }

    public func minimumRPM(index: Int) throws -> Int? {
        try manager.readFanMinSpeed(index: index)
    }

    public func maximumRPM(index: Int) throws -> Int? {
        try manager.readFanMaxSpeed(index: index)
    }

    public func targetRPM(index: Int) throws -> Int? {
        try manager.readFanTargetSpeed(index: index)
    }

    public func mode(index: Int) throws -> Int? {
        try manager.readFanMode(index: index)
    }

    public func setFanSpeed(index: Int, rpm: Int) throws {
        try manager.setFanSpeed(index: index, speed: rpm)
    }

    public func resetFanToAuto(index: Int) throws {
        try manager.resetFanToAuto(index: index)
    }

    public func temperatures() throws -> [HelperTemperatureSnapshot] {
        try manager.readAllTemperatureSensors().map { sensor in
            HelperTemperatureSnapshot(key: sensor.key, name: sensor.name, value: sensor.value)
        }
    }
}
