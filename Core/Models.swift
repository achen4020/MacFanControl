// Models.swift - 数据模型定义

import Foundation

// MARK: - Error Types

public enum AppError: LocalizedError, Equatable {
    case helperNotInstalled
    case helperInstallFailed(String)
    case helperNotFound
    case sensorAccessFailed
    case fanControlFailed(String)
    case fanResetFailed
    case fanControlUnavailable
    case settingsLoadFailed(String)
    case settingsSaveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return "请先安装 SMC Helper"
        case .helperInstallFailed(let detail):
            return detail
        case .helperNotFound:
            return "找不到 smc_helper 文件"
        case .sensorAccessFailed:
            return "无法访问传感器"
        case .fanControlFailed(let detail):
            return "无法设置风扇速度: \(detail)"
        case .fanResetFailed:
            return "无法重置风扇"
        case .fanControlUnavailable:
            return "此 Mac 无法手动控制风扇"
        case .settingsLoadFailed(let detail):
            return "配置加载失败: \(detail)"
        case .settingsSaveFailed(let detail):
            return "配置保存失败: \(detail)"
        }
    }
}

// MARK: - Data Models

/// Unified temperature reading (shared across providers)
public struct TemperatureReading: Equatable {
    public let name: String
    public let temperature: Double

    public init(name: String, temperature: Double) {
        self.name = name
        self.temperature = temperature
    }
}

// MARK: - Protocols

/// Protocol for temperature data providers
public protocol TemperatureProvider {
    func getTemperatures() -> [TemperatureReading]
    func getCPUTemperature() -> Double?
    func getMaxTemperature() -> Double?
}

/// Protocol for fan control operations
public protocol FanControlProvider: Sendable {
    var isAvailable: Bool { get }
    func getFanCount() -> Int
    func getFanData() -> [FanDataSnapshot]
    func setFanSpeed(_ rpm: Int) -> Bool
    func resetToAuto() -> Bool
}

/// Snapshot of fan data from a provider
public struct FanDataSnapshot {
    public let index: Int
    public let currentSpeed: Int
    public let minSpeed: Int
    public let maxSpeed: Int
    public let mode: Int  // 0 = auto, 1 = manual

    public init(index: Int, currentSpeed: Int, minSpeed: Int, maxSpeed: Int, mode: Int) {
        self.index = index
        self.currentSpeed = currentSpeed
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
        self.mode = mode
    }
}
/// Fan information
public struct FanInfo: Identifiable, Equatable, Sendable {
    public let id: Int
    public var currentSpeed: Int
    public var minSpeed: Int
    public var maxSpeed: Int
    public var targetSpeed: Int?
    public var isManualMode: Bool

    public init(id: Int, currentSpeed: Int, minSpeed: Int, maxSpeed: Int, targetSpeed: Int? = nil, isManualMode: Bool) {
        self.id = id
        self.currentSpeed = currentSpeed
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
        self.targetSpeed = targetSpeed
        self.isManualMode = isManualMode
    }

    public var speedPercentage: Double {
        guard maxSpeed > minSpeed else { return 0 }
        return Double(currentSpeed - minSpeed) / Double(maxSpeed - minSpeed) * 100
    }

    public static func == (lhs: FanInfo, rhs: FanInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.currentSpeed == rhs.currentSpeed &&
        lhs.minSpeed == rhs.minSpeed &&
        lhs.maxSpeed == rhs.maxSpeed &&
        lhs.targetSpeed == rhs.targetSpeed &&
        lhs.isManualMode == rhs.isManualMode
    }
}

/// Temperature sensor information
public struct TemperatureInfo: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var value: Double

    public init(id: String, name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }

    public var formattedValue: String {
        String(format: "%.1f°C", value)
    }

    private var cpuChannelNumber: Int? {
        let prefix = "PMU tdie"
        guard name.hasPrefix(prefix) else { return nil }

        let suffix = name.dropFirst(prefix.count)
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isNumber }),
              let number = Int(suffix),
              number > 0 else { return nil }
        return number
    }

    /// User-facing name for sensors whose hardware meaning is reliable.
    public var displayName: String? {
        if let channel = cpuChannelNumber {
            return "CPU 温度通道 \(channel)"
        }
        if name == "NAND CH0 temp" {
            return "SSD"
        }
        return nil
    }

    /// Sensor category ordering. SSD follows every CPU channel.
    public var displayCategoryOrder: Int? {
        if cpuChannelNumber != nil {
            return 0
        }
        if name == "NAND CH0 temp" {
            return 1
        }
        return nil
    }

    /// Natural ordering inside a display category.
    public var displaySortOrder: Int? {
        if let channel = cpuChannelNumber {
            return channel
        }
        if name == "NAND CH0 temp" {
            return 0
        }
        return nil
    }

    public var isDisplayable: Bool {
        displayName != nil
    }

    public var warningLevel: WarningLevel {
        if value >= 95 {
            return .critical
        } else if value >= 80 {
            return .warning
        } else {
            return .normal
        }
    }
}

/// Temperature warning levels
public enum WarningLevel {
    case normal
    case warning
    case critical
}

/// Capacity usage for the macOS startup volume.
public struct StorageUsage: Equatable {
    public let used: UInt64
    public let available: UInt64
    public let total: UInt64
    public let percentage: Double

    public init?(total: UInt64, available: UInt64) {
        guard total > 0, available <= total else { return nil }
        self.total = total
        self.available = available
        self.used = total - available
        self.percentage = Double(used) / Double(total) * 100
    }

    public var formattedUsed: String {
        Self.format(used)
    }

    public var formattedTotal: String {
        Self.format(total)
    }

    private static func format(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000_000 {
            return String(format: "%.1f TB", Double(bytes) / 1_000_000_000_000)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

/// Temperature-based fan curve point
public struct FanCurvePoint: Codable, Equatable {
    public var temperature: Double
    public var fanSpeedPercentage: Double

    public init(temperature: Double, fanSpeedPercentage: Double) {
        self.temperature = temperature
        self.fanSpeedPercentage = fanSpeedPercentage
    }
}

/// Fan control profile
public struct FanProfile: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var curve: [FanCurvePoint]
    public var isActive: Bool = false

    public init(name: String, curve: [FanCurvePoint], isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.curve = curve
        self.isActive = isActive
    }

    public static let silent = FanProfile(
        name: "静音",
        curve: [
            FanCurvePoint(temperature: 40, fanSpeedPercentage: 20),
            FanCurvePoint(temperature: 60, fanSpeedPercentage: 35),
            FanCurvePoint(temperature: 75, fanSpeedPercentage: 50),
            FanCurvePoint(temperature: 85, fanSpeedPercentage: 75),
            FanCurvePoint(temperature: 95, fanSpeedPercentage: 100),
        ]
    )

    public static let balanced = FanProfile(
        name: "平衡",
        curve: [
            FanCurvePoint(temperature: 40, fanSpeedPercentage: 30),
            FanCurvePoint(temperature: 55, fanSpeedPercentage: 45),
            FanCurvePoint(temperature: 70, fanSpeedPercentage: 65),
            FanCurvePoint(temperature: 80, fanSpeedPercentage: 85),
            FanCurvePoint(temperature: 90, fanSpeedPercentage: 100),
        ]
    )

    public static let performance = FanProfile(
        name: "性能",
        curve: [
            FanCurvePoint(temperature: 35, fanSpeedPercentage: 40),
            FanCurvePoint(temperature: 50, fanSpeedPercentage: 60),
            FanCurvePoint(temperature: 65, fanSpeedPercentage: 80),
            FanCurvePoint(temperature: 75, fanSpeedPercentage: 95),
            FanCurvePoint(temperature: 85, fanSpeedPercentage: 100),
        ]
    )

    public func targetSpeedPercentage(for temperature: Double) -> Double {
        guard !curve.isEmpty else { return 50 }

        let sortedCurve = curve.sorted { $0.temperature < $1.temperature }

        if temperature <= sortedCurve.first!.temperature {
            return sortedCurve.first!.fanSpeedPercentage
        }

        if temperature >= sortedCurve.last!.temperature {
            return sortedCurve.last!.fanSpeedPercentage
        }

        for i in 0..<(sortedCurve.count - 1) {
            let lower = sortedCurve[i]
            let upper = sortedCurve[i + 1]

            if temperature >= lower.temperature && temperature <= upper.temperature {
                let ratio = (temperature - lower.temperature) / (upper.temperature - lower.temperature)
                return lower.fanSpeedPercentage + ratio * (upper.fanSpeedPercentage - lower.fanSpeedPercentage)
            }
        }

        return 50
    }
}

/// Complete persisted state for fan profiles and automatic control.
public struct FanControlSettings: Codable, Equatable {
    public var profiles: [FanProfile]
    public var activeProfileID: UUID?
    public var isAutoControlEnabled: Bool

    public init(
        profiles: [FanProfile],
        activeProfileID: UUID? = nil,
        isAutoControlEnabled: Bool = false
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.isAutoControlEnabled = isAutoControlEnabled
    }

    /// Keeps the selected profile and each profile's display state consistent.
    public func normalized() -> FanControlSettings {
        var result = self
        let hasActiveProfile = result.activeProfileID.map { id in
            result.profiles.contains { $0.id == id }
        } ?? false

        if !result.isAutoControlEnabled || !hasActiveProfile {
            result.activeProfileID = nil
            result.isAutoControlEnabled = false
        }

        for index in result.profiles.indices {
            result.profiles[index].isActive =
                result.isAutoControlEnabled && result.profiles[index].id == result.activeProfileID
        }
        return result
    }

    /// Adds or replaces the custom curve while preserving its stable identifier.
    public func updatingCustomProfile(curve: [FanCurvePoint]) -> FanControlSettings {
        var result = self
        let sortedCurve = curve.sorted { $0.temperature < $1.temperature }
        let customID: UUID

        if let index = result.profiles.firstIndex(where: { $0.name == "自定义" }) {
            customID = result.profiles[index].id
            result.profiles[index].curve = sortedCurve
        } else {
            let profile = FanProfile(name: "自定义", curve: sortedCurve)
            customID = profile.id
            result.profiles.append(profile)
        }

        result.activeProfileID = customID
        result.isAutoControlEnabled = true
        return result.normalized()
    }
}

/// Encodes complete settings and migrates the legacy profiles-only format.
public struct FanControlSettingsStore {
    public static let settingsKey = "fanControlSettings"
    public static let legacyProfilesKey = "fanProfiles"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> FanControlSettings? {
        if let data = defaults.data(forKey: Self.settingsKey) {
            return try JSONDecoder()
                .decode(FanControlSettings.self, from: data)
                .normalized()
        }

        guard let legacyData = defaults.data(forKey: Self.legacyProfilesKey) else {
            return nil
        }

        let profiles = try JSONDecoder().decode([FanProfile].self, from: legacyData)
        let activeID = profiles.first(where: \.isActive)?.id
        let migrated = FanControlSettings(
            profiles: profiles,
            activeProfileID: activeID,
            isAutoControlEnabled: activeID != nil
        ).normalized()
        try save(migrated)
        return migrated
    }

    public func save(_ settings: FanControlSettings) throws {
        let data = try JSONEncoder().encode(settings.normalized())
        defaults.set(data, forKey: Self.settingsKey)
    }
}
