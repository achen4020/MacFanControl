#!/usr/bin/env swift

import Foundation
import IOKit

// SMC structures
struct SMCKeyData {
    struct vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct pLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers()
    var pLimitData = pLimitData()
    var keyInfo = keyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

let kSMCHandleYieldToEmbeddedOS: UInt8 = 3
let kSMCReadKey: UInt8 = 5
let kSMCWriteKey: UInt8 = 6
let kSMCGetKeyFromIndex: UInt8 = 8
let kSMCGetKeyInfo: UInt8 = 9

func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

func stringFromFourCharCode(_ code: UInt32) -> String {
    var chars: [Character] = []
    chars.append(Character(UnicodeScalar((code >> 24) & 0xFF)!))
    chars.append(Character(UnicodeScalar((code >> 16) & 0xFF)!))
    chars.append(Character(UnicodeScalar((code >> 8) & 0xFF)!))
    chars.append(Character(UnicodeScalar(code & 0xFF)!))
    return String(chars)
}

print("SMC Fan Key Test")
print("================")

// Open SMC
var conn: io_connect_t = 0
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))

guard service != 0 else {
    print("ERROR: AppleSMC service not found")
    exit(1)
}

let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
IOObjectRelease(service)

guard result == kIOReturnSuccess else {
    print("ERROR: Failed to open AppleSMC: \(String(format: "0x%x", result))")
    exit(1)
}

print("SMC connection opened successfully")

func readSMCKey(_ key: String) -> (success: Bool, data: [UInt8], type: String) {
    var input = SMCKeyData()
    var output = SMCKeyData()

    input.key = fourCharCode(key)
    input.data8 = kSMCGetKeyInfo

    var outputSize = MemoryLayout<SMCKeyData>.size

    let result1 = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    guard result1 == kIOReturnSuccess else {
        return (false, [], "")
    }

    let dataSize = output.keyInfo.dataSize
    let dataType = stringFromFourCharCode(output.keyInfo.dataType)

    input.keyInfo.dataSize = dataSize
    input.data8 = kSMCReadKey

    let result2 = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    guard result2 == kIOReturnSuccess else {
        return (false, [], dataType)
    }

    var data: [UInt8] = []
    withUnsafeBytes(of: output.bytes) { ptr in
        for i in 0..<Int(dataSize) {
            data.append(ptr[i])
        }
    }

    return (true, data, dataType)
}

// Fan keys to try
let fanKeys = [
    "FNum",  // Number of fans
    "F0Ac",  // Fan 0 actual speed
    "F0Mn",  // Fan 0 minimum speed
    "F0Mx",  // Fan 0 maximum speed
    "F0Tg",  // Fan 0 target speed
    "F0Sf",  // Fan 0 safe speed
    "F0ID",  // Fan 0 ID
    "F1Ac",  // Fan 1 actual speed
    "FS! ",  // Fan speed forced bits
    "Ftst",  // Fan test mode
]

print("\nTrying fan keys:")
for key in fanKeys {
    let (success, data, type) = readSMCKey(key)
    if success {
        print("  \(key) [\(type)]: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Decode common types
        if type == "ui8 " && data.count >= 1 {
            print("       -> \(data[0])")
        } else if type == "ui16" && data.count >= 2 {
            let value = (UInt16(data[0]) << 8) | UInt16(data[1])
            print("       -> \(value)")
        } else if type == "flt " && data.count >= 4 {
            let bits = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
            let value = Float(bitPattern: bits)
            print("       -> \(value)")
        } else if type == "fpe2" && data.count >= 2 {
            // Fixed point 14.2
            let raw = (UInt16(data[0]) << 8) | UInt16(data[1])
            let value = Double(raw) / 4.0
            print("       -> \(value) RPM")
        }
    } else {
        print("  \(key): FAILED")
    }
}

// Try to enumerate all keys
print("\nEnumerating SMC keys (first 100):")
var input = SMCKeyData()
var output = SMCKeyData()

// Get total key count
input.data8 = kSMCGetKeyFromIndex
input.data32 = 0

var outputSize = MemoryLayout<SMCKeyData>.size
let countResult = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

if countResult == kIOReturnSuccess {
    // Try to get keys by index
    var fanRelatedKeys: [String] = []

    for i: UInt32 in 0..<100 {
        input.data8 = kSMCGetKeyFromIndex
        input.data32 = i

        let result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
        if result == kIOReturnSuccess && output.key != 0 {
            let keyName = stringFromFourCharCode(output.key)
            if keyName.hasPrefix("F") || keyName.contains("fan") || keyName.contains("Fan") {
                fanRelatedKeys.append(keyName)
            }
        }
    }

    if !fanRelatedKeys.isEmpty {
        print("Fan-related keys found: \(fanRelatedKeys)")
    } else {
        print("No fan-related keys found in first 100 keys")
    }
}

IOServiceClose(conn)
print("\nDone")
