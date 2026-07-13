# 风扇自动控制配置持久化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保存自定义曲线、当前选中配置和自动控制启用状态，并在应用重启后直接恢复自动控制。

**Architecture:** 在 `MacFanControlCore` 中建立独立、可测试的 `FanControlSettings` 状态模型，负责规范化活动配置和更新自定义曲线。`FanController` 只负责把完整状态读写到 `UserDefaults`、兼容旧数据，并根据 Helper 可用性启动实际控制。

**Tech Stack:** Swift 5.9、SwiftUI、Combine、Foundation `Codable`、`UserDefaults`、XCTest、Swift Package Manager。

## 全局约束

- 保持 macOS 13.0 最低版本和现有 Swift Package target 划分。
- 不新增第三方依赖。
- Helper 不可用时仍必须保存配置，但不得声称实际风扇控制成功。
- 兼容旧 `fanProfiles` 数据，迁移失败时不得删除旧数据。
- 不修改预设曲线内容、插值算法、界面布局或 Helper 架构。

## 文件结构

- 修改 `Core/Models.swift`：新增完整持久化状态、状态规范化和自定义曲线更新逻辑。
- 修改 `Tests/MacFanControlCoreTests/ModelsTests.swift`：覆盖状态往返、选中恢复、自定义配置稳定 ID 和无效状态规范化。
- 修改 `Sources/FanController.swift`：读写完整状态、迁移旧格式、恢复自动控制并提供自定义曲线保存入口。
- 修改 `Sources/FanCurveEditor.swift`：通过控制器入口保存曲线，不再直接修改配置数组。

---

### Task 1：可测试的完整配置状态

**Files:**
- Modify: `Core/Models.swift:218-290`
- Test: `Tests/MacFanControlCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `FanProfile`、`FanCurvePoint`
- Produces: `FanControlSettings.init(profiles:activeProfileID:isAutoControlEnabled:)`、`normalized()`、`updatingCustomProfile(curve:)`

- [ ] **Step 1：编写失败测试**

在 `ModelsTests` 中添加状态编码往返、无效活动 ID 规范化和自定义曲线稳定 ID 测试：

```swift
func testFanControlSettings_roundTripPreservesActiveCustomProfile() throws {
    let custom = FanProfile(
        name: "自定义",
        curve: [FanCurvePoint(temperature: 42, fanSpeedPercentage: 33)],
        isActive: true
    )
    let settings = FanControlSettings(
        profiles: [.silent, custom],
        activeProfileID: custom.id,
        isAutoControlEnabled: true
    )

    let decoded = try JSONDecoder().decode(
        FanControlSettings.self,
        from: JSONEncoder().encode(settings)
    )

    XCTAssertEqual(decoded, settings)
}

func testFanControlSettings_normalizedDisablesMissingActiveProfile() {
    let settings = FanControlSettings(
        profiles: [.balanced],
        activeProfileID: UUID(),
        isAutoControlEnabled: true
    ).normalized()

    XCTAssertNil(settings.activeProfileID)
    XCTAssertFalse(settings.isAutoControlEnabled)
    XCTAssertFalse(settings.profiles[0].isActive)
}

func testFanControlSettings_updatingCustomProfileKeepsStableID() {
    let original = FanProfile(
        name: "自定义",
        curve: [FanCurvePoint(temperature: 40, fanSpeedPercentage: 30)]
    )
    let settings = FanControlSettings(profiles: [.silent, original])
    let updated = settings.updatingCustomProfile(curve: [
        FanCurvePoint(temperature: 80, fanSpeedPercentage: 90),
        FanCurvePoint(temperature: 50, fanSpeedPercentage: 45),
    ])

    let custom = try! XCTUnwrap(updated.profiles.first { $0.name == "自定义" })
    XCTAssertEqual(custom.id, original.id)
    XCTAssertEqual(custom.curve.map(\.temperature), [50, 80])
    XCTAssertEqual(updated.activeProfileID, original.id)
    XCTAssertTrue(updated.isAutoControlEnabled)
    XCTAssertTrue(custom.isActive)
}
```

- [ ] **Step 2：运行测试确认 RED**

Run: `swift test --filter ModelsTests`

Expected: 编译失败，提示找不到 `FanControlSettings`。

- [ ] **Step 3：实现最小状态模型**

在 `Core/Models.swift` 添加：

```swift
public struct FanControlSettings: Codable, Equatable {
    public var profiles: [FanProfile]
    public var activeProfileID: UUID?
    public var isAutoControlEnabled: Bool

    public init(
        profiles: [FanProfile],
        activeProfileID: UUID? = nil,
        isAutoControlEnabled: Bool = false
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.isAutoControlEnabled = isAutoControlEnabled
    }

    public func normalized() -> FanControlSettings {
        var result = self
        let hasActiveProfile = result.activeProfileID.map { id in
            result.profiles.contains { $0.id == id }
        } ?? false

        if !result.isAutoControlEnabled || !hasActiveProfile {
            result.activeProfileID = nil
            result.isAutoControlEnabled = false
        }

        for index in result.profiles.indices {
            result.profiles[index].isActive =
                result.isAutoControlEnabled && result.profiles[index].id == result.activeProfileID
        }
        return result
    }

    public func updatingCustomProfile(curve: [FanCurvePoint]) -> FanControlSettings {
        var result = self
        let sortedCurve = curve.sorted { $0.temperature < $1.temperature }
        let customID: UUID

        if let index = result.profiles.firstIndex(where: { $0.name == "自定义" }) {
            customID = result.profiles[index].id
            result.profiles[index].curve = sortedCurve
        } else {
            let profile = FanProfile(name: "自定义", curve: sortedCurve)
            customID = profile.id
            result.profiles.append(profile)
        }

        result.activeProfileID = customID
        result.isAutoControlEnabled = true
        return result.normalized()
    }
}
```

- [ ] **Step 4：运行测试确认 GREEN**

Run: `swift test --filter ModelsTests`

Expected: 新增测试和原有模型测试全部通过。

- [ ] **Step 5：提交状态模型**

```bash
git add Core/Models.swift Tests/MacFanControlCoreTests/ModelsTests.swift
git commit -m "feat: add persistent fan control settings model"
```

### Task 2：持久化存储与控制器启动恢复

**Files:**
- Modify: `Sources/FanController.swift:52-65,152-170,182-197,579-655`
- Modify: `Core/Models.swift`
- Test: `Tests/MacFanControlCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `FanControlSettings.normalized()`、`FanControlSettings.updatingCustomProfile(curve:)`
- Produces: `FanControlSettingsStore.load()` / `save(_:)`、`saveCustomProfile(curve: [FanCurvePoint])`、完整状态恢复、幂等的 `startAutoControlIfAvailable()`

- [ ] **Step 1：编写旧格式迁移和完整状态存储的失败测试**

在 `ModelsTests` 使用独立 suite 的 `UserDefaults`，测试存储优先读取完整状态，并能迁移旧配置：

```swift
func testFanControlSettingsStore_migratesLegacyActiveProfile() throws {
    let suiteName = "ModelsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var legacy = FanProfile.performance
    legacy.isActive = true
    defaults.set(
        try JSONEncoder().encode([FanProfile.silent, legacy]),
        forKey: FanControlSettingsStore.legacyProfilesKey
    )

    let store = FanControlSettingsStore(defaults: defaults)
    let migrated = try XCTUnwrap(store.load())

    XCTAssertEqual(migrated.activeProfileID, legacy.id)
    XCTAssertTrue(migrated.isAutoControlEnabled)
    XCTAssertNotNil(defaults.data(forKey: FanControlSettingsStore.settingsKey))
}

func testFanControlSettingsStore_roundTripsCompleteState() throws {
    let suiteName = "ModelsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let active = FanProfile.silent
    let expected = FanControlSettings(
        profiles: [active],
        activeProfileID: active.id,
        isAutoControlEnabled: true
    ).normalized()
    let store = FanControlSettingsStore(defaults: defaults)

    try store.save(expected)

    XCTAssertEqual(try store.load(), expected)
}
```

- [ ] **Step 2：运行存储测试确认 RED**

Run: `swift test --filter FanControlSettingsStore`

Expected: 编译失败，提示找不到 `FanControlSettingsStore`。

- [ ] **Step 3：实现存储并接入控制器**

在 `MacFanControlCore` 中新增：

```swift
public struct FanControlSettingsStore {
    public static let settingsKey = "fanControlSettings"
    public static let legacyProfilesKey = "fanProfiles"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> FanControlSettings? {
        if let data = defaults.data(forKey: Self.settingsKey) {
            return try JSONDecoder().decode(FanControlSettings.self, from: data).normalized()
        }
        guard let legacyData = defaults.data(forKey: Self.legacyProfilesKey) else { return nil }
        let profiles = try JSONDecoder().decode([FanProfile].self, from: legacyData)
        let activeID = profiles.first(where: \.isActive)?.id
        let migrated = FanControlSettings(
            profiles: profiles,
            activeProfileID: activeID,
            isAutoControlEnabled: activeID != nil
        ).normalized()
        try save(migrated)
        return migrated
    }

    public func save(_ settings: FanControlSettings) throws {
        defaults.set(try JSONEncoder().encode(settings.normalized()), forKey: Self.settingsKey)
    }
}
```

在 `FanController` 中添加存储和恢复标记：

```swift
private let settingsStore = FanControlSettingsStore()
private var shouldRestoreAutoControl = false
```

将 `loadSettings()` 改为优先读取完整状态；没有新数据时读取旧数组并迁移。统一通过以下恢复逻辑赋值：

```swift
private func restore(_ settings: FanControlSettings) {
    let normalized = settings.normalized()
    profiles = normalized.profiles
    activeProfile = normalized.activeProfileID.flatMap { id in
        normalized.profiles.first { $0.id == id }
    }
    isAutoControlEnabled = normalized.isAutoControlEnabled && activeProfile != nil
    shouldRestoreAutoControl = isAutoControlEnabled
}
```

将 `saveSettings()` 改为整体保存：

```swift
private func saveSettings() {
    let settings = FanControlSettings(
        profiles: profiles,
        activeProfileID: activeProfile?.id,
        isAutoControlEnabled: isAutoControlEnabled
    ).normalized()

    do {
        try settingsStore.save(settings)
    } catch {
        lastError = .settingsSaveFailed(error.localizedDescription)
    }
}
```

- [ ] **Step 4：让自动控制恢复与 Helper 可用性解耦**

提取幂等启动方法：

```swift
private func startAutoControlIfAvailable() {
    guard isAutoControlEnabled, activeProfile != nil, canControlFans else { return }
    autoControlTimer?.invalidate()
    autoControlTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
            guard let self, !self.isApplyingAutoControl else { return }
            self.applyAutoControl()
        }
    }
    shouldRestoreAutoControl = false
    applyAutoControl()
}
```

在 `startMonitoring()` 和 Helper 安装成功路径调用该方法。修改 `enableAutoControl(profile:)`：先更新选中状态并保存，再判断控制能力；控制不可用时保留已保存状态并设置错误。

新增自定义保存入口：

```swift
func saveCustomProfile(curve: [FanCurvePoint]) {
    let settings = FanControlSettings(
        profiles: profiles,
        activeProfileID: activeProfile?.id,
        isAutoControlEnabled: isAutoControlEnabled
    ).updatingCustomProfile(curve: curve)

    restore(settings)
    saveSettings()
    startAutoControlIfAvailable()
    if !canControlFans {
        lastError = .fanControlUnavailable
    }
}
```

- [ ] **Step 5：构建并运行完整测试**

Run: `swift test`

Expected: 应用、Helper 和测试 target 构建成功，所有测试通过。

- [ ] **Step 6：提交控制器持久化**

```bash
git add Sources/FanController.swift Tests/MacFanControlCoreTests/ModelsTests.swift
git commit -m "fix: restore automatic fan control settings"
```

### Task 3：曲线编辑器使用独立保存入口

**Files:**
- Modify: `Sources/FanCurveEditor.swift:285-303`

**Interfaces:**
- Consumes: `FanController.saveCustomProfile(curve:)`
- Produces: “完成”按钮始终保存排序后的自定义曲线，并在能力可用时立即控制风扇

- [ ] **Step 1：确认旧路径复现条件**

检查现有 `saveAndDismiss()`：它先修改 `profiles`，随后调用会因 `canControlFans == false` 提前返回的 `enableAutoControl(profile:)`，因此没有调用 `saveSettings()`。

- [ ] **Step 2：替换为控制器保存入口**

将 `saveAndDismiss()` 改为：

```swift
private func saveAndDismiss() {
    fanController.saveCustomProfile(curve: curvePoints)
    onDismiss?()
}
```

- [ ] **Step 3：运行完整验证**

Run: `swift test`

Expected: 全部测试通过，`MacFanControl` executable target 构建成功。

Run: `git diff --check`

Expected: 无输出。

- [ ] **Step 4：检查最终变更范围**

Run: `git status --short && git diff --stat HEAD~2`

Expected: 仅包含计划中的 Core、Tests、FanController 和 FanCurveEditor 变更，不包含构建产物。

- [ ] **Step 5：提交编辑器接入**

```bash
git add Sources/FanCurveEditor.swift
git commit -m "fix: persist custom fan curves independently"
```
