import XCTest
@testable import MacFanControlCore

final class ModelsTests: XCTestCase {

    // MARK: - FanProfile Curve Interpolation

    func testCurveInterpolation_belowMinTemp() {
        let profile = FanProfile.silent
        // 低于最低温度点(40°C)，应返回最低风扇速度
        let result = profile.targetSpeedPercentage(for: 20)
        XCTAssertEqual(result, 20.0)
    }

    func testCurveInterpolation_aboveMaxTemp() {
        let profile = FanProfile.silent
        // 高于最高温度点(95°C)，应返回最高风扇速度
        let result = profile.targetSpeedPercentage(for: 100)
        XCTAssertEqual(result, 100.0)
    }

    func testCurveInterpolation_exactPoint() {
        let profile = FanProfile.silent
        // 精确匹配温度点
        let result = profile.targetSpeedPercentage(for: 60)
        XCTAssertEqual(result, 35.0)
    }

    func testCurveInterpolation_midpoint() {
        let profile = FanProfile.silent
        // 40°C→20%, 60°C→35%, 中点50°C应为27.5%
        let result = profile.targetSpeedPercentage(for: 50)
        XCTAssertEqual(result, 27.5, accuracy: 0.01)
    }

    func testCurveInterpolation_emptyCurve() {
        let profile = FanProfile(name: "empty", curve: [])
        let result = profile.targetSpeedPercentage(for: 50)
        XCTAssertEqual(result, 50.0)
    }

    func testCurveInterpolation_singlePoint() {
        let profile = FanProfile(name: "single", curve: [
            FanCurvePoint(temperature: 50, fanSpeedPercentage: 60)
        ])
        // 低于唯一点
        XCTAssertEqual(profile.targetSpeedPercentage(for: 30), 60.0)
        // 高于唯一点
        XCTAssertEqual(profile.targetSpeedPercentage(for: 80), 60.0)
    }

    // MARK: - WarningLevel

    func testWarningLevel_normal() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 50)
        XCTAssertEqual(info.warningLevel, .normal)
    }

    func testWarningLevel_warning() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 85)
        XCTAssertEqual(info.warningLevel, .warning)
    }

    func testWarningLevel_critical() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 95)
        XCTAssertEqual(info.warningLevel, .critical)
    }

    func testWarningLevel_boundary80() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 80)
        XCTAssertEqual(info.warningLevel, .warning)
    }

    func testWarningLevel_boundary79() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 79.9)
        XCTAssertEqual(info.warningLevel, .normal)
    }

    // MARK: - TemperatureInfo DisplayName

    func testDisplayName_knownSensor() {
        let info = TemperatureInfo(id: "t1", name: "PMU tdie1", value: 50)
        XCTAssertEqual(info.displayName, "CPU 核心 1")
    }

    func testDisplayName_efficiencyCore() {
        let info = TemperatureInfo(id: "t1", name: "PMU2 tdie3", value: 50)
        XCTAssertEqual(info.displayName, "效率核心 3")
    }

    func testDisplayName_ssd() {
        let info = TemperatureInfo(id: "t1", name: "NAND CH0 temp", value: 40)
        XCTAssertEqual(info.displayName, "SSD 温度")
    }

    func testDisplayName_unknownFallback() {
        let info = TemperatureInfo(id: "t1", name: "Unknown Sensor", value: 50)
        XCTAssertEqual(info.displayName, "Unknown Sensor")
    }

    func testDisplayName_genericTdie() {
        let info = TemperatureInfo(id: "t1", name: "PMU tdie99", value: 50)
        XCTAssertEqual(info.displayName, "CPU 核心 99")
    }

    // MARK: - FanInfo

    func testFanSpeedPercentage() {
        let fan = FanInfo(id: 0, currentSpeed: 3000, minSpeed: 1000, maxSpeed: 5000, isManualMode: false)
        XCTAssertEqual(fan.speedPercentage, 50.0)
    }

    func testFanSpeedPercentage_atMin() {
        let fan = FanInfo(id: 0, currentSpeed: 1000, minSpeed: 1000, maxSpeed: 5000, isManualMode: false)
        XCTAssertEqual(fan.speedPercentage, 0.0)
    }

    func testFanSpeedPercentage_atMax() {
        let fan = FanInfo(id: 0, currentSpeed: 5000, minSpeed: 1000, maxSpeed: 5000, isManualMode: false)
        XCTAssertEqual(fan.speedPercentage, 100.0)
    }

    func testFanSpeedPercentage_equalMinMax() {
        let fan = FanInfo(id: 0, currentSpeed: 3000, minSpeed: 3000, maxSpeed: 3000, isManualMode: false)
        XCTAssertEqual(fan.speedPercentage, 0.0)
    }

    // MARK: - AppError

    func testAppError_descriptions() {
        XCTAssertNotNil(AppError.helperNotInstalled.errorDescription)
        XCTAssertNotNil(AppError.sensorAccessFailed.errorDescription)
        XCTAssertNotNil(AppError.fanResetFailed.errorDescription)
        XCTAssertNotNil(AppError.fanControlUnavailable.errorDescription)
        XCTAssertTrue(AppError.fanControlFailed("test").errorDescription!.contains("test"))
        XCTAssertTrue(AppError.helperInstallFailed("detail").errorDescription!.contains("detail"))
    }

    // MARK: - TemperatureInfo FormattedValue

    func testFormattedValue() {
        let info = TemperatureInfo(id: "t1", name: "CPU", value: 65.3)
        XCTAssertEqual(info.formattedValue, "65.3°C")
    }

    // MARK: - Preset Profiles

    func testPresetProfiles_exist() {
        XCTAssertFalse(FanProfile.silent.curve.isEmpty)
        XCTAssertFalse(FanProfile.balanced.curve.isEmpty)
        XCTAssertFalse(FanProfile.performance.curve.isEmpty)
    }

    func testPresetProfiles_sortedCurves() {
        for profile in [FanProfile.silent, .balanced, .performance] {
            let temps = profile.curve.map { $0.temperature }
            XCTAssertEqual(temps, temps.sorted(), "Profile \(profile.name) curve should be sorted")
        }
    }
}