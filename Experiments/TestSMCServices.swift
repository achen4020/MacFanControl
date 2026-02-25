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

let kSMCGetKeyInfo: UInt8 = 9
let kSMCReadKey: UInt8 = 5

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

print("Testing Different SMC Services")
print("==============================")

// Try different service names
let serviceNames = [
    "AppleSMC",
    "AppleSMCKeysEndpoint",
    "AppleSMCClient",
    "IOSMCService",
]

for serviceName in serviceNames {
    print("\nTrying service: \(serviceName)")

    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))

    if service == 0 {
        print("  Service not found")
        continue
    }

    var conn: io_connect_t = 0

    // Try different user client types
    for clientType: UInt32 in 0..<5 {
        let result = IOServiceOpen(service, mach_task_self_, clientType, &conn)

        if result == kIOReturnSuccess {
            print("  Opened with client type \(clientType)")

            // Try to read FNum
            var input = SMCKeyData()
            var output = SMCKeyData()

            input.key = fourCharCode("FNum")
            input.data8 = kSMCGetKeyInfo

            var outputSize = MemoryLayout<SMCKeyData>.size

            // Try different selectors
            for selector: UInt32 in 0..<10 {
                let callResult = IOConnectCallStructMethod(conn, selector, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
                if callResult == kIOReturnSuccess && output.keyInfo.dataSize > 0 {
                    print("    Selector \(selector) works! dataSize=\(output.keyInfo.dataSize)")
                }
            }

            IOServiceClose(conn)
        }
    }

    IOObjectRelease(service)
}

// Try to find all SMC-related services
print("\n\nSearching for all SMC-related services:")
var iterator: io_iterator_t = 0
let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("SMC"), &iterator)

if matchResult == kIOReturnSuccess {
    var service = IOIteratorNext(iterator)
    while service != 0 {
        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &name)
        print("  Found: \(String(cString: name))")

        var className = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(service, &className)
        print("    Class: \(String(cString: className))")

        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    IOObjectRelease(iterator)
}

// Search by class
print("\nSearching by class pattern:")
let classPatterns = ["AppleSMC", "SMC", "Fan", "Thermal"]

for pattern in classPatterns {
    var iter: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(pattern), &iter)
    if result == kIOReturnSuccess {
        var count = 0
        var service = IOIteratorNext(iter)
        while service != 0 {
            count += 1
            if count <= 3 {
                var className = [CChar](repeating: 0, count: 128)
                IOObjectGetClass(service, &className)
                print("  \(pattern): \(String(cString: className))")
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        if count > 3 {
            print("  ... and \(count - 3) more")
        }
        IOObjectRelease(iter)
    }
}
