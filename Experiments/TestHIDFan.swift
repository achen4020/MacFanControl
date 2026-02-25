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

print("Searching for Fan Sensors in HID System...")
print("==========================================")

// Create HID client
guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    print("ERROR: Failed to create IOHIDEventSystemClient")
    exit(1)
}

// Try different usage pages and usages
// 0xFF00 = Apple vendor page
// Usage 5 = Temperature
// Usage 6 = Fan? (guessing)
// Usage 1 = Power?

let usagesToTry: [(String, Int, Int)] = [
    ("Temperature (0xFF00:5)", 0xFF00, 5),
    ("Fan? (0xFF00:6)", 0xFF00, 6),
    ("Power? (0xFF00:1)", 0xFF00, 1),
    ("Voltage? (0xFF00:2)", 0xFF00, 2),
    ("Current? (0xFF00:3)", 0xFF00, 3),
    ("Unknown (0xFF00:4)", 0xFF00, 4),
    ("Unknown (0xFF00:7)", 0xFF00, 7),
    ("Unknown (0xFF00:8)", 0xFF00, 8),
    ("Unknown (0xFF00:0x20)", 0xFF00, 0x20),
    ("Unknown (0xFF00:0x21)", 0xFF00, 0x21),
]

for (name, page, usage) in usagesToTry {
    let matching: [String: Any] = [
        "PrimaryUsagePage": page,
        "PrimaryUsage": usage
    ]
    IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

    if let servicesUnmanaged = IOHIDEventSystemClientCopyServices(client) {
        let servicesArray = servicesUnmanaged.takeRetainedValue() as NSArray
        if servicesArray.count > 0 {
            print("\n\(name): Found \(servicesArray.count) services")

            for i in 0..<min(servicesArray.count, 3) {
                let service = Unmanaged<AnyObject>.passUnretained(servicesArray[i] as AnyObject).toOpaque()

                var productName = "Unknown"
                if let productUnmanaged = IOHIDServiceClientCopyProperty(service, "Product" as CFString) {
                    let productRef = productUnmanaged.takeRetainedValue()
                    if let name = productRef as? String {
                        productName = name
                    }
                }
                print("  - \(productName)")
            }
            if servicesArray.count > 3 {
                print("  ... and \(servicesArray.count - 3) more")
            }
        }
    }
}

// Now search without matching to see all services
print("\n\nAll HID Services (no filter):")
print("=============================")
IOHIDEventSystemClientSetMatching(client, nil)

if let servicesUnmanaged = IOHIDEventSystemClientCopyServices(client) {
    let servicesArray = servicesUnmanaged.takeRetainedValue() as NSArray
    print("Total services: \(servicesArray.count)")

    var servicesByType: [String: Int] = [:]

    for i in 0..<servicesArray.count {
        let service = Unmanaged<AnyObject>.passUnretained(servicesArray[i] as AnyObject).toOpaque()

        var productName = "Unknown"
        if let productUnmanaged = IOHIDServiceClientCopyProperty(service, "Product" as CFString) {
            let productRef = productUnmanaged.takeRetainedValue()
            if let name = productRef as? String {
                productName = name
            }
        }

        // Categorize by prefix
        let prefix = productName.components(separatedBy: " ").first ?? productName
        servicesByType[prefix, default: 0] += 1

        // Print if it looks like fan
        if productName.lowercased().contains("fan") || productName.lowercased().contains("rpm") {
            print("  FOUND FAN: \(productName)")
        }
    }

    print("\nServices by type:")
    for (type, count) in servicesByType.sorted(by: { $0.key < $1.key }) {
        print("  \(type): \(count)")
    }
}
