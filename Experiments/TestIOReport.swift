#!/usr/bin/env swift

import Foundation
import IOKit

// IOReport functions
@_silgen_name("IOReportCopyAllChannels")
func IOReportCopyAllChannels(_ a: UInt64, _ b: UInt64) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCopyChannelsInGroup")
func IOReportCopyChannelsInGroup(_ group: CFString, _ subgroup: CFString?, _ a: UInt64, _ b: UInt64, _ c: UInt64) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCreateSubscription")
func IOReportCreateSubscription(_ a: UnsafeMutableRawPointer?, _ channels: CFDictionary, _ b: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, _ c: UInt64, _ d: UnsafeMutablePointer<CFTypeRef?>?) -> Unmanaged<AnyObject>?

@_silgen_name("IOReportCreateSamples")
func IOReportCreateSamples(_ subscription: AnyObject, _ channels: CFMutableDictionary, _ callback: CFTypeRef?) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCreateSamplesDelta")
func IOReportCreateSamplesDelta(_ a: CFDictionary, _ b: CFDictionary, _ c: CFTypeRef?) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportIterate")
func IOReportIterate(_ samples: CFDictionary, _ callback: @convention(c) (CFDictionary) -> Int32) -> Int32

print("IOReport Fan Search")
print("===================")

// Try to get all channels
if let channelsUnmanaged = IOReportCopyAllChannels(0, 0) {
    let channels = channelsUnmanaged.takeRetainedValue() as NSDictionary
    print("Got all channels")

    // Look for fan-related groups
    if let groups = channels["IOReportChannels"] as? [[String: Any]] {
        print("Total channel groups: \(groups.count)")

        var fanRelated: [[String: Any]] = []

        for group in groups {
            if let groupName = group["IOReportGroupName"] as? String {
                let lowerName = groupName.lowercased()
                if lowerName.contains("fan") || lowerName.contains("thermal") ||
                   lowerName.contains("cool") || lowerName.contains("rpm") ||
                   lowerName.contains("smc") {
                    fanRelated.append(group)
                    print("  Found: \(groupName)")
                }
            }
        }

        if fanRelated.isEmpty {
            print("\nNo fan-related groups found. Listing all groups:")
            let uniqueGroups = Set(groups.compactMap { $0["IOReportGroupName"] as? String })
            for group in uniqueGroups.sorted() {
                print("  - \(group)")
            }
        }
    }
} else {
    print("Failed to get all channels")
}

// Try specific groups
print("\n\nTrying specific groups:")
let groupsToTry = ["Fan", "Thermal", "SMC", "Energy Model", "CPU Stats", "GPU Stats"]

for groupName in groupsToTry {
    if let channelsUnmanaged = IOReportCopyChannelsInGroup(groupName as CFString, nil, 0, 0, 0) {
        let channels = channelsUnmanaged.takeRetainedValue() as NSDictionary
        print("\n\(groupName) group found:")

        if let channelList = channels["IOReportChannels"] as? [[String: Any]] {
            for channel in channelList.prefix(5) {
                if let name = channel["IOReportChannelName"] as? String {
                    print("  - \(name)")
                }
            }
            if channelList.count > 5 {
                print("  ... and \(channelList.count - 5) more")
            }
        }
    }
}

print("\n\nDone")
