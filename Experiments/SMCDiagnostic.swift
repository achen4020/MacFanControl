// SMCDiagnostic.swift - 诊断 SMC 可用的传感器
// 运行: swift SMCDiagnostic.swift

import Foundation
import IOKit

// MARK: - SMC 基础结构

struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0,0,0,0,0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0,0,0,0,0)
    var keyInfo: (UInt32, UInt32, UInt8) = (0,0,0)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

class SMCDiagnostic {
    var connection: io_connect_t = 0

    func open() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            print("❌ 无法找到 AppleSMC 服务")
            return false
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        if result != kIOReturnSuccess {
            print("❌ 无法连接到 SMC (错误码: \(result))")
            return false
        }

        print("✅ 成功连接到 SMC")
        return true
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readKey(_ key: String) -> (success: Bool, bytes: [UInt8], size: Int) {
        var input = SMCKeyData()
        var output = SMCKeyData()

        // 转换键名
        input.key = stringToKey(key)
        input.data8 = 9  // kSMCGetKeyInfo

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        var result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess else { return (false, [], 0) }

        input.keyInfo.0 = output.keyInfo.0
        input.data8 = 5  // kSMCReadKey

        result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess && output.result == 0 else { return (false, [], 0) }

        let size = Int(output.keyInfo.0)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: output.bytes) { ptr in
            for i in 0..<min(size, 32) {
                bytes.append(ptr[i])
            }
        }

        return (true, bytes, size)
    }

    func stringToKey(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = result << 8 | UInt32(char)
        }
        return result
    }

    func bytesToTemperature(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let value = Int16(bytes[0]) << 8 | Int16(bytes[1])
        return Double(value) / 256.0
    }

    func bytesToFanSpeed(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 2 else { return nil }
        let value = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Int(value >> 2)
    }

    func bytesToInt(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        return Int(bytes[0])
    }
}

// MARK: - 主程序

print("=" * 60)
print("Mac SMC 传感器诊断工具")
print("=" * 60)
print("")

let smc = SMCDiagnostic()

guard smc.open() else {
    print("无法打开 SMC 连接，请确保在真实 Mac 上运行")
    exit(1)
}

defer { smc.close() }

// 温度传感器键列表 (包括 Intel 和 Apple Silicon)
let temperatureKeys: [(name: String, key: String)] = [
    // Intel Mac 常用
    ("CPU Die", "TC0D"),
    ("CPU Proximity", "TC0P"),
    ("CPU Core 0", "TC0C"),
    ("CPU Core 1", "TC1C"),
    ("CPU Core 2", "TC2C"),
    ("CPU Core 3", "TC3C"),
    ("GPU Die", "TG0D"),
    ("GPU Proximity", "TG0P"),
    ("Memory", "Tm0P"),
    ("Battery", "TB0T"),
    ("SSD", "TH0P"),

    // Apple Silicon 常用
    ("CPU P-Cluster 1", "Tp01"),
    ("CPU P-Cluster 2", "Tp05"),
    ("CPU P-Cluster 3", "Tp09"),
    ("CPU P-Cluster 4", "Tp0D"),
    ("CPU E-Cluster 1", "Tp02"),
    ("CPU E-Cluster 2", "Tp06"),
    ("GPU 1", "Tg05"),
    ("GPU 2", "Tg0D"),
    ("GPU 3", "Tg0L"),
    ("GPU 4", "Tg0T"),
    ("ANE", "Tp0X"),
    ("DRAM", "Tm02"),
    ("SSD Controller", "TH0a"),
    ("Thunderbolt", "TI0p"),

    // 更多 Apple Silicon M3/M4 键
    ("PMU tdie1", "Tp1h"),
    ("PMU tdie2", "Tp1t"),
    ("PMU tdie3", "Tp1p"),
    ("PMU tdie4", "Tp1l"),
    ("SOC MTR Temp", "Ts0P"),
    ("SOC PMGR", "Ts0S"),
    ("Charger Proximity", "TC0c"),
    ("Airflow 0", "TA0P"),
    ("Airflow 1", "TA1P"),
    ("Heatpipe 0", "Th0H"),
    ("Heatpipe 1", "Th1H"),
]

print("🌡️  温度传感器扫描:")
print("-" * 50)

var foundTemps: [(name: String, key: String, temp: Double)] = []

for (name, key) in temperatureKeys {
    let result = smc.readKey(key)
    if result.success {
        if let temp = smc.bytesToTemperature(result.bytes), temp > 0 && temp < 150 {
            foundTemps.append((name, key, temp))
            print("✅ \(key): \(name) = \(String(format: "%.1f", temp))°C")
        }
    }
}

if foundTemps.isEmpty {
    print("⚠️  未找到标准温度传感器，尝试扫描更多键...")

    // 扫描更多可能的键
    let prefixes = ["T", "t"]
    let suffixes = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
    let types = ["P", "D", "H", "C", "S", "p", "h", "c", "s"]

    for prefix in prefixes {
        for char in ["c", "p", "g", "m", "s", "a", "b", "i", "n", "h"] {
            for suffix in suffixes {
                for type in types {
                    let key = "\(prefix)\(char)\(suffix)\(type)"
                    let result = smc.readKey(key)
                    if result.success {
                        if let temp = smc.bytesToTemperature(result.bytes), temp > 10 && temp < 120 {
                            foundTemps.append(("Unknown", key, temp))
                            print("✅ \(key): \(String(format: "%.1f", temp))°C")
                        }
                    }
                }
            }
        }
    }
}

print("")
print("💨 风扇传感器扫描:")
print("-" * 50)

// 检查风扇数量
let fanNumResult = smc.readKey("FNum")
let fanCount: Int
if fanNumResult.success {
    fanCount = smc.bytesToInt(fanNumResult.bytes)
    print("✅ FNum: 检测到 \(fanCount) 个风扇")
} else {
    print("⚠️  FNum 键不可用，尝试直接扫描风扇...")
    fanCount = 0
}

// 扫描风扇
var foundFans = 0
for i in 0..<8 {
    let actualKey = "F\(i)Ac"
    let result = smc.readKey(actualKey)
    if result.success {
        if let speed = smc.bytesToFanSpeed(result.bytes) {
            foundFans += 1
            print("✅ \(actualKey): 风扇 \(i) 转速 = \(speed) RPM")

            // 获取最小/最大值
            let minResult = smc.readKey("F\(i)Mn")
            let maxResult = smc.readKey("F\(i)Mx")
            if minResult.success, let minSpeed = smc.bytesToFanSpeed(minResult.bytes) {
                print("   F\(i)Mn: 最小 = \(minSpeed) RPM")
            }
            if maxResult.success, let maxSpeed = smc.bytesToFanSpeed(maxResult.bytes) {
                print("   F\(i)Mx: 最大 = \(maxSpeed) RPM")
            }
        }
    }
}

if foundFans == 0 {
    print("⚠️  未找到标准风扇键，可能此 Mac 使用不同的键名")
}

print("")
print("=" * 60)
print("诊断总结")
print("=" * 60)
print("")
print("🌡️  找到 \(foundTemps.count) 个温度传感器")
print("💨 找到 \(foundFans) 个风扇")
print("")

if !foundTemps.isEmpty {
    print("建议使用的温度键:")
    for (name, key, temp) in foundTemps.prefix(5) {
        print("  - \(key) (\(name)): \(String(format: "%.1f", temp))°C")
    }
}

print("")
print("请将以上结果反馈，我会根据你的 Mac 型号调整代码。")

// 辅助函数
func *(str: String, count: Int) -> String {
    return String(repeating: str, count: count)
}
