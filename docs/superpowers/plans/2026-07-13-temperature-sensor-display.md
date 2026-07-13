# 温度传感器名称与过滤实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** “更多传感器”只展示可可靠识别的 CPU 温度通道和 SSD，并使用准确名称、数量和自然顺序。

**Architecture:** `TemperatureInfo` 作为唯一识别边界，通过可选 `displayName` 和可选 `displaySortOrder` 表达白名单结果。SwiftUI 只消费过滤排序后的模型集合，不再对未知名称做回退展示。

**Tech Stack:** Swift 5.9、SwiftUI、Foundation、XCTest、Swift Package Manager。

## 全局约束

- 只允许完整匹配 `PMU tdie<正整数>` 和 `NAND CH0 temp`。
- 不推测 `PMU2 tdie*`、`tdev*`、`tcal` 或未知名称。
- 不改变 HID 读取、CPU 温度提取和最高温度计算。
- 不新增第三方依赖。

---

### Task 1：传感器白名单模型

**Files:**
- Modify: `Core/Models.swift:122-198`
- Test: `Tests/MacFanControlCoreTests/ModelsTests.swift:79-106`

**Interfaces:**
- Produces: `TemperatureInfo.displayName: String?`、`TemperatureInfo.displaySortOrder: Int?`、`TemperatureInfo.isDisplayable: Bool`

- [ ] **Step 1：编写失败测试**

更新原有名称断言，并增加完整匹配、隐藏与排序测试：

```swift
func testDisplayName_knownSensor() {
    let info = TemperatureInfo(id: "t1", name: "PMU tdie1", value: 50)
    XCTAssertEqual(info.displayName, "CPU 温度通道 1")
}

func testDisplayName_ssd() {
    let info = TemperatureInfo(id: "t1", name: "NAND CH0 temp", value: 40)
    XCTAssertEqual(info.displayName, "SSD")
}

func testDisplayName_filtersAmbiguousSensors() {
    for name in ["PMU2 tdie1", "PMU tdev1", "PMU2 tdev1", "PMU tcal", "PMU2 tcal", "Unknown"] {
        XCTAssertNil(TemperatureInfo(id: name, name: name, value: 40).displayName)
    }
}

func testDisplayName_requiresCompleteCPUChannelMatch() {
    XCTAssertNil(TemperatureInfo(id: "bad", name: "PMU tdie1 extra", value: 40).displayName)
    XCTAssertNil(TemperatureInfo(id: "zero", name: "PMU tdie0", value: 40).displayName)
}

func testDisplaySortOrder_usesNaturalChannelOrderAndSSDLast() {
    let names = ["NAND CH0 temp", "PMU tdie10", "PMU tdie2"]
    let sorted = names.map { TemperatureInfo(id: $0, name: $0, value: 40) }
        .sorted { $0.displaySortOrder! < $1.displaySortOrder! }
    XCTAssertEqual(sorted.compactMap(\.displayName), ["CPU 温度通道 2", "CPU 温度通道 10", "SSD"])
}
```

- [ ] **Step 2：运行测试确认 RED**

Run: `swift test --filter ModelsTests`

Expected: 名称和隐藏断言失败，并提示缺少 `displaySortOrder`。

- [ ] **Step 3：实现严格白名单**

删除现有字典和模糊 `contains` 回退，加入：

```swift
private var cpuChannelNumber: Int? {
    let prefix = "PMU tdie"
    guard name.hasPrefix(prefix) else { return nil }
    let suffix = name.dropFirst(prefix.count)
    guard !suffix.isEmpty,
          suffix.allSatisfy({ $0.isNumber }),
          let number = Int(suffix),
          number > 0 else { return nil }
    return number
}

public var displayName: String? {
    if let channel = cpuChannelNumber { return "CPU 温度通道 \(channel)" }
    if name == "NAND CH0 temp" { return "SSD" }
    return nil
}

public var displaySortOrder: Int? {
    if let channel = cpuChannelNumber { return channel }
    if name == "NAND CH0 temp" { return 10_000 }
    return nil
}

public var isDisplayable: Bool { displayName != nil }
```

- [ ] **Step 4：运行模型测试确认 GREEN**

Run: `swift test --filter ModelsTests`

Expected: 全部模型测试通过。

### Task 2：“更多传感器”使用过滤集合

**Files:**
- Modify: `Sources/MenuBarViews.swift:210-316`

**Interfaces:**
- Consumes: `TemperatureInfo.isDisplayable`、`displayName`、`displaySortOrder`

- [ ] **Step 1：新增界面计算属性**

```swift
private var displayableSensors: [TemperatureInfo] {
    fanController.temperatures
        .filter(\.isDisplayable)
        .sorted {
            ($0.displaySortOrder ?? Int.max) < ($1.displaySortOrder ?? Int.max)
        }
}
```

- [ ] **Step 2：替换所有原始数组计数与遍历**

按钮显示条件、数量、`prefix(12)` 和剩余数量全部使用 `displayableSensors`；行内使用：

```swift
if let displayName = sensor.displayName {
    HStack {
        Text(displayName)
        Spacer()
        Text(sensor.formattedValue)
    }
}
```

- [ ] **Step 3：运行完整验证**

Run: `swift test`

Expected: 应用、Helper 和测试 target 构建成功，全部测试通过。

Run: `git diff --check`

Expected: 无输出。

- [ ] **Step 4：提交实现**

```bash
git add Core/Models.swift Sources/MenuBarViews.swift Tests/MacFanControlCoreTests/ModelsTests.swift
git commit -m "fix: filter ambiguous temperature sensors"
```
