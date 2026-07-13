# 网络上传下载速度监控实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在菜单中显示当前活跃物理网络接口合计的实时下载和上传速度。

**Architecture:** `MacFanControlCore` 提供纯快照差值计算和单位格式化，`NetworkMonitor` 使用 `getifaddrs` 采集活跃 `en*` 接口累计字节，`FanController` 复用两秒循环发布速度，SwiftUI 负责展示。

**Tech Stack:** Swift 5.9、Darwin `getifaddrs`、SwiftUI、Foundation、XCTest、Swift Package Manager。

## 全局约束

- 只统计有 IPv4/IPv6 地址且 `UP/RUNNING` 的 `en*` 接口。
- 排除回环、VPN、AWDL、桥接及其他虚拟接口。
- 首次采样、接口变化、计数器回退和无效间隔返回零。
- 不新增定时器或第三方依赖。

---

### Task 1：速率模型和格式化

**Files:**
- Modify: `Core/Models.swift`
- Test: `Tests/MacFanControlCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `NetworkTransferSnapshot`、`NetworkSpeed.zero`、`NetworkSpeed.between(previous:current:)`、`NetworkSpeed.format(bytesPerSecond:)`

- [ ] **Step 1：编写失败测试**

```swift
func testNetworkSpeed_calculatesRatesUsingElapsedTime() {
    let previous = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 10), receivedBytes: 1_000, sentBytes: 2_000, interfaces: ["en0"])
    let current = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 12), receivedBytes: 5_000, sentBytes: 3_000, interfaces: ["en0"])
    let speed = NetworkSpeed.between(previous: previous, current: current)
    XCTAssertEqual(speed.downloadBytesPerSecond, 2_000)
    XCTAssertEqual(speed.uploadBytesPerSecond, 500)
}

func testNetworkSpeed_rejectsDiscontinuousSnapshots() {
    let base = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 10), receivedBytes: 2_000, sentBytes: 2_000, interfaces: ["en0"])
    let changed = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 12), receivedBytes: 3_000, sentBytes: 3_000, interfaces: ["en1"])
    let reset = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 12), receivedBytes: 1_000, sentBytes: 1_000, interfaces: ["en0"])
    let invalidTime = NetworkTransferSnapshot(timestamp: Date(timeIntervalSince1970: 10), receivedBytes: 3_000, sentBytes: 3_000, interfaces: ["en0"])
    XCTAssertEqual(NetworkSpeed.between(previous: base, current: changed), .zero)
    XCTAssertEqual(NetworkSpeed.between(previous: base, current: reset), .zero)
    XCTAssertEqual(NetworkSpeed.between(previous: base, current: invalidTime), .zero)
}

func testNetworkSpeed_formatsUnits() {
    XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 500), "500.0 B/s")
    XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 1_500), "1.5 KB/s")
    XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 2_500_000), "2.5 MB/s")
    XCTAssertEqual(NetworkSpeed.format(bytesPerSecond: 3_500_000_000), "3.5 GB/s")
}
```

- [ ] **Step 2：运行测试确认 RED**

Run: `swift test --filter NetworkSpeed`

Expected: 编译失败，提示找不到网络模型。

- [ ] **Step 3：实现最小模型**

快照包含 `Date`、两个 `UInt64` 计数器和 `Set<String>`。`between` 先验证接口集合相等且非空、间隔为正、计数器非递减，再用差值除以秒数。格式化按十进制 1000 进位并将负值钳制为零。

- [ ] **Step 4：运行模型测试确认 GREEN**

Run: `swift test --filter NetworkSpeed`

Expected: 网络模型测试全部通过。

### Task 2：物理接口采样与控制器接入

**Files:**
- Modify: `Sources/SystemMonitor.swift`
- Modify: `Sources/FanController.swift`

**Interfaces:**
- Consumes: `NetworkTransferSnapshot`、`NetworkSpeed.between`
- Produces: `NetworkMonitor.getNetworkSpeed()`、`FanController.networkSpeed`

- [ ] **Step 1：实现 `NetworkMonitor`**

使用 `getifaddrs` 两遍扫描：第一遍收集有 IP 地址、名称以 `en` 开头且 `IFF_UP/IFF_RUNNING` 的接口；第二遍读取这些接口的 `AF_LINK` `if_data`，累计 `ifi_ibytes/ifi_obytes`。每次采样更新上一份快照并返回差值速度。

- [ ] **Step 2：接入现有监控循环**

`FanController` 新增默认注入的 `NetworkMonitor` 和 `@Published var networkSpeed = NetworkSpeed.zero`。在 CPU、内存、存储统计阶段调用一次，仅在值变化时赋值。

- [ ] **Step 3：运行完整构建**

Run: `swift test`

Expected: 应用、Helper 和测试 target 构建成功，全部测试通过。

### Task 3：菜单展示与最终验证

**Files:**
- Modify: `Sources/MenuBarViews.swift`

**Interfaces:**
- Consumes: `fanController.networkSpeed`、`NetworkSpeed.format`

- [ ] **Step 1：添加网络行**

在系统状态区域增加 `network` 图标和“网络”标签；右侧同一行显示蓝色下载 `↓` 与绿色上传 `↑`，各自使用 `NetworkSpeed.format`。

- [ ] **Step 2：最终验证与提交**

Run: `swift test`

Expected: 全部测试通过。

Run: `git diff --check`

Expected: 无输出。

```bash
git add Core/Models.swift Sources/SystemMonitor.swift Sources/FanController.swift Sources/MenuBarViews.swift Tests/MacFanControlCoreTests/ModelsTests.swift
git commit -m "feat: show physical network transfer speeds"
```
