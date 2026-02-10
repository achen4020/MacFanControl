// TemperatureReader.swift - Apple Silicon 温度传感器读取

import Foundation
import IOKit
import MacFanControlCore
// MARK: - M4 Temperature Reader (使用 IOHIDEventSystemClient)

/// M4 Mac 温度传感器读取器
class M4TempReader: TemperatureProvider {
    typealias ThermalReading = TemperatureReading

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

    func getTemperatures() -> [TemperatureReading] {
        guard isAvailable,
              let c = client,
              let services = copyServices?(c),
              let getProp = copyProperty,
              let getEvent = copyEvent,
              let getValue = getFloatValue else {
            return []
        }

        // copyServices returns a CF object with Copy semantics — caller must release
        defer {
            let unmanaged = Unmanaged<CFArray>.passUnretained(services)
            unmanaged.release()
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
                // copyProperty returns a CF object with Copy semantics
                Unmanaged<AnyObject>.passUnretained(prop as AnyObject).release()
            }

            // 获取温度事件
            if let event = getEvent(service, kIOHIDEventTypeTemperature, 0, 0) {
                // 温度字段: (type << 16) | 0 = 0xf0000
                let kIOHIDEventFieldTemperatureLevel: UInt32 = 0xf0000
                let temp = getValue(event, kIOHIDEventFieldTemperatureLevel)
                if temp > 0 && temp < 150 {
                    readings.append(TemperatureReading(name: name, temperature: temp))
                }
                // copyEvent returns a CF object with Copy semantics
                Unmanaged<AnyObject>.fromOpaque(event).release()
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