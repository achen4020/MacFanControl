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
        XCTAssertEqual(info.displayName, "CPU 温度通道 1")
    }

    func testDisplayName_ssd() {
        let info = TemperatureInfo(id: "t1", name: "NAND CH0 temp", value: 40)
        XCTAssertEqual(info.displayName, "SSD")
    }

    func testDisplayName_filtersAmbiguousSensors() {
        let names = [
            "PMU2 tdie1", "PMU tdev1", "PMU2 tdev1",
            "PMU tcal", "PMU2 tcal", "Unknown Sensor",
        ]

        for name in names {
            let info = TemperatureInfo(id: name, name: name, value: 40)
            XCTAssertNil(info.displayName, "\(name) should not be displayed")
            XCTAssertFalse(info.isDisplayable)
        }
    }

    func testDisplayName_requiresCompleteCPUChannelMatch() {
        XCTAssertNil(TemperatureInfo(id: "bad", name: "PMU tdie1 extra", value: 40).displayName)
        XCTAssertNil(TemperatureInfo(id: "zero", name: "PMU tdie0", value: 40).displayName)
    }

    func testDisplaySortOrder_usesNaturalChannelOrderAndSSDLast() {
        let names = ["NAND CH0 temp", "PMU tdie10001", "PMU tdie10", "PMU tdie2"]
        let sorted = names
            .map { TemperatureInfo(id: $0, name: $0, value: 40) }
            .sorted {
                if $0.displayCategoryOrder != $1.displayCategoryOrder {
                    return $0.displayCategoryOrder! < $1.displayCategoryOrder!
                }
                return $0.displaySortOrder! < $1.displaySortOrder!
            }

        XCTAssertEqual(
            sorted.compactMap(\.displayName),
            ["CPU 温度通道 2", "CPU 温度通道 10", "CPU 温度通道 10001", "SSD"]
        )
    }

    // MARK: - StorageUsage

    func testStorageUsage_calculatesUsedCapacityAndPercentage() throws {
        let usage = try XCTUnwrap(
            StorageUsage(total: 500_000_000_000, available: 125_000_000_000)
        )

        XCTAssertEqual(usage.used, 375_000_000_000)
        XCTAssertEqual(usage.percentage, 75, accuracy: 0.001)
        XCTAssertEqual(usage.formattedUsed, "375.0 GB")
        XCTAssertEqual(usage.formattedTotal, "500.0 GB")
    }

    func testStorageUsage_formatsTerabytes() throws {
        let usage = try XCTUnwrap(
            StorageUsage(total: 2_000_000_000_000, available: 500_000_000_000)
        )

        XCTAssertEqual(usage.formattedUsed, "1.5 TB")
        XCTAssertEqual(usage.formattedTotal, "2.0 TB")
    }

    func testStorageUsage_rejectsInvalidCapacity() {
        XCTAssertNil(StorageUsage(total: 0, available: 0))
        XCTAssertNil(StorageUsage(total: 100, available: 101))
    }

    // MARK: - NetworkSpeed

    func testNetworkSpeed_calculatesRatesUsingElapsedTime() {
        let previous = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 2_000)]
        )
        let current = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 5_000, sentBytes: 3_000)]
        )

        let speed = NetworkSpeed.between(previous: previous, current: current)

        XCTAssertEqual(speed.downloadBytesPerSecond, 2_000)
        XCTAssertEqual(speed.uploadBytesPerSecond, 500)
    }

    func testNetworkSpeed_rejectsDiscontinuousSnapshots() {
        let base = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 2_000, sentBytes: 2_000)]
        )
        let changed = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            counters: ["en1": NetworkInterfaceCounters(receivedBytes: 3_000, sentBytes: 3_000)]
        )
        let reset = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 1_000)]
        )
        let invalidTime = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 3_000, sentBytes: 3_000)]
        )

        XCTAssertEqual(NetworkSpeed.between(previous: base, current: changed), .zero)
        XCTAssertEqual(NetworkSpeed.between(previous: base, current: reset), .zero)
        XCTAssertEqual(NetworkSpeed.between(previous: base, current: invalidTime), .zero)
    }

    func testNetworkSpeed_handlesPerInterfaceUInt32CounterWrap() {
        let previous = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            counters: [
                "en0": NetworkInterfaceCounters(
                    receivedBytes: UInt32.max - 999,
                    sentBytes: UInt32.max - 499
                )
            ]
        )
        let current = NetworkTransferSnapshot(
            timestamp: Date(timeIntervalSince1970: 12),
            counters: ["en0": NetworkInterfaceCounters(receivedBytes: 1_000, sentBytes: 500)]
        )

        let speed = NetworkSpeed.between(previous: previous, current: current)

        XCTAssertEqual(speed.downloadBytesPerSecond, 1_000)
        XCTAssertEqual(speed.uploadBytesPerSecond, 500)
    }

    func testPhysicalNetworkInterfaceName_requiresEnFollowedByDigits() {
        XCTAssertTrue(PhysicalNetworkInterface.isSupportedName("en0"))
        XCTAssertTrue(PhysicalNetworkInterface.isSupportedName("en12"))
        XCTAssertFalse(PhysicalNetworkInterface.isSupportedName("en"))
        XCTAssertFalse(PhysicalNetworkInterface.isSupportedName("energy0"))
        XCTAssertFalse(PhysicalNetworkInterface.isSupportedName("awdl0"))
        XCTAssertFalse(PhysicalNetworkInterface.isSupportedName("utun3"))
    }

    func testNetworkSpeed_formatsUnits() {
        XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 500), "500.0 B/s")
        XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 1_500), "1.5 KB/s")
        XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 2_500_000), "2.5 MB/s")
        XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 3_500_000_000), "3.5 GB/s")
        XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: -1), "0.0 B/s")
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

    // MARK: - Fan Control Settings Persistence

    func testFanControlSettings_roundTripPreservesActiveCustomProfile() throws {
        let custom = FanProfile(
            name: "自定义",
            curve: [FanCurvePoint(temperature: 42, fanSpeedPercentage: 33)],
            isActive: true
        )
        let settings = FanControlSettings(
            profiles: [.silent, custom],
            activeProfileID: custom.id,
            isAutoControlEnabled: true
        )

        let decoded = try JSONDecoder().decode(
            FanControlSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded, settings)
    }

    func testFanControlSettings_normalizedDisablesMissingActiveProfile() {
        let settings = FanControlSettings(
            profiles: [.balanced],
            activeProfileID: UUID(),
            isAutoControlEnabled: true
        ).normalized()

        XCTAssertNil(settings.activeProfileID)
        XCTAssertFalse(settings.isAutoControlEnabled)
        XCTAssertFalse(settings.profiles[0].isActive)
    }

    func testFanControlSettings_updatingCustomProfileKeepsStableID() throws {
        let original = FanProfile(
            name: "自定义",
            curve: [FanCurvePoint(temperature: 40, fanSpeedPercentage: 30)]
        )
        let settings = FanControlSettings(profiles: [.silent, original])
        let updated = settings.updatingCustomProfile(curve: [
            FanCurvePoint(temperature: 80, fanSpeedPercentage: 90),
            FanCurvePoint(temperature: 50, fanSpeedPercentage: 45),
        ])

        let custom = try XCTUnwrap(updated.profiles.first { $0.name == "自定义" })
        XCTAssertEqual(custom.id, original.id)
        XCTAssertEqual(custom.curve.map(\.temperature), [50, 80])
        XCTAssertEqual(updated.activeProfileID, original.id)
        XCTAssertTrue(updated.isAutoControlEnabled)
        XCTAssertTrue(custom.isActive)
    }

    func testFanControlSettingsStore_migratesLegacyActiveProfile() throws {
        let suiteName = "ModelsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacy = FanProfile.performance
        legacy.isActive = true
        defaults.set(
            try JSONEncoder().encode([FanProfile.silent, legacy]),
            forKey: FanControlSettingsStore.legacyProfilesKey
        )

        let store = FanControlSettingsStore(defaults: defaults)
        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.activeProfileID, legacy.id)
        XCTAssertTrue(migrated.isAutoControlEnabled)
        XCTAssertNotNil(defaults.data(forKey: FanControlSettingsStore.settingsKey))
    }

    func testFanControlSettingsStore_roundTripsCompleteState() throws {
        let suiteName = "ModelsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let active = FanProfile.silent
        let expected = FanControlSettings(
            profiles: [active],
            activeProfileID: active.id,
            isAutoControlEnabled: true
        ).normalized()
        let store = FanControlSettingsStore(defaults: defaults)

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
    }
}
