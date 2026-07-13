# 启动磁盘监控实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除“更多传感器”，在主菜单直接显示 SSD 温度、启动磁盘已用/总容量和使用率。

**Architecture:** `MacFanControlCore.StorageUsage` 负责安全容量计算和稳定格式化，`StorageMonitor` 负责读取并缓存启动卷 `/` 的文件系统属性，`FanController` 聚合 SSD 温度及容量状态，SwiftUI 只负责呈现。

**Tech Stack:** Swift 5.9、SwiftUI、Foundation、XCTest、Swift Package Manager。

## 全局约束

- 只统计当前启动卷 `/`。
- SSD 温度只接受精确名称 `NAND CH0 temp`，SMC 回退不提供 SSD 温度。
- 文件系统读取失败时隐藏容量行，不显示零值。
- 不新增第三方依赖，不修改风扇控制和 HID 读取方式。

---

### Task 1：安全容量模型

**Files:**
- Modify: `Core/Models.swift`
- Test: `Tests/MacFanControlCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `StorageUsage.init?(total:available:)`、`formattedUsed`、`formattedTotal`

- [ ] **Step 1：编写失败测试**

```swift
func testStorageUsage_calculatesUsedCapacityAndPercentage() throws {
    let usage = try XCTUnwrap(StorageUsage(total: 500_000_000_000, available: 125_000_000_000))
    XCTAssertEqual(usage.used, 375_000_000_000)
    XCTAssertEqual(usage.percentage, 75, accuracy: 0.001)
    XCTAssertEqual(usage.formattedUsed, "375.0 GB")
    XCTAssertEqual(usage.formattedTotal, "500.0 GB")
}

func testStorageUsage_formatsTerabytes() throws {
    let usage = try XCTUnwrap(StorageUsage(total: 2_000_000_000_000, available: 500_000_000_000))
    XCTAssertEqual(usage.formattedUsed, "1.5 TB")
    XCTAssertEqual(usage.formattedTotal, "2.0 TB")
}

func testStorageUsage_rejectsInvalidCapacity() {
    XCTAssertNil(StorageUsage(total: 0, available: 0))
    XCTAssertNil(StorageUsage(total: 100, available: 101))
}
```

- [ ] **Step 2：运行测试确认 RED**

Run: `swift test --filter StorageUsage`

Expected: 编译失败，提示找不到 `StorageUsage`。

- [ ] **Step 3：实现最小模型**

```swift
public struct StorageUsage: Equatable {
    public let used: UInt64
    public let available: UInt64
    public let total: UInt64
    public let percentage: Double

    public init?(total: UInt64, available: UInt64) {
        guard total > 0, available <= total else { return nil }
        self.total = total
        self.available = available
        self.used = total - available
        self.percentage = Double(used) / Double(total) * 100
    }

    public var formattedUsed: String { Self.format(used) }
    public var formattedTotal: String { Self.format(total) }

    private static func format(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000_000 {
            return String(format: "%.1f TB", Double(bytes) / 1_000_000_000_000)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
```

- [ ] **Step 4：运行模型测试确认 GREEN**

Run: `swift test --filter StorageUsage`

Expected: 3 个容量测试通过。

### Task 2：启动卷监控与 SSD 温度状态

**Files:**
- Modify: `Sources/SystemMonitor.swift`
- Modify: `Sources/FanController.swift`

**Interfaces:**
- Consumes: `StorageUsage(total:available:)`
- Produces: `StorageMonitor.getStorageUsage()`、`FanController.ssdTemperature`、`FanController.storageUsage`

- [ ] **Step 1：新增缓存的启动卷监控**

在 `SystemMonitor.swift` 新增 `StorageMonitor`，默认 `path = "/"`、`cacheInterval = 30`。`getStorageUsage()` 在缓存有效时返回缓存，否则读取 `.systemSize` 和 `.systemFreeSize` 的 `NSNumber.uint64Value`，构造有效 `StorageUsage` 后更新缓存。

- [ ] **Step 2：接入控制器状态**

在 `FanController` 新增：

```swift
@Published var ssdTemperature: Double?
@Published var storageUsage: StorageUsage?
private let storageMonitor: StorageMonitor
```

构造函数注入默认 `StorageMonitor()`。每轮监控更新 `storageUsage`；HID 读数精确查找 `NAND CH0 temp` 并在主线程更新 `ssdTemperature`。SMC 回退明确将 SSD 温度设为 `nil`，避免把其他 SMC key 误认为 NAND 温度。

- [ ] **Step 3：运行完整构建**

Run: `swift test`

Expected: 应用、Helper 和测试 target 构建成功，所有测试通过。

### Task 3：移除更多传感器并显示 SSD 状态

**Files:**
- Modify: `Sources/MenuBarViews.swift:210-344`

**Interfaces:**
- Consumes: `fanController.ssdTemperature`、`fanController.storageUsage`

- [ ] **Step 1：删除展开列表**

删除 `showMoreSensors`、按钮、列表、过滤排序属性及仅供列表使用的 `sensorColor`。

- [ ] **Step 2：添加 SSD 温度与容量行**

SSD 温度存在时使用 `TemperatureRow(icon: "internaldrive", name: "SSD 温度", ...)`。容量存在时显示 `SSD 存储`、`已用 / 总容量` 和括号百分比，并用 50%、75%、90% 阈值着色。

- [ ] **Step 3：最终验证与提交**

Run: `swift test`

Expected: 全部测试通过。

Run: `git diff --check`

Expected: 无输出。

```bash
git add Core/Models.swift Sources/SystemMonitor.swift Sources/FanController.swift Sources/MenuBarViews.swift Tests/MacFanControlCoreTests/ModelsTests.swift
git commit -m "feat: show startup disk usage and SSD temperature"
```
