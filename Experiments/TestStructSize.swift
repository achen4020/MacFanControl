#!/usr/bin/env swift

import Foundation

// SMC 结构体 - 检查大小
struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo: (UInt32, UInt32, UInt8) = (0, 0, 0)
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

print("SMCKeyData size: \(MemoryLayout<SMCKeyData>.size)")
print("SMCKeyData stride: \(MemoryLayout<SMCKeyData>.stride)")
print("SMCKeyData alignment: \(MemoryLayout<SMCKeyData>.alignment)")

// 正确的 SMC 结构体 (80 bytes = 0x50)
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)  // 6 bytes + 2 padding = 8
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)  // 16 bytes
    var keyInfo: (UInt32, UInt32, UInt8) = (0, 0, 0)  // 9 bytes + 3 padding = 12
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0  // 4 bytes
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)  // 32 bytes
}

print("\nSMCParamStruct size: \(MemoryLayout<SMCParamStruct>.size)")
print("SMCParamStruct stride: \(MemoryLayout<SMCParamStruct>.stride)")

// 尝试匹配 Apple 的结构体定义
// 从 IOKit 头文件中的定义
struct AppleSMCKeyData {
    var key: UInt32 = 0                    // 4 bytes, offset 0
    var vers: UInt8 = 0                    // 1 byte
    var versMajor: UInt8 = 0               // 1 byte
    var versMinor: UInt8 = 0               // 1 byte
    var versBuild: UInt8 = 0               // 1 byte
    var versRelease: UInt16 = 0            // 2 bytes
    var versReserved: UInt16 = 0           // 2 bytes, total vers = 8 bytes

    var pLimitVersion: UInt16 = 0          // 2 bytes
    var pLimitLength: UInt16 = 0           // 2 bytes
    var pLimitCPU: UInt32 = 0              // 4 bytes
    var pLimitGPU: UInt32 = 0              // 4 bytes
    var pLimitMem: UInt32 = 0              // 4 bytes, total pLimit = 16 bytes

    var keyInfoDataSize: UInt32 = 0        // 4 bytes
    var keyInfoDataType: UInt32 = 0        // 4 bytes
    var keyInfoDataAttr: UInt8 = 0         // 1 byte + 3 padding = 4 bytes

    var result: UInt8 = 0                  // 1 byte
    var status: UInt8 = 0                  // 1 byte
    var data8: UInt8 = 0                   // 1 byte
    var data32: UInt32 = 0                 // 4 bytes

    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)  // 32 bytes
}

print("\nAppleSMCKeyData size: \(MemoryLayout<AppleSMCKeyData>.size)")
print("AppleSMCKeyData stride: \(MemoryLayout<AppleSMCKeyData>.stride)")

// 检查各字段偏移
print("\nField offsets in AppleSMCKeyData:")
print("  key: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.key)!)")
print("  vers: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.vers)!)")
print("  pLimitVersion: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.pLimitVersion)!)")
print("  keyInfoDataSize: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.keyInfoDataSize)!)")
print("  result: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.result)!)")
print("  data8: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.data8)!)")
print("  data32: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.data32)!)")
print("  bytes: \(MemoryLayout<AppleSMCKeyData>.offset(of: \AppleSMCKeyData.bytes)!)")
