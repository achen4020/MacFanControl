// SystemMonitor.swift - CPU 和内存监控

import Foundation
import MacFanControlCore
import Darwin
// MARK: - CPU 负载监测

class CPULoadMonitor {
    struct CPUUsage {
        let user: Double
        let system: Double
        let idle: Double
        let total: Double
    }

    private var previousInfo: host_cpu_load_info?
    private let hostPort = mach_host_self()

    func getCPUUsage() -> CPUUsage? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        defer { previousInfo = info }

        guard let prev = previousInfo else {
            return CPUUsage(user: 0, system: 0, idle: 100, total: 0)
        }

        let userDiff = user - Double(prev.cpu_ticks.0)
        let systemDiff = system - Double(prev.cpu_ticks.1)
        let idleDiff = idle - Double(prev.cpu_ticks.2)
        let niceDiff = nice - Double(prev.cpu_ticks.3)

        let total = userDiff + systemDiff + idleDiff + niceDiff

        guard total > 0 else {
            return CPUUsage(user: 0, system: 0, idle: 100, total: 0)
        }

        return CPUUsage(
            user: (userDiff / total) * 100,
            system: (systemDiff / total) * 100,
            idle: (idleDiff / total) * 100,
            total: ((userDiff + systemDiff) / total) * 100
        )
    }

    func estimateTemperature() -> Double {
        guard let usage = getCPUUsage() else { return 45.0 }
        let baseTemp = 35.0
        let maxTemp = 85.0
        return baseTemp + (usage.total / 100.0) * (maxTemp - baseTemp)
    }
}

// MARK: - 内存监测

class MemoryMonitor {
    private let hostPort = mach_host_self()
    private let totalMemory: UInt64

    init() {
        var mem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &size, nil, 0)
        totalMemory = mem
    }

    struct MemoryUsage {
        let used: UInt64      // 已使用内存 (bytes)
        let free: UInt64      // 空闲内存 (bytes)
        let total: UInt64     // 总内存 (bytes)
        let percentage: Double // 使用百分比

        var usedGB: Double {
            Double(used) / 1_073_741_824
        }

        var totalGB: Double {
            Double(total) / 1_073_741_824
        }

        var formattedUsed: String {
            String(format: "%.1f GB", usedGB)
        }

        var formattedTotal: String {
            String(format: "%.1f GB", totalGB)
        }
    }

    func getMemoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)

        // 计算已使用内存
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let free = totalMemory - used

        let percentage = Double(used) / Double(totalMemory) * 100

        return MemoryUsage(
            used: used,
            free: free,
            total: totalMemory,
            percentage: percentage
        )
    }
}

// MARK: - Startup Volume Monitoring

class StorageMonitor {
    private let fileManager: FileManager
    private let path: String
    private let cacheInterval: TimeInterval
    private var cachedUsage: StorageUsage?
    private var lastAttempt: Date?

    init(
        fileManager: FileManager = .default,
        path: String = "/",
        cacheInterval: TimeInterval = 30
    ) {
        self.fileManager = fileManager
        self.path = path
        self.cacheInterval = cacheInterval
    }

    func getStorageUsage() -> StorageUsage? {
        if let lastAttempt,
           Date().timeIntervalSince(lastAttempt) < cacheInterval {
            return cachedUsage
        }

        lastAttempt = Date()

        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: path),
              let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let available = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value,
              let usage = StorageUsage(total: total, available: available) else {
            cachedUsage = nil
            return nil
        }

        cachedUsage = usage
        return usage
    }
}

// MARK: - Physical Network Monitoring

class NetworkMonitor {
    private var previousSnapshot: NetworkTransferSnapshot?

    func getNetworkSpeed() -> NetworkSpeed {
        guard let current = captureSnapshot() else {
            previousSnapshot = nil
            return .zero
        }

        defer { previousSnapshot = current }
        guard let previousSnapshot else { return .zero }
        return NetworkSpeed.between(previous: previousSnapshot, current: current)
    }

    private func captureSnapshot() -> NetworkTransferSnapshot? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var activeInterfaces = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = cursor {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            let family = interface.ifa_addr.map { Int32($0.pointee.sa_family) }

            if name.hasPrefix("en"),
               (flags & IFF_UP) != 0,
               (flags & IFF_RUNNING) != 0,
               family == AF_INET || family == AF_INET6 {
                activeInterfaces.insert(name)
            }

            cursor = interface.ifa_next
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        cursor = firstAddress

        while let current = cursor {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let family = interface.ifa_addr.map { Int32($0.pointee.sa_family) }

            if activeInterfaces.contains(name),
               family == AF_LINK,
               let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                receivedBytes += UInt64(data.ifi_ibytes)
                sentBytes += UInt64(data.ifi_obytes)
            }

            cursor = interface.ifa_next
        }

        return NetworkTransferSnapshot(
            timestamp: Date(),
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            interfaces: activeInterfaces
        )
    }
}
