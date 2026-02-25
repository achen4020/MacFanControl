#!/usr/bin/env swift

import Foundation
import IOKit

// SMC structures - matching Apple's internal structure
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
let kSMCGetKeyFromIndex: UInt8 = 8
let kSMCGetKeyCount: UInt8 = 1

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

print("Advanced SMC Test")
print("=================")

// Open AppleSMCKeysEndpoint specifically
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))

guard service != 0 else {
    print("ERROR: AppleSMCKeysEndpoint not found")
    exit(1)
}

var conn: io_connect_t = 0
let openResult = IOServiceOpen(service, mach_task_self_, 0, &conn)
IOObjectRelease(service)

guard openResult == kIOReturnSuccess else {
    print("ERROR: Failed to open service: \(String(format: "0x%x", openResult))")
    exit(1)
}

print("Connection opened: \(conn)")

// Try to get key count first
print("\nTrying to get SMC key count...")

var input = SMCKeyData()
var output = SMCKeyData()
var outputSize = MemoryLayout<SMCKeyData>.size

// Method 1: Try selector 2 with kSMCGetKeyCount
input.data8 = kSMCGetKeyCount
var result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
print("Selector 2, GetKeyCount: \(String(format: "0x%x", result)), data32=\(output.data32)")

// Method 2: Try reading #KEY which contains key count
input = SMCKeyData()
output = SMCKeyData()
input.key = fourCharCode("#KEY")
input.data8 = kSMCGetKeyInfo

result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
print("#KEY GetKeyInfo: \(String(format: "0x%x", result)), dataSize=\(output.keyInfo.0)")

if result == kIOReturnSuccess && output.keyInfo.0 > 0 {
    input.keyInfo.0 = output.keyInfo.0
    input.data8 = kSMCReadKey

    result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
    print("#KEY ReadKey: \(String(format: "0x%x", result))")

    if result == kIOReturnSuccess {
        let keyCount = (UInt32(output.bytes.0) << 24) | (UInt32(output.bytes.1) << 16) |
                       (UInt32(output.bytes.2) << 8) | UInt32(output.bytes.3)
        print("Total SMC keys: \(keyCount)")
    }
}

// Try to enumerate keys
print("\nEnumerating SMC keys...")
var foundKeys: [String] = []

for i: UInt32 in 0..<500 {
    input = SMCKeyData()
    output = SMCKeyData()
    input.data8 = kSMCGetKeyFromIndex
    input.data32 = i

    result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)

    if result == kIOReturnSuccess && output.key != 0 {
        let keyName = stringFromFourCharCode(output.key)
        foundKeys.append(keyName)

        // Check if it's a fan key
        if keyName.hasPrefix("F") && (keyName.contains("Ac") || keyName.contains("Mn") || keyName.contains("Mx") || keyName == "FNum") {
            print("  Found fan key: \(keyName)")

            // Try to read it
            var readInput = SMCKeyData()
            var readOutput = SMCKeyData()
            readInput.key = output.key
            readInput.data8 = kSMCGetKeyInfo

            let infoResult = IOConnectCallStructMethod(conn, 2, &readInput, MemoryLayout<SMCKeyData>.size, &readOutput, &outputSize)
            if infoResult == kIOReturnSuccess {
                let dataSize = readOutput.keyInfo.0
                let dataType = stringFromFourCharCode(readOutput.keyInfo.1)
                print("    Type: \(dataType), Size: \(dataSize)")

                readInput.keyInfo.0 = dataSize
                readInput.data8 = kSMCReadKey

                let readResult = IOConnectCallStructMethod(conn, 2, &readInput, MemoryLayout<SMCKeyData>.size, &readOutput, &outputSize)
                if readResult == kIOReturnSuccess {
                    var bytes: [UInt8] = []
                    withUnsafeBytes(of: readOutput.bytes) { ptr in
                        for j in 0..<Int(dataSize) {
                            bytes.append(ptr[j])
                        }
                    }
                    print("    Data: \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")

                    // Decode fpe2 (fixed point 14.2)
                    if dataType == "fpe2" && bytes.count >= 2 {
                        let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                        let rpm = Double(raw) / 4.0
                        print("    RPM: \(rpm)")
                    }
                }
            }
        }
    } else if result != kIOReturnSuccess {
        break
    }
}

print("\nTotal keys found: \(foundKeys.count)")

// Print some interesting keys
let interestingPrefixes = ["F", "T", "P", "V", "I"]
for prefix in interestingPrefixes {
    let matching = foundKeys.filter { $0.hasPrefix(prefix) }
    if !matching.isEmpty {
        print("\(prefix)* keys: \(matching.prefix(10).joined(separator: ", "))\(matching.count > 10 ? "..." : "")")
    }
}

IOServiceClose(conn)
print("\nDone")
