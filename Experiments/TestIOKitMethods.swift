#!/usr/bin/env swift

// 测试不同的 IOKit 调用方式
// 需要 sudo 运行

import Foundation
import IOKit

print("Testing Different IOKit Call Methods")
print("====================================")
print("UID: \(getuid())")

// 打开 AppleSMC
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0 else {
    print("ERROR: AppleSMC not found")
    exit(1)
}

var conn: io_connect_t = 0

// 尝试不同的 client type
for clientType: UInt32 in 0..<5 {
    let result = IOServiceOpen(service, mach_task_self_, clientType, &conn)
    if result == kIOReturnSuccess {
        print("Opened with client type \(clientType), connection: \(conn)")

        // 尝试不同的 selector
        for selector: UInt32 in 0..<10 {
            var input: [UInt64] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            var output: [UInt64] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            var outputCount: UInt32 = 10

            // 设置 key = "FNum" (0x464E756D)
            input[0] = 0x464E756D

            let callResult = IOConnectCallScalarMethod(conn, selector, input, 10, &output, &outputCount)
            if callResult == kIOReturnSuccess {
                print("  Selector \(selector) (scalar): SUCCESS, output: \(output[0])")
            } else if callResult != 0xe00002c2 && callResult != 0xe00002bc {
                print("  Selector \(selector) (scalar): \(String(format: "0x%x", callResult))")
            }
        }

        IOServiceClose(conn)
    }
}

IOObjectRelease(service)

// 尝试 AppleSMCKeysEndpoint
print("\n--- Trying AppleSMCKeysEndpoint ---")
let keysService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
if keysService != 0 {
    for clientType: UInt32 in 0..<5 {
        let result = IOServiceOpen(keysService, mach_task_self_, clientType, &conn)
        if result == kIOReturnSuccess {
            print("Opened AppleSMCKeysEndpoint with client type \(clientType)")

            // 尝试读取
            var inputStruct = [UInt8](repeating: 0, count: 80)
            var outputStruct = [UInt8](repeating: 0, count: 80)
            var outputSize = 80

            // 设置 key = "FNum"
            inputStruct[0] = 0x46  // F
            inputStruct[1] = 0x4E  // N
            inputStruct[2] = 0x75  // u
            inputStruct[3] = 0x6D  // m
            inputStruct[38] = 9    // kSMCGetKeyInfo

            for selector: UInt32 in 0..<10 {
                let callResult = IOConnectCallStructMethod(conn, selector, &inputStruct, 80, &outputStruct, &outputSize)
                if callResult == kIOReturnSuccess {
                    print("  Selector \(selector): SUCCESS")
                    print("    Output: \(outputStruct.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")
                } else if callResult != 0xe00002c2 {
                    print("  Selector \(selector): \(String(format: "0x%x", callResult))")
                }
            }

            IOServiceClose(conn)
        }
    }
    IOObjectRelease(keysService)
} else {
    print("AppleSMCKeysEndpoint not found")
}

print("\nDone")
