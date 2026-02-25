#!/usr/bin/env swift

import Foundation
import IOKit

typealias IOHIDEventSystemClientRef = UnsafeMutableRawPointer
typealias IOHIDServiceClientRef = UnsafeMutableRawPointer
typealias IOHIDEventRef = UnsafeMutableRawPointer

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

@_silgen_name("IOHIDEventGetIntegerValue")
func IOHIDEventGetIntegerValue(_ event: IOHIDEventRef, _ field: UInt32) -> Int64

@_silgen_name("IOHIDEventGetType")
func IOHIDEventGetType(_ event: IOHIDEventRef) -> Int32

print("Searching for Fan Data via HID Events")
print("=====================================")

guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    print("ERROR: Failed to create IOHIDEventSystemClient")
    exit(1)
}

// Get all services without filter
IOHIDEventSystemClientSetMatching(client, nil)

guard let servicesUnmanaged = IOHIDEventSystemClientCopyServices(client) else {
    print("ERROR: No HID services found")
    exit(1)
}

let servicesArray = servicesUnmanaged.takeRetainedValue() as NSArray
print("Total HID services: \(servicesArray.count)")

// Known HID event types
let eventTypes: [(String, Int64)] = [
    ("NULL", 0),
    ("VendorDefined", 1),
    ("Button", 2),
    ("Keyboard", 3),
    ("Translation", 4),
    ("Rotation", 5),
    ("Scroll", 6),
    ("Scale", 7),
    ("Zoom", 8),
    ("Velocity", 9),
    ("Orientation", 10),
    ("Digitizer", 11),
    ("AmbientLightSensor", 12),
    ("Accelerometer", 13),
    ("Proximity", 14),
    ("Temperature", 15),
    ("NavigationSwipe", 16),
    ("PointerScroll", 17),
    ("Progress", 18),
    ("MultiAxisPointer", 19),
    ("Gyro", 20),
    ("Compass", 21),
    ("DockSwipe", 22),
    ("SymbolicHotKey", 23),
    ("Power", 24),
    ("LED", 25),
    ("FluidTouchGesture", 26),
    ("BoundaryScroll", 27),
    ("BiometricEvent", 28),
    ("Unicode", 29),
    ("AtmosphericPressure", 30),
    ("Force", 31),
    ("MotionActivity", 32),
    ("MotionGesture", 33),
    ("GameController", 34),
    ("Humidity", 35),
    ("Collection", 36),
    ("Brightness", 37),
    ("GenericGesture", 38),
]

print("\nSearching for services with fan-like events...")

for i in 0..<servicesArray.count {
    let service = Unmanaged<AnyObject>.passUnretained(servicesArray[i] as AnyObject).toOpaque()

    var productName = "Unknown"
    if let productUnmanaged = IOHIDServiceClientCopyProperty(service, "Product" as CFString) {
        let productRef = productUnmanaged.takeRetainedValue()
        if let name = productRef as? String {
            productName = name
        }
    }

    // Check for Power events (might contain fan data)
    if let event = IOHIDServiceClientCopyEvent(service, 24, 0, 0) {  // Power
        let eventType = IOHIDEventGetType(event)

        // Try to get values
        for field: UInt32 in [0x180000, 0x180001, 0x180002, 0x180003, 0x180004] {
            let floatVal = IOHIDEventGetFloatValue(event, field)
            let intVal = IOHIDEventGetIntegerValue(event, field)
            if floatVal != 0 || intVal != 0 {
                print("\(productName) - Power event field 0x\(String(field, radix: 16)): float=\(floatVal), int=\(intVal)")
            }
        }
    }

    // Check for Velocity events (might be fan RPM)
    if let event = IOHIDServiceClientCopyEvent(service, 9, 0, 0) {  // Velocity
        print("\(productName) has Velocity event")
        for field: UInt32 in 0..<10 {
            let floatVal = IOHIDEventGetFloatValue(event, field)
            if floatVal != 0 {
                print("  field \(field): \(floatVal)")
            }
        }
    }
}

// Check PMU services specifically for power/fan data
print("\n\nChecking PMU services for power data:")
let matching: [String: Any] = [
    "PrimaryUsagePage": 0xFF00,
    "PrimaryUsage": 1  // Power
]
IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

if let servicesUnmanaged = IOHIDEventSystemClientCopyServices(client) {
    let servicesArray = servicesUnmanaged.takeRetainedValue() as NSArray
    print("Found \(servicesArray.count) power services")

    for i in 0..<min(servicesArray.count, 10) {
        let service = Unmanaged<AnyObject>.passUnretained(servicesArray[i] as AnyObject).toOpaque()

        var productName = "Unknown"
        if let productUnmanaged = IOHIDServiceClientCopyProperty(service, "Product" as CFString) {
            let productRef = productUnmanaged.takeRetainedValue()
            if let name = productRef as? String {
                productName = name
            }
        }

        // Try Power event
        if let event = IOHIDServiceClientCopyEvent(service, 24, 0, 0) {
            // Power field: (24 << 16) | index = 0x180000 + index
            let baseField: UInt32 = 0x180000
            for idx: UInt32 in 0..<5 {
                let floatVal = IOHIDEventGetFloatValue(event, baseField + idx)
                if floatVal != 0 {
                    print("  \(productName) power[\(idx)]: \(floatVal)")
                }
            }
        }
    }
}

print("\n\nDone")
