// FanController.swift - Fan control logic and temperature monitoring
// 支持 Intel Mac 和 Apple Silicon (M1/M2/M3/M4)

import Foundation
import Combine
import IOKit
import UserNotifications

// MARK: - Data Models

/// Fan information
struct FanInfo: Identifiable, Equatable {
    let id: Int
    var currentSpeed: Int      // Current RPM
    var minSpeed: Int          // Minimum RPM
    var maxSpeed: Int          // Maximum RPM
    var targetSpeed: Int?      // User-set target (nil = auto)
    var isManualMode: Bool     // Manual or automatic

    var speedPercentage: Double {
        guard maxSpeed > minSpeed else { return 0 }
        return Double(currentSpeed - minSpeed) / Double(maxSpeed - minSpeed) * 100
    }

    static func == (lhs: FanInfo, rhs: FanInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.currentSpeed == rhs.currentSpeed &&
        lhs.minSpeed == rhs.minSpeed &&
        lhs.maxSpeed == rhs.maxSpeed &&
        lhs.targetSpeed == rhs.targetSpeed &&
        lhs.isManualMode == rhs.isManualMode
    }
}

/// Temperature sensor information
struct TemperatureInfo: Identifiable, Equatable {
    let id: String
    let name: String
    var value: Double

    var formattedValue: String {
        String(format: "%.1f°C", value)
    }

    /// 友好的中文名称
    var displayName: String {
        // M4 传感器名称映射
        let sensorMappings: [String: String] = [
            // PMU tdie - CPU 核心温度
            "PMU tdie1": "CPU 核心 1",
            "PMU tdie2": "CPU 核心 2",
            "PMU tdie3": "CPU 核心 3",
            "PMU tdie4": "CPU 核心 4",
            "PMU tdie5": "CPU 核心 5",
            "PMU tdie6": "CPU 核心 6",
            "PMU tdie7": "CPU 核心 7",
            "PMU tdie8": "CPU 核心 8",
            "PMU tdie9": "CPU 核心 9",
            "PMU tdie10": "CPU 核心 10",
            "PMU tdie11": "CPU 核心 11",
            "PMU tdie12": "CPU 核心 12",
            "PMU tdie13": "CPU 核心 13",
            "PMU tdie14": "CPU 核心 14",
            // PMU2 tdie - 效率核心温度
            "PMU2 tdie1": "效率核心 1",
            "PMU2 tdie2": "效率核心 2",
            "PMU2 tdie3": "效率核心 3",
            "PMU2 tdie4": "效率核心 4",
            "PMU2 tdie5": "效率核心 5",
            "PMU2 tdie6": "效率核心 6",
            "PMU2 tdie7": "效率核心 7",
            "PMU2 tdie8": "效率核心 8",
            "PMU2 tdie9": "效率核心 9",
            "PMU2 tdie10": "效率核心 10",
            // PMU tdev - 设备温度
            "PMU tdev1": "芯片区域 1",
            "PMU tdev2": "芯片区域 2",
            "PMU tdev3": "芯片区域 3",
            "PMU tdev4": "芯片区域 4",
            "PMU tdev5": "芯片区域 5",
            "PMU tdev6": "芯片区域 6",
            "PMU tdev7": "芯片区域 7",
            "PMU tdev8": "芯片区域 8",
            // PMU2 tdev
            "PMU2 tdev1": "效率芯片区域 1",
            "PMU2 tdev2": "效率芯片区域 2",
            "PMU2 tdev3": "效率芯片区域 3",
            "PMU2 tdev4": "效率芯片区域 4",
            "PMU2 tdev5": "效率芯片区域 5",
            // 校准温度
            "PMU tcal": "PMU 校准",
            "PMU2 tcal": "PMU2 校准",
            // 存储
            "NAND CH0 temp": "SSD 温度",
        ]

        if let mapped = sensorMappings[name] {
            return mapped
        }

        // 通用模式匹配
        if name.contains("tdie") {
            if name.contains("PMU2") {
                return name.replacingOccurrences(of: "PMU2 tdie", with: "效率核心 ")
            }
            return name.replacingOccurrences(of: "PMU tdie", with: "CPU 核心 ")
        }
        if name.contains("tdev") {
            if name.contains("PMU2") {
                return name.replacingOccurrences(of: "PMU2 tdev", with: "效率区域 ")
            }
            return name.replacingOccurrences(of: "PMU tdev", with: "芯片区域 ")
        }
        if name.contains("NAND") {
            return "SSD"
        }

        return name
    }

    var warningLevel: WarningLevel {
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
enum WarningLevel {
    case normal
    case warning
    case critical
}

/// Temperature-based fan curve point
struct FanCurvePoint: Codable, Equatable {
    var temperature: Double
    var fanSpeedPercentage: Double  // 0-100
}

/// Fan control profile
struct FanProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var curve: [FanCurvePoint]
    var isActive: Bool = false

    static let silent = FanProfile(
        name: "静音",
        curve: [
            FanCurvePoint(temperature: 40, fanSpeedPercentage: 20),
            FanCurvePoint(temperature: 60, fanSpeedPercentage: 35),
            FanCurvePoint(temperature: 75, fanSpeedPercentage: 50),
            FanCurvePoint(temperature: 85, fanSpeedPercentage: 75),
            FanCurvePoint(temperature: 95, fanSpeedPercentage: 100),
        ]
    )

    static let balanced = FanProfile(
        name: "平衡",
        curve: [
            FanCurvePoint(temperature: 40, fanSpeedPercentage: 30),
            FanCurvePoint(temperature: 55, fanSpeedPercentage: 45),
            FanCurvePoint(temperature: 70, fanSpeedPercentage: 65),
            FanCurvePoint(temperature: 80, fanSpeedPercentage: 85),
            FanCurvePoint(temperature: 90, fanSpeedPercentage: 100),
        ]
    )

    static let performance = FanProfile(
        name: "性能",
        curve: [
            FanCurvePoint(temperature: 35, fanSpeedPercentage: 40),
            FanCurvePoint(temperature: 50, fanSpeedPercentage: 60),
            FanCurvePoint(temperature: 65, fanSpeedPercentage: 80),
            FanCurvePoint(temperature: 75, fanSpeedPercentage: 95),
            FanCurvePoint(temperature: 85, fanSpeedPercentage: 100),
        ]
    )

    func targetSpeedPercentage(for temperature: Double) -> Double {
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

// MARK: - M4 Temperature Reader (使用 IOHIDEventSystemClient)

/// M4 Mac 温度传感器读取器
class M4TempReader {
    struct ThermalReading {
        let name: String
        let temperature: Double
    }

    // 私有 API 类型
    private typealias IOHIDEventSystemClientRef = UnsafeMutableRawPointer
    private typealias IOHIDServiceClientRef = UnsafeMutableRawPointer
    private typealias IOHIDEventRef = UnsafeMutableRawPointer

    // 函数指针
    private var createClient: (@convention(c) (CFAllocator?) -> IOHIDEventSystemClientRef?)?
    private var setMatching: (@convention(c) (IOHIDEventSystemClientRef, CFDictionary) -> Void)?
    private var copyServices: (@convention(c) (IOHIDEventSystemClientRef) -> CFArray?)?
    private var copyProperty: (@convention(c) (IOHIDServiceClientRef, CFString) -> CFTypeRef?)?
    private var copyEvent: (@convention(c) (IOHIDServiceClientRef, Int64, Int32, Int64) -> IOHIDEventRef?)?
    private var getFloatValue: (@convention(c) (IOHIDEventRef, UInt32) -> Double)?

    private var client: IOHIDEventSystemClientRef?
    private var isAvailable = false

    init() {
        loadSymbols()
        if isAvailable {
            setupClient()
        }
    }

    private func loadSymbols() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return
        }

        if let sym = dlsym(handle, "IOHIDEventSystemClientCreate") {
            createClient = unsafeBitCast(sym, to: (@convention(c) (CFAllocator?) -> IOHIDEventSystemClientRef?).self)
        }
        if let sym = dlsym(handle, "IOHIDEventSystemClientSetMatching") {
            setMatching = unsafeBitCast(sym, to: (@convention(c) (IOHIDEventSystemClientRef, CFDictionary) -> Void).self)
        }
        if let sym = dlsym(handle, "IOHIDEventSystemClientCopyServices") {
            copyServices = unsafeBitCast(sym, to: (@convention(c) (IOHIDEventSystemClientRef) -> CFArray?).self)
        }
        if let sym = dlsym(handle, "IOHIDServiceClientCopyProperty") {
            copyProperty = unsafeBitCast(sym, to: (@convention(c) (IOHIDServiceClientRef, CFString) -> CFTypeRef?).self)
        }
        if let sym = dlsym(handle, "IOHIDServiceClientCopyEvent") {
            copyEvent = unsafeBitCast(sym, to: (@convention(c) (IOHIDServiceClientRef, Int64, Int32, Int64) -> IOHIDEventRef?).self)
        }
        if let sym = dlsym(handle, "IOHIDEventGetFloatValue") {
            getFloatValue = unsafeBitCast(sym, to: (@convention(c) (IOHIDEventRef, UInt32) -> Double).self)
        }

        isAvailable = createClient != nil && copyServices != nil && copyEvent != nil && getFloatValue != nil
    }

    private func setupClient() {
        guard let create = createClient, let matching = setMatching else { return }

        client = create(kCFAllocatorDefault)
        guard let c = client else { return }

        // 匹配温度传感器
        let dict: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 5  // Temperature
        ]
        matching(c, dict as CFDictionary)
    }

    func getTemperatures() -> [ThermalReading] {
        guard isAvailable,
              let c = client,
              let services = copyServices?(c),
              let getProp = copyProperty,
              let getEvent = copyEvent,
              let getValue = getFloatValue else {
            return []
        }

        var readings: [ThermalReading] = []
        let kIOHIDEventTypeTemperature: Int64 = 15

        for i in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: IOHIDServiceClientRef.self)

            // 获取传感器名称
            var name = "Sensor \(i)"
            if let prop = getProp(service, "Product" as CFString) {
                if CFGetTypeID(prop) == CFStringGetTypeID() {
                    name = prop as! String
                }
            }

            // 获取温度事件
            if let event = getEvent(service, kIOHIDEventTypeTemperature, 0, 0) {
                // 温度字段: (type << 16) | 0 = 0xf0000
                let kIOHIDEventFieldTemperatureLevel: UInt32 = 0xf0000
                let temp = getValue(event, kIOHIDEventFieldTemperatureLevel)
                if temp > 0 && temp < 150 {
                    readings.append(ThermalReading(name: name, temperature: temp))
                }
            }
        }

        return readings
    }

    func getCPUTemperature() -> Double? {
        let readings = getTemperatures()

        // M4 优先查找 tdie 传感器 (芯片内部温度)
        let cpuKeywords = ["tdie1", "tdie2", "tdie3", "PMU tdie", "PMU2 tdie"]
        for keyword in cpuKeywords {
            if let reading = readings.first(where: { $0.name.localizedCaseInsensitiveContains(keyword) }) {
                return reading.temperature
            }
        }

        // 返回所有 tdie 传感器的平均值
        let tdieReadings = readings.filter { $0.name.contains("tdie") }
        if !tdieReadings.isEmpty {
            let avg = tdieReadings.map { $0.temperature }.reduce(0, +) / Double(tdieReadings.count)
            return avg
        }

        // 返回最高温度
        return readings.map { $0.temperature }.max()
    }

    func getMaxTemperature() -> Double? {
        return getTemperatures().map { $0.temperature }.max()
    }
}

// MARK: - CPU 负载监测

class CPULoadMonitor {
    struct CPUUsage {
        let user: Double
        let system: Double
        let idle: Double
        let total: Double
    }

    private var previousInfo: host_cpu_load_info?

    func getCPUUsage() -> CPUUsage? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        defer { previousInfo = info }

        guard let prev = previousInfo else {
            return CPUUsage(user: 0, system: 0, idle: 100, total: 0)
        }

        let userDiff = user - Double(prev.cpu_ticks.0)
        let systemDiff = system - Double(prev.cpu_ticks.1)
        let idleDiff = idle - Double(prev.cpu_ticks.2)
        let niceDiff = nice - Double(prev.cpu_ticks.3)

        let total = userDiff + systemDiff + idleDiff + niceDiff

        guard total > 0 else {
            return CPUUsage(user: 0, system: 0, idle: 100, total: 0)
        }

        return CPUUsage(
            user: (userDiff / total) * 100,
            system: (systemDiff / total) * 100,
            idle: (idleDiff / total) * 100,
            total: ((userDiff + systemDiff) / total) * 100
        )
    }

    func estimateTemperature() -> Double {
        guard let usage = getCPUUsage() else { return 45.0 }
        let baseTemp = 35.0
        let maxTemp = 85.0
        return baseTemp + (usage.total / 100.0) * (maxTemp - baseTemp)
    }
}

// MARK: - 内存监测

class MemoryMonitor {
    struct MemoryUsage {
        let used: UInt64      // 已使用内存 (bytes)
        let free: UInt64      // 空闲内存 (bytes)
        let total: UInt64     // 总内存 (bytes)
        let percentage: Double // 使用百分比

        var usedGB: Double {
            Double(used) / 1_073_741_824
        }

        var totalGB: Double {
            Double(total) / 1_073_741_824
        }

        var formattedUsed: String {
            String(format: "%.1f GB", usedGB)
        }

        var formattedTotal: String {
            String(format: "%.1f GB", totalGB)
        }
    }

    func getMemoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)

        // 获取总内存
        var totalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

        // 计算已使用内存
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let free = totalMemory - used

        let percentage = Double(used) / Double(totalMemory) * 100

        return MemoryUsage(
            used: used,
            free: free,
            total: totalMemory,
            percentage: percentage
        )
    }
}

// MARK: - SMC Helper (通过 Unix Socket 与 daemon 通信)

class SMCHelperClient {
    static let shared = SMCHelperClient()

    private let socketPath = "/var/run/com.macfancontrol.smchelper.sock"
    private let helperPath = "/Library/PrivilegedHelperTools/com.macfancontrol.smchelper"

    private init() {}

    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath) ||
        FileManager.default.fileExists(atPath: helperPath)
    }

    var isDaemonRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    struct FanData: Codable {
        let index: Int
        let currentSpeed: Double
        let minSpeed: Double
        let maxSpeed: Double
        let targetSpeed: Double
        let mode: Int
    }

    struct FanInfo: Codable {
        let fanCount: Int
        let fans: [FanData]
    }

    struct TempData: Codable {
        let key: String
        let name: String
        let value: Double
    }

    struct TempInfo: Codable {
        let temperatures: [TempData]
    }

    func getFanInfo() -> FanInfo? {
        guard let output = sendCommand("info") else { return nil }
        guard let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FanInfo.self, from: data)
    }

    func getTemperatures() -> TempInfo? {
        guard let output = sendCommand("temp") else { return nil }
        guard let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TempInfo.self, from: data)
    }

    func setFanSpeed(_ rpm: Int) -> Bool {
        guard let output = sendCommand("speed \(rpm)") else { return false }
        return output.contains("success")
    }

    func resetToAuto() -> Bool {
        guard let output = sendCommand("auto") else { return false }
        return output.contains("success")
    }

    /// 通过 Unix Socket 发送命令
    private func sendCommand(_ command: String) -> String? {
        // 首先尝试 socket 通信
        if isDaemonRunning {
            if let result = sendViaSocket(command) {
                return result
            }
        }
        return nil
    }

    private func sendViaSocket(_ command: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // 复制 socket 路径
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        // 连接
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else { return nil }

        // 发送命令
        let cmdData = command + "\n"
        _ = cmdData.withCString { cstr in
            write(fd, cstr, strlen(cstr))
        }

        // 读取响应
        var buffer = [CChar](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count - 1)
        guard bytesRead > 0 else { return nil }

        return String(cString: buffer)
    }

    // MARK: - 自动安装 Helper Daemon

    /// 检查并安装 Helper (如果需要)
    func installHelperIfNeeded(completion: @escaping (Bool, String?) -> Void) {
        if isDaemonRunning {
            completion(true, nil)
            return
        }

        // 获取 helper 源文件路径
        let bundle = Bundle.main
        guard let helperSource = bundle.path(forResource: "smc_helper", ofType: nil) ??
              findHelperInAppBundle() else {
            // 尝试从应用目录查找
            let appDir = bundle.bundlePath
            let possiblePaths = [
                (appDir as NSString).deletingLastPathComponent + "/smc_helper",
                FileManager.default.currentDirectoryPath + "/smc_helper",
                FileManager.default.currentDirectoryPath + "/.build/debug/smc_helper",
                "/tmp/smc_helper",
                "/Users/chen/MacFanControl/smc_helper"
            ]

            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    installHelper(from: path, completion: completion)
                    return
                }
            }

            completion(false, "找不到 smc_helper 文件")
            return
        }

        installHelper(from: helperSource, completion: completion)
    }

    private func findHelperInAppBundle() -> String? {
        let bundle = Bundle.main
        let appPath = bundle.bundlePath

        // 检查 Contents/Resources 目录 (标准位置)
        let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources/smc_helper")
        if FileManager.default.fileExists(atPath: resourcesPath) {
            return resourcesPath
        }

        // 检查 Contents/MacOS 目录
        let macosPath = (appPath as NSString).appendingPathComponent("Contents/MacOS/smc_helper")
        if FileManager.default.fileExists(atPath: macosPath) {
            return macosPath
        }

        // 检查 bundle.resourcePath
        if let resourceDir = bundle.resourcePath {
            let path = (resourceDir as NSString).appendingPathComponent("smc_helper")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func installHelper(from sourcePath: String, completion: @escaping (Bool, String?) -> Void) {
        // 构建 plist 内容
        let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.macfancontrol.smchelper</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/Library/PrivilegedHelperTools/com.macfancontrol.smchelper</string>
                    <string>daemon</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>StandardErrorPath</key>
                <string>/var/log/com.macfancontrol.smchelper.log</string>
            </dict>
            </plist>
            """

        // 将 plist 写入临时文件
        let tempPlistPath = "/tmp/com.macfancontrol.smchelper.plist"
        do {
            try plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)
        } catch {
            completion(false, "无法创建临时文件")
            return
        }

        let script = "do shell script \"launchctl unload /Library/LaunchDaemons/com.macfancontrol.smchelper.plist 2>/dev/null || true; mkdir -p /Library/PrivilegedHelperTools; cp '\(sourcePath)' /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; chown root:wheel /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; chmod 755 /Library/PrivilegedHelperTools/com.macfancontrol.smchelper; cp '\(tempPlistPath)' /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; chown root:wheel /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; chmod 644 /Library/LaunchDaemons/com.macfancontrol.smchelper.plist; launchctl load /Library/LaunchDaemons/com.macfancontrol.smchelper.plist\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                // 等待 daemon 启动
                Thread.sleep(forTimeInterval: 1.0)

                DispatchQueue.main.async {
                    if self.isDaemonRunning {
                        completion(true, nil)
                    } else if let err = error {
                        completion(false, err["NSAppleScriptErrorMessage"] as? String ?? "安装失败")
                    } else {
                        completion(false, "Daemon 启动失败")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, "无法创建安装脚本")
                }
            }
        }
    }
}
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
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: String = ""
    @Published var memoryTotal: String = ""
    @Published var isMonitoring = false
    @Published var lastError: String?
    @Published var activeProfile: FanProfile?
    @Published var isAutoControlEnabled = false
    @Published var canControlFans = false
    @Published var isAppleSilicon = true
    @Published var isM4 = false
    @Published var platformInfo: String = ""
    @Published var temperatureSource: String = "未知"
    @Published var sensorCount: Int = 0
    @Published var isInstallingHelper = false
    @Published var needsHelperInstall = false

    @Published var profiles: [FanProfile] = [.silent, .balanced, .performance]

    // Private
    private let smc = SMCManager.shared
    private let m4TempReader = M4TempReader()
    private let smcHelper = SMCHelperClient.shared
    private let cpuLoadMonitor = CPULoadMonitor()
    private let memoryMonitor = MemoryMonitor()
    private var monitorTimer: Timer?
    private var autoControlTimer: Timer?
    private let updateInterval: TimeInterval = 2.0
    private var lastHighTempNotificationTime: Date?

    private init() {
        detectPlatform()
        loadSettings()
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

        // 检测是否为 M4 (Mac16,x)
        isM4 = modelString.hasPrefix("Mac16")

        platformInfo = isAppleSilicon ? "Apple Silicon (\(modelString))" : "Intel (\(brand))"

        // M4 可以通过 SMC Helper daemon 控制风扇
        canControlFans = smcHelper.isDaemonRunning

        // 检查是否需要安装 helper
        needsHelperInstall = isM4 && !smcHelper.isDaemonRunning
    }

    // MARK: - Helper Installation

    func installHelper() {
        guard !isInstallingHelper else { return }

        isInstallingHelper = true
        lastError = nil

        smcHelper.installHelperIfNeeded { [weak self] success, error in
            Task { @MainActor in
                self?.isInstallingHelper = false
                if success {
                    self?.canControlFans = true
                    self?.needsHelperInstall = false
                    self?.lastError = nil
                    // 重新获取风扇信息
                    self?.updateFanInfo()
                } else {
                    self?.lastError = error ?? "安装失败"
                }
            }
        }
    }

    func checkAndInstallHelper() {
        if isM4 && !smcHelper.isDaemonRunning {
            installHelper()
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastError = nil

        updateTemperatures()
        updateFanInfo()

        monitorTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTemperatures()
                self?.updateFanInfo()
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

    private func updateFanInfo() {
        // 更新 canControlFans 状态
        canControlFans = smcHelper.isDaemonRunning

        // 尝试使用 SMC Helper daemon (支持 M4)
        if smcHelper.isDaemonRunning {
            if let fanInfo = smcHelper.getFanInfo() {
                var newFans: [FanInfo] = []
                for fanData in fanInfo.fans {
                    let existingFan = fans.first { $0.id == fanData.index }
                    let fan = FanInfo(
                        id: fanData.index,
                        currentSpeed: Int(fanData.currentSpeed),
                        minSpeed: Int(fanData.minSpeed),
                        maxSpeed: Int(fanData.maxSpeed),
                        targetSpeed: existingFan?.targetSpeed,
                        isManualMode: fanData.mode == 1
                    )
                    newFans.append(fan)
                }
                fans = newFans
                return
            }
        }

        // 后备: 使用传统 SMC (Intel Mac)
        if !isAppleSilicon {
            do {
                try smc.open()
            } catch {
                fans = []
                return
            }

            let count = smc.getFanCount()
            var newFans: [FanInfo] = []

            for i in 0..<count {
                let current = smc.getFanSpeed(index: i) ?? 0
                let min = smc.getFanMinSpeed(index: i) ?? 0
                let max = smc.getFanMaxSpeed(index: i) ?? 6000

                let existingFan = fans.first { $0.id == i }

                let fan = FanInfo(
                    id: i,
                    currentSpeed: current,
                    minSpeed: min,
                    maxSpeed: max,
                    targetSpeed: existingFan?.targetSpeed,
                    isManualMode: existingFan?.isManualMode ?? false
                )
                newFans.append(fan)
            }

            fans = newFans
        } else {
            // Apple Silicon 没有 Helper 时显示空
            fans = []
        }
    }

    private func updateTemperatures() {
        // 更新 CPU 使用率
        if let usage = cpuLoadMonitor.getCPUUsage() {
            cpuUsage = usage.total
        }

        // 更新内存使用率
        if let memory = memoryMonitor.getMemoryUsage() {
            memoryUsage = memory.percentage
            memoryUsed = memory.formattedUsed
            memoryTotal = memory.formattedTotal
        }

        if isM4 {
            // M4: 使用 HID 传感器
            let readings = m4TempReader.getTemperatures()

            if !readings.isEmpty {
                temperatureSource = "HID 传感器"
                sensorCount = readings.count

                // 转换为 TemperatureInfo
                temperatures = readings.map { reading in
                    TemperatureInfo(id: reading.name, name: reading.name, value: reading.temperature)
                }

                // 获取 CPU 温度 (tdie 传感器平均值)
                if let cpuTemp = m4TempReader.getCPUTemperature() {
                    cpuTemperature = cpuTemp
                }

                // 获取最高温度
                if let maxTemp = m4TempReader.getMaxTemperature() {
                    maxTemperature = maxTemp
                }
            } else {
                // 后备: CPU 负载估算
                temperatureSource = "CPU 负载估算"
                sensorCount = 0
                cpuTemperature = cpuLoadMonitor.estimateTemperature()
                maxTemperature = cpuTemperature
                temperatures = [
                    TemperatureInfo(id: "estimated", name: "CPU (估算)", value: cpuTemperature)
                ]
            }
        } else if isAppleSilicon {
            // M1/M2/M3: 尝试 HID，然后 SMC
            let readings = m4TempReader.getTemperatures()

            if !readings.isEmpty {
                temperatureSource = "HID 传感器"
                sensorCount = readings.count
                temperatures = readings.map { reading in
                    TemperatureInfo(id: reading.name, name: reading.name, value: reading.temperature)
                }
                if let cpuTemp = m4TempReader.getCPUTemperature() {
                    cpuTemperature = cpuTemp
                }
                if let maxTemp = m4TempReader.getMaxTemperature() {
                    maxTemperature = maxTemp
                }
            } else {
                fallbackToSMC()
            }
        } else {
            // Intel: 使用 SMC
            temperatureSource = "SMC"
            fallbackToSMC()
        }

        gpuTemperature = smc.getGPUTemperature()

        // 检查高温通知
        checkHighTemperatureNotification()
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
        do {
            try smc.open()
        } catch {
            lastError = "无法访问传感器"
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
            TemperatureInfo(id: sensor.key, name: sensor.key, value: sensor.value)
        }
    }

    // MARK: - Fan Control

    func setFanSpeed(fanIndex: Int, speed: Int) {
        guard canControlFans else {
            lastError = "请先安装 SMC Helper"
            return
        }

        guard fanIndex < fans.count else { return }

        let fan = fans[fanIndex]
        let clampedSpeed = max(fan.minSpeed, min(fan.maxSpeed, speed))

        // 使用 SMC Helper
        if smcHelper.isHelperInstalled {
            if smcHelper.setFanSpeed(clampedSpeed) {
                fans[fanIndex].targetSpeed = clampedSpeed
                fans[fanIndex].isManualMode = true
                lastError = nil
            } else {
                lastError = "无法设置风扇速度"
            }
            return
        }

        // 后备: 传统 SMC (Intel)
        do {
            try smc.setFanSpeed(index: fanIndex, speed: clampedSpeed)
            fans[fanIndex].targetSpeed = clampedSpeed
            fans[fanIndex].isManualMode = true
            lastError = nil
        } catch {
            lastError = "无法设置风扇速度: \(error.localizedDescription)"
        }
    }

    func setFanSpeedPercentage(fanIndex: Int, percentage: Double) {
        guard fanIndex < fans.count else { return }

        let fan = fans[fanIndex]
        let range = fan.maxSpeed - fan.minSpeed
        let speed = fan.minSpeed + Int(Double(range) * percentage / 100.0)

        setFanSpeed(fanIndex: fanIndex, speed: speed)
    }

    func resetFanToAuto(fanIndex: Int) {
        guard fanIndex < fans.count else { return }

        // 使用 SMC Helper
        if smcHelper.isHelperInstalled {
            if smcHelper.resetToAuto() {
                fans[fanIndex].targetSpeed = nil
                fans[fanIndex].isManualMode = false
                lastError = nil
            } else {
                lastError = "无法重置风扇"
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
            lastError = "无法重置风扇"
        }
    }

    func resetAllFansToAuto() {
        for i in 0..<fans.count {
            resetFanToAuto(fanIndex: i)
        }
        isAutoControlEnabled = false
        activeProfile = nil
    }

    // MARK: - Profile Control

    func enableAutoControl(profile: FanProfile) {
        guard canControlFans else {
            lastError = "此 Mac 无法手动控制风扇"
            return
        }

        activeProfile = profile
        isAutoControlEnabled = true

        for i in 0..<profiles.count {
            profiles[i].isActive = profiles[i].id == profile.id
        }

        autoControlTimer?.invalidate()
        autoControlTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyAutoControl()
            }
        }

        applyAutoControl()
        saveSettings()
    }

    private func applyAutoControl() {
        guard isAutoControlEnabled, let profile = activeProfile else { return }

        let targetPercentage = profile.targetSpeedPercentage(for: cpuTemperature)

        for i in 0..<fans.count {
            setFanSpeedPercentage(fanIndex: i, percentage: targetPercentage)
        }
    }

    func disableAutoControl() {
        isAutoControlEnabled = false
        activeProfile = nil
        autoControlTimer?.invalidate()
        autoControlTimer = nil

        for i in 0..<profiles.count {
            profiles[i].isActive = false
        }

        resetAllFansToAuto()
        saveSettings()
    }

    // MARK: - Settings

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "fanProfiles"),
           let savedProfiles = try? JSONDecoder().decode([FanProfile].self, from: data) {
            profiles = savedProfiles
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "fanProfiles")
        }
    }
}
