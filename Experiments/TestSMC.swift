// TestSMC.swift - 测试 SMC 访问
// 运行: swift TestSMC.swift

import Foundation
import IOKit

print("=== M4 Mac SMC 测试 ===")
print("")

// SMC 数据结构
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

func stringToKey(_ str: String) -> UInt32 {
    var result: UInt32 = 0
    for char in str.utf8.prefix(4) {
        result = result << 8 | UInt32(char)
    }
    // 补齐空格
    for _ in str.utf8.count..<4 {
        result = result << 8 | UInt32(0x20)
    }
    return result
}

// 连接 SMC
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
if service == 0 {
    print("❌ 无法找到 AppleSMC 服务")
    exit(1)
}

var connection: io_connect_t = 0
let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
IOObjectRelease(service)

if openResult != kIOReturnSuccess {
    print("❌ 无法连接到 SMC (错误: \(openResult))")
    exit(1)
}

print("✅ 成功连接到 SMC")
print("")

// 读取 SMC 键
func readKey(_ key: String) -> (success: Bool, bytes: [UInt8], size: Int, result: UInt8) {
    var input = SMCKeyData()
    var output = SMCKeyData()

    input.key = stringToKey(key)
    input.data8 = 9  // kSMCGetKeyInfo

    let inputSize = MemoryLayout<SMCKeyData>.size
    var outputSize = MemoryLayout<SMCKeyData>.size

    var result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    if result != kIOReturnSuccess {
        return (false, [], 0, output.result)
    }

    input.keyInfo.0 = output.keyInfo.0
    input.data8 = 5  // kSMCReadKey

    result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    if result != kIOReturnSuccess {
        return (false, [], 0, output.result)
    }

    let size = Int(output.keyInfo.0)
    var bytes: [UInt8] = []
    withUnsafeBytes(of: output.bytes) { ptr in
        for i in 0..<min(size, 32) {
            bytes.append(ptr[i])
        }
    }

    return (output.result == 0, bytes, size, output.result)
}

// 写入 SMC 键
func writeKey(_ key: String, bytes: [UInt8]) -> (success: Bool, result: UInt8) {
    var input = SMCKeyData()
    var output = SMCKeyData()

    input.key = stringToKey(key)
    input.data8 = 9  // kSMCGetKeyInfo

    let inputSize = MemoryLayout<SMCKeyData>.size
    var outputSize = MemoryLayout<SMCKeyData>.size

    var result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    if result != kIOReturnSuccess {
        return (false, output.result)
    }

    input.keyInfo.0 = output.keyInfo.0
    input.data8 = 6  // kSMCWriteKey

    // 设置数据
    withUnsafeMutableBytes(of: &input.bytes) { ptr in
        for i in 0..<min(bytes.count, 32) {
            ptr[i] = bytes[i]
        }
    }

    result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    return (result == kIOReturnSuccess && output.result == 0, output.result)
}

// 测试风扇相关键
print("📊 测试风扇相关 SMC 键:")
print("-" * 50)

let fanKeys = ["FNum", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "FS! ", "Ftst"]

for key in fanKeys {
    let result = readKey(key)
    if result.success {
        let hexBytes = result.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("✅ \(key): [\(hexBytes)] (size: \(result.size))")

        // 解析特定键
        if key == "FNum" && result.size >= 1 {
            print("   → 风扇数量: \(result.bytes[0])")
        }
        if (key == "F0Ac" || key == "F0Mn" || key == "F0Mx" || key == "F0Tg") && result.size >= 2 {
            let fpe2 = UInt16(result.bytes[0]) << 8 | UInt16(result.bytes[1])
            let rpm = Int(fpe2 >> 2)
            print("   → 转速: \(rpm) RPM")
        }
        if key == "F0Md" && result.size >= 1 {
            print("   → 模式: \(result.bytes[0] == 0 ? "自动" : "手动")")
        }
    } else {
        print("❌ \(key): 读取失败 (result: \(result.result))")
    }
}

print("")
print("📊 测试温度相关 SMC 键:")
print("-" * 50)

let tempKeys = ["TC0D", "TC0P", "TC0C", "Tp01", "Tp05", "TG0D", "Tm0P"]

for key in tempKeys {
    let result = readKey(key)
    if result.success && result.size >= 2 {
        let value = Int16(result.bytes[0]) << 8 | Int16(result.bytes[1])
        let temp = Double(value) / 256.0
        if temp > 0 && temp < 150 {
            print("✅ \(key): \(String(format: "%.1f", temp))°C")
        } else {
            let hexBytes = result.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("⚠️ \(key): [\(hexBytes)] (无效温度)")
        }
    } else {
        print("❌ \(key): 读取失败")
    }
}

print("")
print("📊 尝试写入 Ftst 键 (解锁风扇控制):")
print("-" * 50)

let writeResult = writeKey("Ftst", bytes: [1])
if writeResult.success {
    print("✅ Ftst = 1 写入成功!")

    // 验证
    let verifyResult = readKey("Ftst")
    if verifyResult.success {
        print("   验证: Ftst = \(verifyResult.bytes[0])")
    }

    // 尝试设置风扇模式
    print("")
    print("📊 尝试设置风扇手动模式:")
    let modeResult = writeKey("F0Md", bytes: [1])
    if modeResult.success {
        print("✅ F0Md = 1 写入成功!")
    } else {
        print("❌ F0Md 写入失败 (result: \(modeResult.result))")
    }

    // 恢复自动模式
    _ = writeKey("F0Md", bytes: [0])
    _ = writeKey("Ftst", bytes: [0])

} else {
    print("❌ Ftst 写入失败 (result: \(writeResult.result))")
    print("   这可能是 M4 固件限制")
}

IOServiceClose(connection)

print("")
print("=== 测试完成 ===")

// 辅助函数
func *(str: String, count: Int) -> String {
    return String(repeating: str, count: count)
}
