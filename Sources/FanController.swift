// FanController.swift - 风扇控制核心逻辑

import Foundation
import Combine
import IOKit
import UserNotifications
@preconcurrency import HelperIPC
@preconcurrency import MacFanControlCore
@preconcurrency import SMCKit
// MARK: - Fan Controller

@MainActor
class FanController: ObservableObject {
    static let shared = FanController()

    // Published properties
    @Published var fans: [FanInfo] = []
    @Published var temperatures: [TemperatureInfo] = []
    @Published var cpuTemperature: Double = 0
    @Published var maxTemperature: Double = 0
    @Published var gpuTemperature: Double?
    @Published var ssdTemperature: Double?
    @Published var storageUsage: StorageUsage?
    @Published var networkSpeed = NetworkSpeed.zero
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: String = ""
    @Published var memoryTotal: String = ""
    @Published var isMonitoring = false
    @Published var lastError: AppError?
    @Published var activeProfile: FanProfile?
    @Published var isAutoControlEnabled = false
    @Published var canControlFans = false
    @Published var isAppleSilicon = true
    @Published var isM4 = false
    @Published var platformInfo: String = ""
    @Published var temperatureSource: String = "未知"
    @Published var sensorCount: Int = 0
    @Published var isInstallingHelper = false
    @Published var helperRegistrationState: HelperRegistrationState = .notFound

    @Published var profiles: [FanProfile] = [.silent, .balanced, .performance]

    // Private
    private let smc: SMCManager
    private let temperatureProvider: TemperatureProvider
    private let smcHelper: SMCHelperClient
    private let helperServiceManager: HelperServiceManager
    private let fanControl: FanControlProvider
    private let cpuLoadMonitor: CPULoadMonitor
    private let memoryMonitor: MemoryMonitor
    private let storageMonitor: StorageMonitor
    private let networkMonitor: NetworkMonitor
    private let settingsStore = FanControlSettingsStore()
    private var monitorTimer: Timer?
    private var autoControlTimer: Timer?
    private var isApplyingAutoControl = false
    private let autoControlApplyGate = ExclusiveOperationGate()
    private var isUpdatingFanInfo = false
    private var isUpdatingTemperatures = false
    private var lastAutoTargetPercentage: Double = -1
    private let updateInterval: TimeInterval = 2.0
    private var lastHighTempNotificationTime: Date?

    private init(
        smc: SMCManager = .shared,
        temperatureProvider: TemperatureProvider = M4TempReader(),
        smcHelper: SMCHelperClient = .shared,
        helperServiceManager: HelperServiceManager? = nil,
        cpuLoadMonitor: CPULoadMonitor = CPULoadMonitor(),
        memoryMonitor: MemoryMonitor = MemoryMonitor(),
        storageMonitor: StorageMonitor = StorageMonitor(),
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.smc = smc
        self.temperatureProvider = temperatureProvider
        self.smcHelper = smcHelper
        self.helperServiceManager = helperServiceManager ?? .shared
        self.fanControl = smcHelper
        self.cpuLoadMonitor = cpuLoadMonitor
        self.memoryMonitor = memoryMonitor
        self.storageMonitor = storageMonitor
        self.networkMonitor = networkMonitor
        detectPlatform()
        loadSettings()
    }

    deinit {
        monitorTimer?.invalidate()
        autoControlTimer?.invalidate()
    }

    private func detectPlatform() {
        // 检测 CPU 类型
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpuBrand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &size, nil, 0)
        let brand = String(cString: cpuBrand)

        isAppleSilicon = brand.isEmpty || brand.contains("Apple")

        // 获取型号
        size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)

        // 检测芯片代数
        // Mac13,x / Mac14,x = M1/M2
        // Mac15,x = M3
        // Mac16,x = M4
        // 未来可能有 Mac17,x = M5 等
        isM4 = modelString.hasPrefix("Mac16")

        // 检测芯片型号用于显示
        let chipName = detectChipName(model: modelString)
        platformInfo = isAppleSilicon ? "Apple Silicon \(chipName) (\(modelString))" : "Intel (\(brand))"

        // 所有 Apple Silicon Mac 都可以通过 SMC Helper daemon 控制风扇
        canControlFans = fanControl.isAvailable

        refreshHelperRegistrationState()
    }

    private func detectChipName(model: String) -> String {
        // 根据型号识别芯片
        // Mac13,x = M1 系列 (2020-2021)
        // Mac14,x = M1/M2 系列 (2021-2023)
        // Mac15,x = M3 系列 (2023-2024)
        // Mac16,x = M4 系列 (2024-)

        if model.hasPrefix("Mac16") {
            return "M4"
        } else if model.hasPrefix("Mac15") {
            return "M3"
        } else if model.hasPrefix("Mac14") {
            // Mac14 包含 M1 和 M2 机型，需要进一步判断
            // Mac14,2 = MacBook Air M2
            // Mac14,3 = Mac mini M2
            // Mac14,5/6 = MacBook Pro M2 Pro/Max
            // Mac14,7 = MacBook Pro M2
            // Mac14,9/10 = Mac Studio M2 Max/Ultra
            // Mac14,12 = Mac mini M2 Pro
            let modelNum = model.replacingOccurrences(of: "Mac14,", with: "")
            if let num = Int(modelNum) {
                if num >= 2 {
                    return "M2"
                }
            }
            return "M1/M2"
        } else if model.hasPrefix("Mac13") {
            return "M1"
        } else if model.hasPrefix("MacBookAir10") || model.hasPrefix("MacBookPro17") ||
                  model.hasPrefix("MacBookPro18") || model.hasPrefix("Macmini9") ||
                  model.hasPrefix("iMac21") || model.hasPrefix("MacStudio") {
            return "M1"
        }

        return ""
    }

    // MARK: - Helper Installation

    func installHelper() {
        guard !isInstallingHelper else { return }

        isInstallingHelper = true
        lastError = nil

        do {
            try helperServiceManager.register()
            refreshHelperRegistrationState()
            isInstallingHelper = false
            if helperRegistrationState == .enabled {
                retryHelperConnection()
            }
        } catch {
            isInstallingHelper = false
            refreshHelperRegistrationState()
            lastError = .helperInstallFailed(error.localizedDescription)
        }
    }

    func performHelperRegistrationAction() {
        refreshHelperRegistrationState()
        switch helperRegistrationState {
        case .notRegistered:
            installHelper()
        case .requiresApproval:
            helperServiceManager.openApprovalSettings()
        case .notFound:
            retryHelperConnection()
        case .enabled:
            break
        }
    }

    func refreshHelperRegistrationState() {
        helperRegistrationState = helperServiceManager.state
        if helperRegistrationState != .enabled {
            canControlFans = false
        }
    }

    func retryHelperConnection() {
        refreshHelperRegistrationState()
        guard helperRegistrationState == .enabled else { return }
        smcHelper.disconnect()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateFanInfo()
            await self.startAutoControlIfAvailable()
        }
    }

    func uninstallHelper() async {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        lastError = nil

        let legacyCleanupSucceeded = await smcHelper.removeLegacyHelper()
        do {
            try await helperServiceManager.unregister()
            smcHelper.disconnect()
            refreshHelperRegistrationState()
            canControlFans = false
            isAutoControlEnabled = false
            autoControlTimer?.invalidate()
            autoControlTimer = nil
            if !legacyCleanupSucceeded {
                lastError = .helperInstallFailed("新服务已卸载，但旧版服务清理失败")
            }
        } catch {
            refreshHelperRegistrationState()
            lastError = .helperInstallFailed(error.localizedDescription)
        }
        isInstallingHelper = false
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil

        updateTemperatures()
        Task { await updateFanInfo() }
        Task { await startAutoControlIfAvailable() }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTemperatures()
                await self?.updateFanInfo()
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        autoControlTimer?.invalidate()
        autoControlTimer = nil
        isMonitoring = false
    }

    private func updateFanInfo() async {
        // 防止并发调用堆积
        guard !isUpdatingFanInfo else { return }
        isUpdatingFanInfo = true

        let currentFans = fans
        let appleSilicon = isAppleSilicon
        defer { isUpdatingFanInfo = false }
        var newFans: [FanInfo] = []
        let fanData = await fanControl.getFanData()
        let controlAvailable = fanControl.isAvailable

        if !fanData.isEmpty {
            newFans = fanData.map { data in
                let existingFan = currentFans.first { $0.id == data.index }
                return FanInfo(
                    id: data.index,
                    currentSpeed: data.currentSpeed,
                    minSpeed: data.minSpeed,
                    maxSpeed: data.maxSpeed,
                    targetSpeed: existingFan?.targetSpeed,
                    isManualMode: data.mode == 1
                )
            }
            if canControlFans != controlAvailable { canControlFans = controlAvailable }
            if !fansEqual(fans, newFans) { fans = newFans }
            await startAutoControlIfAvailable()
            return
        }

        // 后备: 使用传统 SMC (Intel Mac)
        if !appleSilicon {
            do {
                try smc.open()
            } catch {
                if canControlFans != controlAvailable { canControlFans = controlAvailable }
                if !fans.isEmpty { fans = [] }
                return
            }

            let count = smc.getFanCount()

            for i in 0..<count {
                let current = smc.getFanSpeed(index: i) ?? 0
                let min = smc.getFanMinSpeed(index: i) ?? 0
                let max = smc.getFanMaxSpeed(index: i) ?? 6000

                let existingFan = currentFans.first { $0.id == i }

                newFans.append(FanInfo(
                    id: i,
                    currentSpeed: current,
                    minSpeed: min,
                    maxSpeed: max,
                    targetSpeed: existingFan?.targetSpeed,
                    isManualMode: existingFan?.isManualMode ?? false
                ))
            }
        }

        if canControlFans != controlAvailable { canControlFans = controlAvailable }
        if !fansEqual(fans, newFans) { fans = newFans }
        await startAutoControlIfAvailable()
    }

    /// Compare two fan arrays without triggering @Published
    private nonisolated func fansEqual(_ a: [FanInfo], _ b: [FanInfo]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if a[i].id != b[i].id || a[i].currentSpeed != b[i].currentSpeed ||
               a[i].isManualMode != b[i].isManualMode {
                return false
            }
        }
        return true
    }

    private func updateTemperatures() {
        // 防止并发调用堆积
        guard !isUpdatingTemperatures else { return }
        isUpdatingTemperatures = true

        // 更新 CPU 使用率 (仅在变化时赋值，避免触发不必要的 SwiftUI 重绘)
        if let usage = cpuLoadMonitor.getCPUUsage() {
            let newUsage = (usage.total * 10).rounded() / 10  // 保留1位小数
            if abs(newUsage - cpuUsage) >= 0.1 {
                cpuUsage = newUsage
            }
        }

        // 更新内存使用率
        if let memory = memoryMonitor.getMemoryUsage() {
            let newPct = (memory.percentage * 10).rounded() / 10
            if abs(newPct - memoryUsage) >= 0.1 { memoryUsage = newPct }
            if memoryUsed != memory.formattedUsed { memoryUsed = memory.formattedUsed }
            if memoryTotal != memory.formattedTotal { memoryTotal = memory.formattedTotal }
        }

        let newStorageUsage = storageMonitor.getStorageUsage()
        if storageUsage != newStorageUsage {
            storageUsage = newStorageUsage
        }

        let newNetworkSpeed = networkMonitor.getNetworkSpeed()
        if networkSpeed != newNetworkSpeed {
            networkSpeed = newNetworkSpeed
        }

        // 温度读取移到后台线程 (HID API 调用较重)
        let tempProvider = self.temperatureProvider
        let currentIsM4 = isM4
        let currentIsAppleSilicon = isAppleSilicon

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if currentIsM4 || currentIsAppleSilicon {
                let readings = tempProvider.getTemperatures()

                let newCpuTemp: Double?
                let newMaxTemp: Double?
                let newSSDTemp: Double?
                let newTemps: [TemperatureInfo]?
                let source: String
                let count: Int

                if !readings.isEmpty {
                    source = "HID 传感器"
                    count = readings.count
                    newTemps = readings.map { reading in
                        TemperatureInfo(id: reading.name, name: reading.name, value: reading.temperature)
                    }
                    newCpuTemp = Self.extractCPUTemperature(from: readings)
                    newMaxTemp = readings.map({ $0.temperature }).max()
                    newSSDTemp = readings.first(where: { $0.name == "NAND CH0 temp" })?.temperature
                } else if currentIsM4 {
                    source = "CPU 负载估算"
                    count = 0
                    newCpuTemp = nil
                    newMaxTemp = nil
                    newSSDTemp = nil
                    newTemps = nil
                } else {
                    // M1/M2/M3 fallback to SMC — handled on main thread
                    DispatchQueue.main.async {
                        self.fallbackToSMC()
                        self.isUpdatingTemperatures = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    if self.temperatureSource != source { self.temperatureSource = source }
                    if self.sensorCount != count { self.sensorCount = count }

                    if let temps = newTemps {
                        // 只在温度值实际变化时更新数组
                        if !self.tempsEqual(self.temperatures, temps) {
                            self.temperatures = temps
                        }
                    } else if currentIsM4 {
                        // CPU 负载估算 fallback
                        let estimated = self.cpuLoadMonitor.estimateTemperature()
                        if abs(estimated - self.cpuTemperature) >= 0.5 {
                            self.cpuTemperature = estimated
                            self.maxTemperature = estimated
                            self.temperatures = [
                                TemperatureInfo(id: "estimated", name: "CPU (估算)", value: estimated)
                            ]
                        }
                    }

                    if let cpu = newCpuTemp, abs(cpu - self.cpuTemperature) >= 0.5 {
                        self.cpuTemperature = cpu
                    }
                    if let maxT = newMaxTemp, abs(maxT - self.maxTemperature) >= 0.5 {
                        self.maxTemperature = maxT
                    }
                    if let ssd = newSSDTemp {
                        if self.ssdTemperature == nil || abs(ssd - self.ssdTemperature!) >= 0.5 {
                            self.ssdTemperature = ssd
                        }
                    } else if self.ssdTemperature != nil {
                        self.ssdTemperature = nil
                    }

                    // GPU 温度仅在 Intel Mac 上通过 SMC 可用
                    if !currentIsAppleSilicon {
                        self.gpuTemperature = self.smc.getGPUTemperature()
                    }

                    self.checkHighTemperatureNotification()
                    self.isUpdatingTemperatures = false
                }
            } else {
                // Intel: 使用 SMC (on main thread)
                DispatchQueue.main.async {
                    if self.temperatureSource != "SMC" { self.temperatureSource = "SMC" }
                    self.fallbackToSMC()
                    if !currentIsAppleSilicon {
                        self.gpuTemperature = self.smc.getGPUTemperature()
                    }
                    self.checkHighTemperatureNotification()
                    self.isUpdatingTemperatures = false
                }
            }
        }
    }

    /// Compare two temperature arrays without triggering @Published
    private func tempsEqual(_ a: [TemperatureInfo], _ b: [TemperatureInfo]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if a[i].id != b[i].id || abs(a[i].value - b[i].value) >= 0.5 {
                return false
            }
        }
        return true
    }

    /// Extract CPU temperature from readings without calling getTemperatures() again
    private nonisolated static func extractCPUTemperature(from readings: [TemperatureReading]) -> Double? {
        let cpuKeywords = ["tdie1", "tdie2", "tdie3", "PMU tdie", "PMU2 tdie"]
        for keyword in cpuKeywords {
            if let reading = readings.first(where: { $0.name.localizedCaseInsensitiveContains(keyword) }) {
                return reading.temperature
            }
        }
        let tdieReadings = readings.filter { $0.name.contains("tdie") }
        if !tdieReadings.isEmpty {
            return tdieReadings.map { $0.temperature }.reduce(0, +) / Double(tdieReadings.count)
        }
        return readings.map { $0.temperature }.max()
    }

    private func checkHighTemperatureNotification() {
        let enableNotification = UserDefaults.standard.bool(forKey: "enableHighTempNotification")
        guard enableNotification else { return }

        let threshold = UserDefaults.standard.double(forKey: "highTempThreshold")
        let effectiveThreshold = threshold > 0 ? threshold : 90.0

        if cpuTemperature >= effectiveThreshold {
            // 检查冷却时间 (5分钟)
            if let lastTime = lastHighTempNotificationTime,
               Date().timeIntervalSince(lastTime) < 300 {
                return
            }

            // 发送通知
            sendHighTempNotification()
            lastHighTempNotificationTime = Date()
        }
    }

    private func sendHighTempNotification() {
        let content = UNMutableNotificationContent()
        content.title = "温度警告"
        content.body = String(format: "CPU 温度已达到 %.1f°C，请注意散热！", cpuTemperature)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "highTemp-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func fallbackToSMC() {
        // SMC's legacy "SSD" label maps to TH0P, not the verified NAND sensor.
        ssdTemperature = nil

        do {
            try smc.open()
        } catch {
            lastError = .sensorAccessFailed
            return
        }

        if let temp = smc.getCPUTemperature() {
            cpuTemperature = temp
            maxTemperature = temp
        }

        gpuTemperature = smc.getGPUTemperature()

        let allSensors = smc.getAllTemperatureSensors()
        sensorCount = allSensors.count
        temperatures = allSensors.map { sensor in
            TemperatureInfo(id: sensor.key, name: sensor.name, value: sensor.value)
        }
    }

    // MARK: - Fan Control

    @discardableResult
    func setFanSpeed(fanIndex: Int, speed: Int) async -> Bool {
        guard canControlFans else {
            lastError = .helperNotInstalled
            return false
        }

        guard fanIndex < fans.count else { return false }

        let fan = fans[fanIndex]
        let clampedSpeed = max(fan.minSpeed, min(fan.maxSpeed, speed))

        // 使用 FanControlProvider
        if fanControl.isAvailable {
            if await fanControl.setFanSpeed(index: fan.id, rpm: clampedSpeed) {
                fans[fanIndex].targetSpeed = clampedSpeed
                fans[fanIndex].isManualMode = true
                lastError = nil
                return true
            } else {
                lastError = .fanControlFailed("Helper 通信失败")
                return false
            }
        }

        // 后备: 传统 SMC (Intel)
        do {
            try smc.setFanSpeed(index: fanIndex, speed: clampedSpeed)
            fans[fanIndex].targetSpeed = clampedSpeed
            fans[fanIndex].isManualMode = true
            lastError = nil
            return true
        } catch {
            lastError = .fanControlFailed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func setFanSpeedPercentage(fanIndex: Int, percentage: Double) async -> Bool {
        guard fanIndex < fans.count else { return false }

        let fan = fans[fanIndex]
        let range = fan.maxSpeed - fan.minSpeed
        let speed = fan.minSpeed + Int(Double(range) * percentage / 100.0)

        return await setFanSpeed(fanIndex: fanIndex, speed: speed)
    }

    func resetFanToAuto(fanIndex: Int) async {
        guard fanIndex < fans.count else { return }

        // 使用 FanControlProvider
        if fanControl.isAvailable {
            if await fanControl.resetFanToAuto(index: fans[fanIndex].id) {
                fans[fanIndex].targetSpeed = nil
                fans[fanIndex].isManualMode = false
                lastError = nil
            } else {
                lastError = .fanResetFailed
            }
            return
        }

        // 后备: 传统 SMC
        do {
            try smc.resetFanToAuto(index: fanIndex)
            fans[fanIndex].targetSpeed = nil
            fans[fanIndex].isManualMode = false
            lastError = nil
        } catch {
            lastError = .fanResetFailed
        }
    }

    func resetAllFansToAuto() async {
        if fanControl.isAvailable {
            if await fanControl.resetAllFansToAuto() {
                for index in fans.indices {
                    fans[index].targetSpeed = nil
                    fans[index].isManualMode = false
                }
                lastError = nil
            } else {
                lastError = .fanResetFailed
            }
        } else {
            for i in 0..<fans.count {
                await resetFanToAuto(fanIndex: i)
            }
        }
        isAutoControlEnabled = false
        activeProfile = nil
    }

    // MARK: - Profile Control

    func enableAutoControl(profile: FanProfile) {
        isAutoControlEnabled = true

        for i in 0..<profiles.count {
            profiles[i].isActive = profiles[i].id == profile.id
        }
        activeProfile = profiles.first { $0.id == profile.id } ?? profile
        lastError = nil
        saveSettings()

        guard canControlFans else {
            lastError = .fanControlUnavailable
            return
        }

        Task { await startAutoControlIfAvailable(restartTimer: true) }
    }

    private func startAutoControlIfAvailable(restartTimer: Bool = false) async {
        guard isAutoControlEnabled, activeProfile != nil else { return }

        guard canControlFans else {
            autoControlTimer?.invalidate()
            autoControlTimer = nil
            lastAutoTargetPercentage = -1
            return
        }

        if autoControlTimer == nil || restartTimer {
            autoControlTimer?.invalidate()
            autoControlTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isApplyingAutoControl else { return }
                    await self.applyAutoControl()
                }
            }
        }
        await applyAutoControl()
    }

    private func applyAutoControl() async {
        guard !isApplyingAutoControl else { return }
        guard isAutoControlEnabled,
              canControlFans,
              let profile = activeProfile,
              !fans.isEmpty else { return }
        guard autoControlApplyGate.begin() else { return }

        isApplyingAutoControl = true
        defer {
            isApplyingAutoControl = false
            autoControlApplyGate.end()
        }

        let targetPercentage = profile.targetSpeedPercentage(for: cpuTemperature)

        // 只在目标转速变化超过 1% 时才发送命令，避免频繁 XPC 通信
        guard abs(targetPercentage - lastAutoTargetPercentage) >= 1.0 else { return }

        var allSucceeded = true
        for i in 0..<fans.count {
            if !(await setFanSpeedPercentage(fanIndex: i, percentage: targetPercentage)) {
                allSucceeded = false
            }
        }

        if allSucceeded {
            lastAutoTargetPercentage = targetPercentage
        }
    }

    func disableAutoControl() async {
        isAutoControlEnabled = false
        activeProfile = nil
        lastAutoTargetPercentage = -1
        autoControlTimer?.invalidate()
        autoControlTimer = nil

        for i in 0..<profiles.count {
            profiles[i].isActive = false
        }

        await resetAllFansToAuto()
        saveSettings()
    }

    func saveCustomProfile(curve: [FanCurvePoint]) {
        let settings = FanControlSettings(
            profiles: profiles,
            activeProfileID: activeProfile?.id,
            isAutoControlEnabled: isAutoControlEnabled
        ).updatingCustomProfile(curve: curve)

        restore(settings)
        saveSettings()
        Task { await startAutoControlIfAvailable(restartTimer: true) }

        if !canControlFans {
            lastError = .fanControlUnavailable
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        do {
            guard let settings = try settingsStore.load() else { return }
            restore(settings)
        } catch {
            lastError = .settingsLoadFailed(error.localizedDescription)
        }
    }

    private func restore(_ settings: FanControlSettings) {
        let normalized = settings.normalized()
        profiles = normalized.profiles
        activeProfile = normalized.activeProfileID.flatMap { id in
            normalized.profiles.first { $0.id == id }
        }
        isAutoControlEnabled = normalized.isAutoControlEnabled && activeProfile != nil
    }

    private func saveSettings() {
        let settings = FanControlSettings(
            profiles: profiles,
            activeProfileID: activeProfile?.id,
            isAutoControlEnabled: isAutoControlEnabled
        ).normalized()

        do {
            try settingsStore.save(settings)
        } catch {
            lastError = .settingsSaveFailed(error.localizedDescription)
        }
    }
}
