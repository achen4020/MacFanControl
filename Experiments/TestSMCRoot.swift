#!/usr/bin/env swift

// 这个脚本需要以 root 权限运行: sudo swift TestSMCRoot.swift

import Foundation
import IOKit

// SMC 结构体 - 必须与内核驱动匹配
struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo: (UInt32, UInt32, UInt8) = (0, 0, 0)  // dataSize, dataType, dataAttributes
    var padding: UInt8 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

let kSMCGetKeyInfo: UInt8 = 9
let kSMCReadKey: UInt8 = 5
let kSMCWriteKey: UInt8 = 6
let kSMCGetKeyFromIndex: UInt8 = 8

func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

func stringFromFourCharCode(_ code: UInt32) -> String {
    var chars: [Character] = []
    for shift in [24, 16, 8, 0] {
        let byte = (code >> shift) & 0xFF
        if byte >= 32 && byte < 127 {
            chars.append(Character(UnicodeScalar(byte)!))
        } else {
            chars.append("?")
        }
    }
    return String(chars)
}

print("SMC Root Test")
print("=============")
print("Running as UID: \(getuid())")

if getuid() != 0 {
    print("WARNING: Not running as root. SMC access may fail.")
    print("Run with: sudo swift TestSMCRoot.swift")
}

// 打开 AppleSMC 服务
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))

guard service != 0 else {
    print("ERROR: AppleSMC service not found")
    exit(1)
}

var conn: io_connect_t = 0
let openResult = IOServiceOpen(service, mach_task_self_, 0, &conn)
IOObjectRelease(service)

guard openResult == kIOReturnSuccess else {
    print("ERROR: Failed to open AppleSMC: \(String(format: "0x%x", openResult))")
    exit(1)
}

print("SMC connection opened: \(conn)")

func readSMCKey(_ key: String) -> (success: Bool, data: [UInt8], type: String, error: String) {
    var input = SMCKeyData()
    var output = SMCKeyData()
    var outputSize = MemoryLayout<SMCKeyData>.size

    // 获取 key info
    input.key = fourCharCode(key)
    input.data8 = kSMCGetKeyInfo

    let result1 = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    if result1 != kIOReturnSuccess {
        return (false, [], "", "GetKeyInfo failed: \(String(format: "0x%x", result1))")
    }

    let dataSize = output.keyInfo.0
    let dataType = stringFromFourCharCode(output.keyInfo.1)

    if dataSize == 0 {
        return (false, [], dataType, "dataSize is 0")
    }

    // 读取 key 值
    input.keyInfo.0 = dataSize
    input.data8 = kSMCReadKey

    let result2 = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    if result2 != kIOReturnSuccess {
        return (false, [], dataType, "ReadKey failed: \(String(format: "0x%x", result2))")
    }

    var data: [UInt8] = []
    withUnsafeBytes(of: output.bytes) { ptr in
        for i in 0..<Int(dataSize) {
            data.append(ptr[i])
        }
    }

    return (true, data, dataType, "")
}

// 测试风扇相关的 key
print("\n--- Fan Keys ---")
let fanKeys = ["FNum", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "F1Ac", "F1Mn", "F1Mx", "FS! ", "Ftst"]

for key in fanKeys {
    let (success, data, type, error) = readSMCKey(key)
    if success {
        var valueStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")

        // 解码常见类型
        if type == "ui8 " && data.count >= 1 {
            valueStr += " -> \(data[0])"
        } else if type == "ui16" && data.count >= 2 {
            let value = (UInt16(data[0]) << 8) | UInt16(data[1])
            valueStr += " -> \(value)"
        } else if type == "fpe2" && data.count >= 2 {
            let raw = (UInt16(data[0]) << 8) | UInt16(data[1])
            let rpm = Double(raw) / 4.0
            valueStr += " -> \(rpm) RPM"
        } else if type == "flt " && data.count >= 4 {
            let bits = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
            let value = Float(bitPattern: bits)
            valueStr += " -> \(value)"
        }

        print("  \(key) [\(type)]: \(valueStr)")
    } else {
        print("  \(key): FAILED - \(error)")
    }
}

// 测试温度相关的 key
print("\n--- Temperature Keys ---")
let tempKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TCGC", "TCSA", "TCXC", "TG0P", "Tp01"]

for key in tempKeys {
    let (success, data, type, error) = readSMCKey(key)
    if success {
        var valueStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")

        if (type == "sp78" || type == "flt ") && data.count >= 2 {
            // sp78 是 signed 7.8 fixed point
            let raw = (Int16(data[0]) << 8) | Int16(data[1])
            let temp = Double(raw) / 256.0
            valueStr += " -> \(String(format: "%.1f", temp))°C"
        }

        print("  \(key) [\(type)]: \(valueStr)")
    } else {
        print("  \(key): FAILED - \(error)")
    }
}

// 枚举一些 key
print("\n--- Enumerating Keys (first 50) ---")
var foundFanKeys: [String] = []
var foundTempKeys: [String] = []

for i: UInt32 in 0..<50 {
    var input = SMCKeyData()
    var output = SMCKeyData()
    var outputSize = MemoryLayout<SMCKeyData>.size

    input.data8 = kSMCGetKeyFromIndex
    input.data32 = i

    let result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    if result == kIOReturnSuccess && output.key != 0 {
        let keyName = stringFromFourCharCode(output.key)
        if keyName.hasPrefix("F") {
            foundFanKeys.append(keyName)
        } else if keyName.hasPrefix("T") {
            foundTempKeys.append(keyName)
        }
    }
}

print("Fan keys found: \(foundFanKeys)")
print("Temp keys found: \(foundTempKeys)")

IOServiceClose(conn)
print("\nDone")
