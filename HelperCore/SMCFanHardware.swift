import HelperIPC
import SMCKit

public final class SMCFanHardware: FanHardwareControlling {
    private let manager: SMCManager

    public init(manager: SMCManager = .shared) {
        self.manager = manager
    }

    public func fanCount() -> Int {
        try? manager.open()
        return manager.getFanCount()
    }

    public func currentRPM(index: Int) -> Int? {
        try? manager.open()
        return manager.getFanSpeed(index: index)
    }

    public func minimumRPM(index: Int) -> Int? {
        try? manager.open()
        return manager.getFanMinSpeed(index: index)
    }

    public func maximumRPM(index: Int) -> Int? {
        try? manager.open()
        return manager.getFanMaxSpeed(index: index)
    }

    public func targetRPM(index: Int) -> Int? {
        try? manager.open()
        return manager.getFanTargetSpeed(index: index)
    }

    public func mode(index: Int) -> Int? {
        try? manager.open()
        return manager.getFanMode(index: index)
    }

    public func setFanSpeed(index: Int, rpm: Int) throws {
        try manager.open()
        try manager.setFanSpeed(index: index, speed: rpm)
    }

    public func resetFanToAuto(index: Int) throws {
        try manager.open()
        try manager.resetFanToAuto(index: index)
    }

    public func temperatures() -> [HelperTemperatureSnapshot] {
        try? manager.open()
        return manager.getAllTemperatureSensors().map { sensor in
            HelperTemperatureSnapshot(key: sensor.key, name: sensor.key, value: sensor.value)
        }
    }
}
