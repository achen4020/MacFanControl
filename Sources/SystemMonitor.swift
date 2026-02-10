// SystemMonitor.swift - CPU 和内存监控

import Foundation
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