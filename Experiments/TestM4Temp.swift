#!/usr/bin/env swift

import Foundation
import IOKit

// Use raw pointers for HID types
typealias IOHIDEventSystemClientRef = UnsafeMutableRawPointer
typealias IOHIDServiceClientRef = UnsafeMutableRawPointer
typealias IOHIDEventRef = UnsafeMutableRawPointer

// IOHIDEventSystemClient functions
@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary?)

@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64, _ options: Int32, _ timeout: Int64) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: UInt32) -> Double

// Constants
let kIOHIDEventTypeTemperature: Int64 = 15
let kIOHIDEventFieldTemperatureLevel: UInt32 = 0xf0000

print("M4 Temperature Monitor Test")
print("===========================")

// Get model
var size: Int = 0
sysctlbyname("hw.model", nil, &size, nil, 0)
var model = [CChar](repeating: 0, count: size)
sysctlbyname("hw.model", &model, &size, nil, 0)
let modelString = String(cString: model)
print("Model: \(modelString)")

// Create HID client
guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    print("ERROR: Failed to create IOHIDEventSystemClient")
    exit(1)
}

// Set matching for temperature sensors
let matching: [String: Any] = [
    "PrimaryUsagePage" as String: 0xFF00,
    "PrimaryUsage" as String: 5
]
IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

// Get services
guard let servicesUnmanaged = IOHIDEventSystemClientCopyServices(client) else {
    print("ERROR: No HID services found")
    exit(1)
}

let servicesArray = servicesUnmanaged.takeRetainedValue() as NSArray
print("Found \(servicesArray.count) temperature sensors\n")

var temperatures: [(name: String, temp: Double)] = []

for i in 0..<servicesArray.count {
    let service = Unmanaged<AnyObject>.passUnretained(servicesArray[i] as AnyObject).toOpaque()

    // Get product name
    var name = "Unknown"
    if let productUnmanaged = IOHIDServiceClientCopyProperty(service, "Product" as CFString) {
        let productRef = productUnmanaged.takeRetainedValue()
        if let productName = productRef as? String {
            name = productName
        }
    }

    // Get temperature event
    if let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) {
        let temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
        if temp > 0 && temp < 150 {
            temperatures.append((name: name, temp: temp))
        }
    }
}

// Sort by name
temperatures.sort { $0.name < $1.name }

// Print results
if temperatures.isEmpty {
    print("No temperature readings available")
} else {
    print("Temperature Readings:")
    print("---------------------")
    for (name, temp) in temperatures {
        print(String(format: "%-30s: %.1f°C", (name as NSString).utf8String!, temp))
    }

    // Calculate stats
    let tdieTemps = temperatures.filter { $0.name.contains("tdie") }
    let tdevTemps = temperatures.filter { $0.name.contains("tdev") }
    let maxTemp = temperatures.map { $0.temp }.max() ?? 0
    let avgTdie = tdieTemps.isEmpty ? 0 : tdieTemps.map { $0.temp }.reduce(0, +) / Double(tdieTemps.count)

    print("\n---------------------")
    print(String(format: "CPU (tdie avg): %.1f°C", avgTdie))
    print(String(format: "Max Temperature: %.1f°C", maxTemp))
    print("Total Sensors: \(temperatures.count)")
    print("  - tdie (CPU core): \(tdieTemps.count)")
    print("  - tdev (device): \(tdevTemps.count)")
}
