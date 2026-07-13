// SMC.swift - SMC (System Management Controller) Access Layer
// Provides low-level access to read temperature sensors and fan data on macOS

import Foundation
import IOKit

// MARK: - SMC Data Types

/// SMC key data version information
public struct SMCKeyDataVersion {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0
    public init() {}
}

/// SMC key limits
public struct SMCKeyDataLimits {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0
    public init() {}
}

/// SMC key information
public struct SMCKeyDataKeyInfo {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
    public init() {}
}

/// SMC key data structure used for IOKit communication
public struct SMCKeyData {
    public var key: UInt32 = 0
    public var vers: SMCKeyDataVersion = SMCKeyDataVersion()
    public var pLimitData: SMCKeyDataLimits = SMCKeyDataLimits()
    public var keyInfo: SMCKeyDataKeyInfo = SMCKeyDataKeyInfo()
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    public init() {}
}

/// SMC value structure
public struct SMCValue {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    public init() {}
}

// MARK: - SMC Constants

/// SMC selector commands
public enum SMCSelector: UInt8 {
    case kSMCHandleYPCEvent = 2
    case kSMCReadKey = 5
    case kSMCWriteKey = 6
    case kSMCGetKeyFromIndex = 8
    case kSMCGetKeyInfo = 9
}

/// Common SMC keys
public struct SMCKeys {
    // Temperature keys
    public static let cpuProximity = "TC0P"      // CPU proximity temperature
    public static let cpuDie = "TC0D"            // CPU die temperature
    public static let cpuCore0 = "TC0C"          // CPU core 0
    public static let cpuCore1 = "TC1C"          // CPU core 1
    public static let gpuProximity = "TG0P"      // GPU proximity
    public static let gpuDie = "TG0D"            // GPU die
    public static let memoryProximity = "Tm0P"   // Memory proximity
    public static let batteryTemp = "TB0T"       // Battery temperature
    public static let palmRest = "Ts0P"          // Palm rest
    public static let ssdTemp = "TH0P"           // SSD temperature

    // Fan keys
    public static let fanCount = "FNum"          // Number of fans
    public static func fanActualSpeed(_ index: Int) -> String { "F\(index)Ac" }  // Actual speed
    public static func fanMinSpeed(_ index: Int) -> String { "F\(index)Mn" }     // Minimum speed
    public static func fanMaxSpeed(_ index: Int) -> String { "F\(index)Mx" }     // Maximum speed
    public static func fanTargetSpeed(_ index: Int) -> String { "F\(index)Tg" }  // Target speed
    public static func fanMode(_ index: Int) -> String { "F\(index)Md" }         // Fan mode (auto/manual)
    public static let fanForce = "FS! "          // Force bits

    // Apple Silicon specific
    public static let cpuECluster = "Tp01"       // Efficiency cluster temp
    public static let cpuPCluster = "Tp05"       // Performance cluster temp

    // Apple Silicon fan unlock key (关键!)
    public static let fanTestMode = "Ftst"       // Force/Test mode - 必须设置为 1 才能控制风扇
}

// MARK: - SMC Manager

/// Main SMC access class
public class SMCManager {
    public static let shared = SMCManager()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private init() {}

    // MARK: - Connection Management

    /// Open connection to SMC
    public func open() throws {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            return // Already open
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )

        guard service != 0 else {
            throw SMCError.serviceNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            throw SMCError.connectionFailed(result)
        }
    }

    /// Close connection to SMC
    public func close() {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: - Key Operations

    /// Read SMC key and return raw value
    public func readKey(_ key: String) throws -> SMCValue {
        try open()

        var inputStruct = SMCKeyData()
        var outputStruct = SMCKeyData()

        inputStruct.key = key.smcKey
        inputStruct.data8 = SMCSelector.kSMCGetKeyInfo.rawValue

        try callSMC(&inputStruct, &outputStruct)

        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = SMCSelector.kSMCReadKey.rawValue

        try callSMC(&inputStruct, &outputStruct)

        var value = SMCValue()
        value.dataSize = outputStruct.keyInfo.dataSize
        value.dataType = outputStruct.keyInfo.dataType
        value.bytes = outputStruct.bytes

        return value
    }

    /// Write SMC key with value
    public func writeKey(_ key: String, value: SMCValue) throws {
        try open()

        var inputStruct = SMCKeyData()
        var outputStruct = SMCKeyData()

        inputStruct.key = key.smcKey
        inputStruct.data8 = SMCSelector.kSMCGetKeyInfo.rawValue

        try callSMC(&inputStruct, &outputStruct)

        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = SMCSelector.kSMCWriteKey.rawValue
        inputStruct.bytes = value.bytes

        try callSMC(&inputStruct, &outputStruct)
    }

    /// Call SMC with input/output structures
    private func callSMC(_ input: inout SMCKeyData, _ output: inout SMCKeyData) throws {
        let inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.kSMCHandleYPCEvent.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            throw SMCError.callFailed(result)
        }

        if output.result != 0 {
            throw SMCError.smcError(output.result)
        }
    }

    // MARK: - Temperature Reading

    /// Read temperature from sensor key (returns Celsius)
    public func readTemperature(key: String) -> Double? {
        do {
            let value = try readKey(key)
            return value.toTemperature()
        } catch {
            return nil
        }
    }

    /// Get CPU temperature (tries multiple keys)
    public func getCPUTemperature() -> Double? {
        // Try different CPU temperature keys
        let keys = [
            SMCKeys.cpuDie,
            SMCKeys.cpuProximity,
            SMCKeys.cpuPCluster,
            SMCKeys.cpuECluster,
            "Tc0c", "TC0c"
        ]

        for key in keys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 150 {
                return temp
            }
        }
        return nil
    }

    /// Get GPU temperature
    public func getGPUTemperature() -> Double? {
        let keys = [SMCKeys.gpuDie, SMCKeys.gpuProximity]
        for key in keys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 150 {
                return temp
            }
        }
        return nil
    }

    // MARK: - Fan Operations

    /// Get number of fans
    public func getFanCount() -> Int {
        do {
            let value = try readKey(SMCKeys.fanCount)
            return Int(value.bytes.0)
        } catch {
            return 0
        }
    }

    /// Get fan speed in RPM
    public func getFanSpeed(index: Int) -> Int? {
        do {
            let key = SMCKeys.fanActualSpeed(index)
            let value = try readKey(key)
            return value.toFanSpeed()
        } catch {
            return nil
        }
    }

    /// Get minimum fan speed
    public func getFanMinSpeed(index: Int) -> Int? {
        do {
            let key = SMCKeys.fanMinSpeed(index)
            let value = try readKey(key)
            return value.toFanSpeed()
        } catch {
            return nil
        }
    }

    /// Get maximum fan speed
    public func getFanMaxSpeed(index: Int) -> Int? {
        do {
            let key = SMCKeys.fanMaxSpeed(index)
            let value = try readKey(key)
            return value.toFanSpeed()
        } catch {
            return nil
        }
    }

    /// Get target fan speed
    public func getFanTargetSpeed(index: Int) -> Int? {
        do {
            let value = try readKey(SMCKeys.fanTargetSpeed(index))
            return value.toFanSpeed()
        } catch {
            return nil
        }
    }

    /// Get fan control mode
    public func getFanMode(index: Int) -> Int? {
        do {
            let value = try readKey(SMCKeys.fanMode(index))
            return Int(value.bytes.0)
        } catch {
            return nil
        }
    }

    /// Set fan speed (requires elevated privileges on Apple Silicon)
    public func setFanSpeed(index: Int, speed: Int) throws {
        // For Apple Silicon: Try to unlock fan control first
        try unlockAppleSiliconFanControl()

        // Enable manual mode
        try setFanManualMode(index: index, manual: true)

        // Set target speed
        let key = SMCKeys.fanTargetSpeed(index)
        var value = SMCValue()
        value.dataSize = 2

        // Convert to fpe2 format (fixed point, 14 bits integer, 2 bits fraction)
        let fpe2 = UInt16(speed) << 2
        value.bytes.0 = UInt8(fpe2 >> 8)
        value.bytes.1 = UInt8(fpe2 & 0xFF)

        try writeKey(key, value: value)
    }

    /// Unlock fan control on Apple Silicon (using Ftst key)
    /// This is required on M1/M2/M3/M4 Macs to override thermalmonitord
    private func unlockAppleSiliconFanControl() throws {
        // Try to set Ftst = 1 to enter diagnostic/test mode
        var value = SMCValue()
        value.dataSize = 1
        value.bytes.0 = 1

        do {
            try writeKey(SMCKeys.fanTestMode, value: value)
            print("✅ Apple Silicon fan control unlocked (Ftst=1)")
        } catch {
            // Ftst key might not exist on Intel Macs, which is fine
            print("ℹ️ Ftst key not available (Intel Mac or not supported)")
        }
    }

    /// Lock fan control back (return to system control)
    public func lockAppleSiliconFanControl() {
        var value = SMCValue()
        value.dataSize = 1
        value.bytes.0 = 0

        do {
            try writeKey(SMCKeys.fanTestMode, value: value)
            print("✅ Apple Silicon fan control locked (Ftst=0)")
        } catch {
            // Ignore errors
        }
    }

    /// Set fan to manual or automatic mode
    public func setFanManualMode(index: Int, manual: Bool) throws {
        // Try setting force bits
        do {
            let forceValue = try readKey(SMCKeys.fanForce)
            var newValue = forceValue

            if manual {
                // Set bit for this fan to force manual mode
                newValue.bytes.0 = forceValue.bytes.0 | UInt8(1 << index)
            } else {
                // Clear bit to return to auto mode
                newValue.bytes.0 = forceValue.bytes.0 & ~UInt8(1 << index)
            }

            try writeKey(SMCKeys.fanForce, value: newValue)
        } catch {
            // Fallback: try setting mode directly
            let key = SMCKeys.fanMode(index)
            var value = SMCValue()
            value.dataSize = 1
            value.bytes.0 = manual ? 1 : 0
            try writeKey(key, value: value)
        }
    }

    /// Reset fan to automatic control
    public func resetFanToAuto(index: Int) throws {
        try setFanManualMode(index: index, manual: false)
        // Also lock Apple Silicon fan control
        lockAppleSiliconFanControl()
    }

    // MARK: - Discovery

    /// Get all available temperature sensors
    public func getAllTemperatureSensors() -> [(key: String, value: Double)] {
        var sensors: [(String, Double)] = []

        let keys = [
            ("CPU Die", SMCKeys.cpuDie),
            ("CPU Proximity", SMCKeys.cpuProximity),
            ("CPU Core 0", SMCKeys.cpuCore0),
            ("CPU Core 1", SMCKeys.cpuCore1),
            ("GPU Die", SMCKeys.gpuDie),
            ("GPU Proximity", SMCKeys.gpuProximity),
            ("Memory", SMCKeys.memoryProximity),
            ("Battery", SMCKeys.batteryTemp),
            ("SSD", SMCKeys.ssdTemp),
            ("CPU P-Cluster", SMCKeys.cpuPCluster),
            ("CPU E-Cluster", SMCKeys.cpuECluster),
        ]

        for (name, key) in keys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 150 {
                sensors.append((name, temp))
            }
        }

        return sensors
    }
}

// MARK: - SMC Error

public enum SMCError: Error, LocalizedError {
    case serviceNotFound
    case connectionFailed(Int32)
    case callFailed(Int32)
    case smcError(UInt8)
    case invalidKey
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "SMC service not found. Make sure you're running on a real Mac."
        case .connectionFailed(let code):
            return "Failed to connect to SMC (error: \(code))"
        case .callFailed(let code):
            return "SMC call failed (error: \(code))"
        case .smcError(let code):
            return "SMC returned error code: \(code)"
        case .invalidKey:
            return "Invalid SMC key"
        case .notSupported:
            return "Operation not supported on this hardware"
        }
    }
}

// MARK: - Extensions

extension String {
    /// Convert 4-character string to SMC key (UInt32)
    public var smcKey: UInt32 {
        var result: UInt32 = 0
        let chars = Array(self.utf8)
        for i in 0..<min(4, chars.count) {
            result = result << 8 | UInt32(chars[i])
        }
        // Pad with spaces if needed
        for _ in chars.count..<4 {
            result = result << 8 | UInt32(Character(" ").asciiValue ?? 0x20)
        }
        return result
    }
}

extension SMCValue {
    /// Convert SMC value to temperature (Celsius)
    public func toTemperature() -> Double? {
        guard dataSize >= 2 else { return nil }

        // sp78 format: signed 7.8 fixed point
        let value = Int16(bytes.0) << 8 | Int16(bytes.1)
        return Double(value) / 256.0
    }

    /// Convert SMC value to fan speed (RPM)
    public func toFanSpeed() -> Int? {
        guard dataSize >= 2 else { return nil }

        // fpe2 format: unsigned 14.2 fixed point
        let value = UInt16(bytes.0) << 8 | UInt16(bytes.1)
        return Int(value >> 2)
    }
}
