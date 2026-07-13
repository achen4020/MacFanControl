# MacFanControl 区域截图与编辑功能实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 MacFanControl 增加默认且可配置的全局区域截图快捷键、单显示器任意区域框选、常用图片标注、保存以及剪贴板复制粘贴能力。

**Architecture:** 新增可独立测试的 `ScreenshotKit` 库，承载截图几何、编辑模型、历史、快捷键配置、屏幕捕获和图片渲染；主应用的 AppKit 协调器负责全局输入、遮罩窗口和编辑窗口，SwiftUI 负责设置与编辑器界面。截图模块不依赖 `FanController`，只在用户触发时工作。

**Tech Stack:** Swift 5.9、SwiftUI、AppKit、CoreGraphics、Carbon Hot Keys、XCTest、Swift Package Manager。

---

## 文件结构

- Create `ScreenshotKit/ScreenshotModels.swift`：快捷键、选区、颜色、工具和标注模型。
- Create `ScreenshotKit/ScreenshotGeometry.swift`：拖动矩形与 Retina 坐标换算。
- Create `ScreenshotKit/ScreenshotHistory.swift`：编辑快照和撤销重做。
- Create `ScreenshotKit/ScreenshotHotKeyStore.swift`：快捷键持久化和验证。
- Create `ScreenshotKit/ScreenCaptureService.swift`：权限、显示器定位和捕获协议。
- Create `ScreenshotKit/ScreenshotRenderer.swift`：裁剪、马赛克、标注合成和编码。
- Create `Sources/Screenshot/GlobalHotKeyManager.swift`：Carbon 全局快捷键生命周期。
- Create `Sources/Screenshot/ScreenCaptureCoordinator.swift`：截图会话状态机。
- Create `Sources/Screenshot/SelectionOverlayController.swift`：遮罩窗口生命周期。
- Create `Sources/Screenshot/SelectionOverlayView.swift`：选区、尺寸和放大镜绘制。
- Create `Sources/Screenshot/ScreenshotEditorViewModel.swift`：编辑状态和动作。
- Create `Sources/Screenshot/ScreenshotCanvasView.swift`：底图、标注、绘制和选择。
- Create `Sources/Screenshot/ScreenshotEditorView.swift`：编辑器工具栏。
- Create `Sources/Screenshot/ScreenshotEditorWindowController.swift`：编辑窗口和关闭确认。
- Create `Sources/Screenshot/ScreenshotHotKeyRecorder.swift`：快捷键录入控件。
- Create `Tests/ScreenshotKitTests/*.swift`：几何、历史、快捷键、渲染和会话测试。
- Modify `Package.swift`、`Sources/MacFanControlApp.swift`、`Sources/MenuBarViews.swift`、`Sources/SettingsViews.swift`、`Sources/Info.plist`、`build-app.sh`。

## Task 1：建立 ScreenshotKit 目标和基础模型

**Files:**
- Modify: `Package.swift`
- Create: `ScreenshotKit/ScreenshotModels.swift`
- Create: `Tests/ScreenshotKitTests/ScreenshotGeometryTests.swift`

- [ ] **Step 1：添加失败测试**

```swift
import XCTest
@testable import ScreenshotKit

final class ScreenshotGeometryTests: XCTestCase {
    func testDefaultHotKeyIsControlShiftA() {
        XCTAssertEqual(ScreenshotHotKey.default.keyCode, 0)
        XCTAssertEqual(ScreenshotHotKey.default.modifiers, [.control, .shift])
    }

    func testSelectionRequiresFourPoints() {
        XCTAssertNil(ScreenshotSelection(start: .zero, end: CGPoint(x: 3, y: 8)))
        XCTAssertNotNil(ScreenshotSelection(start: .zero, end: CGPoint(x: 4, y: 4)))
    }
}
```

- [ ] **Step 2：声明目标并运行测试确认失败**

在 `Package.swift` 增加：

```swift
.target(name: "ScreenshotKit", path: "ScreenshotKit",
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")]),
.testTarget(name: "ScreenshotKitTests", dependencies: ["ScreenshotKit"],
            path: "Tests/ScreenshotKitTests")
```

主应用依赖改为 `dependencies: ["SMCKit", "MacFanControlCore", "ScreenshotKit"]`。

Run: `swift test --filter ScreenshotGeometryTests`

Expected: FAIL，提示 `ScreenshotHotKey` 和 `ScreenshotSelection` 未定义。

- [ ] **Step 3：实现最小模型**

```swift
import Foundation
import CoreGraphics

public struct ScreenshotModifier: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

public struct ScreenshotHotKey: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ScreenshotModifier
    public init(keyCode: UInt32, modifiers: ScreenshotModifier) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    public static let `default` = Self(keyCode: 0, modifiers: [.control, .shift])
}

public struct ScreenshotSelection: Equatable, Sendable {
    public let rect: CGRect
    public init?(start: CGPoint, end: CGPoint, minimumSize: CGFloat = 4) {
        let value = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard value.width >= minimumSize, value.height >= minimumSize else { return nil }
        rect = value
    }
}

public enum ScreenshotTool: String, CaseIterable, Sendable {
    case select, crop, rectangle, arrow, pen, text, mosaic
}
```

- [ ] **Step 4：验证并提交**

Run: `swift test --filter ScreenshotGeometryTests`

Expected: 2 tests PASS。

```bash
git add Package.swift ScreenshotKit/ScreenshotModels.swift Tests/ScreenshotKitTests/ScreenshotGeometryTests.swift
git commit -m "feat: add screenshot core models"
```

## Task 2：实现多显示器与 Retina 坐标换算

**Files:**
- Create: `ScreenshotKit/ScreenshotGeometry.swift`
- Modify: `Tests/ScreenshotKitTests/ScreenshotGeometryTests.swift`

- [ ] **Step 1：添加反向拖动、Y 轴翻转、缩放和边界测试**

```swift
func testReverseDragAndRetinaMapping() {
    XCTAssertEqual(
        ScreenshotSelection(start: CGPoint(x: 90, y: 70), end: CGPoint(x: 10, y: 20))?.rect,
        CGRect(x: 10, y: 20, width: 80, height: 50)
    )
    let geometry = DisplayGeometry(frameInPoints: CGRect(x: 1440, y: 100, width: 1000, height: 800),
                                   pixelSize: CGSize(width: 2000, height: 1600))
    XCTAssertEqual(geometry.pixelRect(forLocalSelection: CGRect(x: 100, y: 200, width: 300, height: 100)),
                   CGRect(x: 200, y: 1000, width: 600, height: 200))
}
```

- [ ] **Step 2：运行测试确认 `DisplayGeometry` 缺失**

Run: `swift test --filter ScreenshotGeometryTests`

Expected: FAIL with `cannot find DisplayGeometry in scope`。

- [ ] **Step 3：实现坐标映射**

```swift
public struct DisplayGeometry: Equatable, Sendable {
    public let frameInPoints: CGRect
    public let pixelSize: CGSize

    public init(frameInPoints: CGRect, pixelSize: CGSize) {
        self.frameInPoints = frameInPoints
        self.pixelSize = pixelSize
    }

    public func pixelRect(forLocalSelection selection: CGRect) -> CGRect {
        let sx = pixelSize.width / frameInPoints.width
        let sy = pixelSize.height / frameInPoints.height
        return CGRect(x: selection.minX * sx,
                      y: pixelSize.height - selection.maxY * sy,
                      width: selection.width * sx,
                      height: selection.height * sy)
            .integral.intersection(CGRect(origin: .zero, size: pixelSize))
    }
}
```

- [ ] **Step 4：验证并提交**

Run: `swift test --filter ScreenshotGeometryTests`

Expected: PASS。

```bash
git add ScreenshotKit/ScreenshotGeometry.swift Tests/ScreenshotKitTests/ScreenshotGeometryTests.swift
git commit -m "feat: add screenshot coordinate mapping"
```

## Task 3：实现标注模型和撤销重做

**Files:**
- Modify: `ScreenshotKit/ScreenshotModels.swift`
- Create: `ScreenshotKit/ScreenshotHistory.swift`
- Create: `Tests/ScreenshotKitTests/ScreenshotHistoryTests.swift`

- [ ] **Step 1：添加历史失败测试**

```swift
func testUndoRedoAndNewEditClearsRedo() {
    let base = ScreenshotDocumentState(cropRect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var history = ScreenshotHistory(initial: base)
    let item = ScreenshotAnnotation.rectangle(id: UUID(), rect: CGRect(x: 10, y: 10, width: 20, height: 20), style: .default)
    history.apply(base.adding(item))
    history.undo()
    XCTAssertTrue(history.current.annotations.isEmpty)
    history.redo()
    XCTAssertEqual(history.current.annotations.count, 1)
    history.undo()
    history.apply(base.withCropRect(CGRect(x: 0, y: 0, width: 80, height: 80)))
    XCTAssertFalse(history.canRedo)
}
```

- [ ] **Step 2：运行测试确认模型缺失**

Run: `swift test --filter ScreenshotHistoryTests`

Expected: FAIL。

- [ ] **Step 3：实现模型和历史**

```swift
public struct ScreenshotColor: Equatable, Sendable {
    public var red, green, blue, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let red = Self(red: 1, green: 0.23, blue: 0.19, alpha: 1)
}
public struct AnnotationStyle: Equatable, Sendable {
    public var color: ScreenshotColor
    public var lineWidth, opacity: CGFloat
    public init(color: ScreenshotColor, lineWidth: CGFloat, opacity: CGFloat) {
        self.color = color; self.lineWidth = lineWidth; self.opacity = opacity
    }
    public static let `default` = Self(color: .red, lineWidth: 5, opacity: 1)
}
public enum ScreenshotAnnotation: Equatable, Sendable {
    case rectangle(id: UUID, rect: CGRect, style: AnnotationStyle)
    case arrow(id: UUID, start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case pen(id: UUID, points: [CGPoint], style: AnnotationStyle)
    case text(id: UUID, rect: CGRect, value: String, fontSize: CGFloat, style: AnnotationStyle)
    case mosaic(id: UUID, rect: CGRect, blockSize: CGFloat)
}
public struct ScreenshotDocumentState: Equatable, Sendable {
    public var cropRect: CGRect
    public var annotations: [ScreenshotAnnotation] = []
    public init(cropRect: CGRect, annotations: [ScreenshotAnnotation] = []) {
        self.cropRect = cropRect; self.annotations = annotations
    }
    public func adding(_ value: ScreenshotAnnotation) -> Self { var c = self; c.annotations.append(value); return c }
    public func withCropRect(_ value: CGRect) -> Self { var c = self; c.cropRect = value; return c }
}
public struct ScreenshotHistory: Sendable {
    public private(set) var current: ScreenshotDocumentState
    private var undoStack: [ScreenshotDocumentState] = []
    private var redoStack: [ScreenshotDocumentState] = []
    public init(initial: ScreenshotDocumentState) { current = initial }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public mutating func apply(_ next: ScreenshotDocumentState) {
        guard next != current else { return }; undoStack.append(current); current = next; redoStack.removeAll()
    }
    public mutating func undo() { guard let v = undoStack.popLast() else { return }; redoStack.append(current); current = v }
    public mutating func redo() { guard let v = redoStack.popLast() else { return }; undoStack.append(current); current = v }
}
```

- [ ] **Step 4：验证并提交**

Run: `swift test --filter ScreenshotHistoryTests`

Expected: PASS。

```bash
git add ScreenshotKit/ScreenshotModels.swift ScreenshotKit/ScreenshotHistory.swift Tests/ScreenshotKitTests/ScreenshotHistoryTests.swift
git commit -m "feat: add screenshot annotations and history"
```

## Task 4：实现快捷键持久化和 Carbon 注册

**Files:**
- Create: `ScreenshotKit/ScreenshotHotKeyStore.swift`
- Create: `Sources/Screenshot/GlobalHotKeyManager.swift`
- Create: `Tests/ScreenshotKitTests/ScreenshotHotKeyStoreTests.swift`

- [ ] **Step 1：测试自定义值往返和无修饰键拒绝**

```swift
func testStoreRoundTripAndValidation() throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = ScreenshotHotKeyStore(defaults: defaults)
    let value = ScreenshotHotKey(keyCode: 1, modifiers: [.command, .shift])
    try store.save(value)
    XCTAssertEqual(store.load(), value)
    XCTAssertThrowsError(try store.save(.init(keyCode: 0, modifiers: [])))
}
```

- [ ] **Step 2：运行确认失败，再实现 JSON/UserDefaults 存储**

```swift
public enum ScreenshotHotKeyError: LocalizedError {
    case missingModifier
    case registrationFailed
    public var errorDescription: String? {
        switch self {
        case .missingModifier: return "快捷键必须包含至少一个修饰键"
        case .registrationFailed: return "快捷键已被系统或其他应用占用"
        }
    }
}

public final class ScreenshotHotKeyStore {
    private let defaults: UserDefaults
    private let key = "screenshot.hotKey"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> ScreenshotHotKey {
        guard let data = defaults.data(forKey: key), let v = try? JSONDecoder().decode(ScreenshotHotKey.self, from: data)
        else { return .default }; return v
    }
    public func save(_ value: ScreenshotHotKey) throws {
        guard !value.modifiers.isEmpty else { throw ScreenshotHotKeyError.missingModifier }
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
```

Run: `swift test --filter ScreenshotHotKeyStoreTests`

Expected: PASS。

- [ ] **Step 3：实现 Carbon 管理器**

`GlobalHotKeyManager` 使用 `RegisterEventHotKey` 和 `InstallEventHandler`。更新快捷键时必须先注册候选值，成功后再 `UnregisterEventHotKey` 旧值；冲突抛出 `ScreenshotHotKeyError.registrationFailed`，不得覆盖持久化旧值。修饰键映射到 `controlKey`、`shiftKey`、`optionKey`、`cmdKey`。事件回调只执行 `Task { @MainActor in onTrigger?() }`，不做截图工作。

- [ ] **Step 4：构建并提交**

Run: `swift build && swift test --filter ScreenshotHotKeyStoreTests`

Expected: PASS。

```bash
git add ScreenshotKit/ScreenshotHotKeyStore.swift Sources/Screenshot/GlobalHotKeyManager.swift Tests/ScreenshotKitTests/ScreenshotHotKeyStoreTests.swift
git commit -m "feat: add configurable screenshot hotkey"
```

## Task 5：实现屏幕权限、显示器定位和截图服务

**Files:**
- Create: `ScreenshotKit/ScreenCaptureService.swift`
- Create: `Tests/ScreenshotKitTests/ScreenCaptureSessionTests.swift`

- [ ] **Step 1：添加会话防重入测试**

```swift
func testSessionRejectsDuplicateStartAndResets() {
    var state = ScreenCaptureSessionState()
    XCTAssertTrue(state.begin())
    XCTAssertFalse(state.begin())
    state.finish()
    XCTAssertTrue(state.begin())
}
```

- [ ] **Step 2：实现状态、协议和系统捕获器**

```swift
public struct CapturedDisplay {
    public let image: CGImage
    public let displayID: CGDirectDisplayID
    public let geometry: DisplayGeometry
}
public protocol ScreenCaptureProviding {
    func hasPermission() -> Bool
    func requestPermission() -> Bool
    func captureDisplay(containing point: CGPoint) throws -> CapturedDisplay
}
public struct ScreenCaptureSessionState {
    public private(set) var isActive = false
    public mutating func begin() -> Bool { guard !isActive else { return false }; isActive = true; return true }
    public mutating func finish() { isActive = false }
}
```

系统实现使用 `CGPreflightScreenCaptureAccess`、`CGRequestScreenCaptureAccess`、`NSScreen.screens.first(where: { $0.frame.contains(point) })`、`NSScreenNumber` 和 `CGDisplayCreateImage`。捕获失败分别抛出 `permissionDenied`、`noDisplay`、`captureFailed`。

- [ ] **Step 3：验证并提交**

Run: `swift test --filter ScreenCaptureSessionTests`

Expected: PASS。

```bash
git add ScreenshotKit/ScreenCaptureService.swift Tests/ScreenshotKitTests/ScreenCaptureSessionTests.swift
git commit -m "feat: add screen capture service"
```

## Task 6：实现截图遮罩窗口

**Files:**
- Create: `Sources/Screenshot/SelectionOverlayView.swift`
- Create: `Sources/Screenshot/SelectionOverlayController.swift`

- [ ] **Step 1：实现视图事件接口**

`SelectionOverlayView` 持有本次 `CGImage`，公开 `onComplete: (ScreenshotSelection) -> Void` 和 `onCancel: () -> Void`。`mouseDown` 保存起点，`mouseDragged` 更新终点，`mouseUp` 使用 `ScreenshotSelection` 校验最小尺寸；Esc（keyCode 53）和右键调用取消。

- [ ] **Step 2：实现绘制顺序**

`draw(_:)` 必须按“完整截图 → 52% 黑色遮罩 → 选区内重新绘制截图 → 2pt 白色边框 → 逻辑尺寸标签 → 120pt 放大镜”绘制。放大镜截取光标附近 `15 × 15` 点，关闭插值放大并绘制中心十字，不缓存完整位图副本。

- [ ] **Step 3：实现无边框窗口**

```swift
let window = NSWindow(contentRect: screenFrame, styleMask: .borderless,
                      backing: .buffered, defer: false)
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
window.backgroundColor = .clear
window.isOpaque = false
```

完成或取消时先把回调设为 nil，再把 `contentView` 设为 nil、`orderOut(nil)`、清空窗口引用，避免闭包环。

- [ ] **Step 4：构建并提交**

Run: `swift build`

Expected: PASS。

```bash
git add Sources/Screenshot/SelectionOverlayView.swift Sources/Screenshot/SelectionOverlayController.swift
git commit -m "feat: add screenshot selection overlay"
```

## Task 7：实现截图协调器和权限提示

**Files:**
- Create: `Sources/Screenshot/ScreenCaptureCoordinator.swift`

- [ ] **Step 1：组装可注入依赖和会话状态**

```swift
@MainActor
final class ScreenCaptureCoordinator: ObservableObject {
    static let shared = ScreenCaptureCoordinator()
    @Published private(set) var lastError: String?
    private let provider: ScreenCaptureProviding
    private let overlay = SelectionOverlayController()
    private var session = ScreenCaptureSessionState()
}
```

- [ ] **Step 2：实现完整流程**

`startCapture()` 依次执行：`session.begin()`、权限预检、鼠标所在显示器捕获、遮罩显示。回调中将 `selection.rect` 交给 `DisplayGeometry.pixelRect`，调用 `CGImage.cropping(to:)`，关闭遮罩后执行 `ScreenshotEditorWindowController.shared.open(image:)`，所有成功、取消和错误路径都用 `defer { session.finish() }` 恢复空闲。

- [ ] **Step 3：实现权限提示**

未授权时用 `NSAlert` 说明用途，按钮“打开系统设置”使用：

```swift
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
```

取消不写入 `lastError`；捕获失败显示本地化错误。

- [ ] **Step 4：构建并提交**

Run: `swift build`

Expected: PASS。

```bash
git add Sources/Screenshot/ScreenCaptureCoordinator.swift
git commit -m "feat: coordinate screenshot capture sessions"
```

## Task 8：实现编辑器窗口、画布和基础标注

**Files:**
- Create: `Sources/Screenshot/ScreenshotEditorViewModel.swift`
- Create: `Sources/Screenshot/ScreenshotCanvasView.swift`
- Create: `Sources/Screenshot/ScreenshotEditorView.swift`
- Create: `Sources/Screenshot/ScreenshotEditorWindowController.swift`

- [ ] **Step 1：实现 ViewModel**

`ScreenshotEditorViewModel` 持有不可变 `CGImage`、当前 `ScreenshotTool`、`AnnotationStyle`、`ScreenshotHistory`、当前选择 ID、错误消息和 `isDirty`。`apply` 标记脏，`undo/redo` 调用历史并刷新画布。

- [ ] **Step 2：实现画布坐标变换**

`ScreenshotCanvasView` 用 `NSViewRepresentable` 包装 AppKit 画布。画布以 aspect-fit 显示当前 `cropRect`；鼠标点通过以下公式进入图片文档坐标：

```swift
CGPoint(x: crop.minX + (point.x - imageRect.minX) * crop.width / imageRect.width,
        y: crop.minY + (point.y - imageRect.minY) * crop.height / imageRect.height)
```

- [ ] **Step 3：实现矩形、箭头、画笔和文字**

鼠标松开时生成一条标注并只调用一次 `history.apply`。画笔一次拖动合并为一个点数组；文字点击后显示 `NSTextField`，空字符串取消。选择工具按数组倒序命中，显示八个缩放手柄；移动、缩放、删除在动作结束时形成一条历史记录。

- [ ] **Step 4：实现 SwiftUI 工具栏和窗口**

顶部固定：选择、裁剪、矩形、箭头、画笔、文字、马赛克、撤销、重做；底部绑定颜色、线宽、透明度；右上角固定取消、复制、保存。窗口初始 `960 × 680`、可缩放。窗口控制器用 `[NSWindow: ScreenshotEditorViewModel]` 支持多个文档，关闭脏文档时确认；关闭后解除内容控制器和模型引用。

- [ ] **Step 5：构建并提交**

Run: `swift build`

Expected: PASS。

```bash
git add Sources/Screenshot/ScreenshotEditorViewModel.swift Sources/Screenshot/ScreenshotCanvasView.swift Sources/Screenshot/ScreenshotEditorView.swift Sources/Screenshot/ScreenshotEditorWindowController.swift
git commit -m "feat: add screenshot annotation editor"
```

## Task 9：实现裁剪、马赛克、最终渲染和编码

**Files:**
- Create: `ScreenshotKit/ScreenshotRenderer.swift`
- Create: `Tests/ScreenshotKitTests/ScreenshotRendererTests.swift`
- Modify: `Sources/Screenshot/ScreenshotCanvasView.swift`

- [ ] **Step 1：添加裁剪尺寸和 PNG 签名测试**

```swift
func testCropAndPNGEncoding() throws {
    let image = makeSolidImage(width: 100, height: 80)
    let state = ScreenshotDocumentState(cropRect: CGRect(x: 10, y: 20, width: 40, height: 30))
    let result = try ScreenshotRenderer().render(image: image, state: state)
    XCTAssertEqual(result.width, 40)
    XCTAssertEqual(result.height, 30)
    XCTAssertEqual(Array(try ScreenshotRenderer().encode(result, format: .png).prefix(8)),
                   [137, 80, 78, 71, 13, 10, 26, 10])
}
```

- [ ] **Step 2：实现渲染器**

渲染器创建 crop 尺寸的 RGBA `CGContext`，绘制裁剪底图，把上下文平移 `-crop.origin` 后按数组顺序绘制标注。矩形、箭头、画笔使用 CoreGraphics path；文字使用 CoreText；马赛克将目标区域缩小到 `ceil(width/blockSize) × ceil(height/blockSize)` 后关闭插值放回。所有标注裁剪在 crop 内并应用 opacity。

- [ ] **Step 3：实现 PNG/JPEG 编码**

先定义：

```swift
public enum ScreenshotImageFormat { case png, jpeg(quality: CGFloat) }
public enum ScreenshotOutputError: LocalizedError {
    case encodingFailed
    public var errorDescription: String? { "图片编码失败" }
}
```

使用 `CGImageDestination`，PNG 类型 `public.png`；JPEG 类型 `public.jpeg` 并传 `kCGImageDestinationLossyCompressionQuality`。编码失败抛出 `ScreenshotOutputError.encodingFailed`。

- [ ] **Step 4：画布接入裁剪和马赛克**

裁剪矩形必须限制在当前 crop 内，并作为一次历史命令；标注仍使用原始图片坐标，画布与渲染器都减去 crop 原点，因此裁剪后坐标同步且不丢精度。马赛克预览复用与渲染器相同的 blockSize 算法。

- [ ] **Step 5：验证并提交**

Run: `swift test --filter ScreenshotRendererTests && swift test`

Expected: PASS。

```bash
git add ScreenshotKit/ScreenshotRenderer.swift Tests/ScreenshotKitTests/ScreenshotRendererTests.swift Sources/Screenshot/ScreenshotCanvasView.swift
git commit -m "feat: add screenshot crop and rendering"
```

## Task 10：实现保存、复制和剪贴板粘贴

**Files:**
- Modify: `Sources/Screenshot/ScreenshotEditorViewModel.swift`
- Modify: `Sources/Screenshot/ScreenshotEditorView.swift`
- Modify: `Sources/Screenshot/ScreenshotEditorWindowController.swift`

- [ ] **Step 1：实现复制**

`copyToPasteboard()` 渲染最终图，创建 `NSBitmapImageRep`，执行 `NSPasteboard.general.clearContents()` 和 `writeObjects`。成功后 `isDirty = false`；失败保留文档并显示错误。

- [ ] **Step 2：实现保存面板**

`NSSavePanel` 默认文件名 `截图-YYYY-MM-dd-HHmmss.png`，允许 `png`、`jpg`、`jpeg`。根据最终扩展名选择 PNG 或质量 0.9 的 JPEG。取消不报错、不关闭；写入成功清除脏标记。

- [ ] **Step 3：实现 Command + V**

窗口处理 `paste:`，按 PNG、TIFF、`NSImage(pasteboard:)` 顺序读取。无图片报“剪贴板中没有可用图片”；宽高乘积超过 `100_000_000` 报“图片超过一亿像素”。脏文档先确认，确认后打开新编辑窗口，原窗口不被覆盖。

- [ ] **Step 4：构建并提交**

Run: `swift build && swift test`

Expected: PASS。

```bash
git add Sources/Screenshot/ScreenshotEditorViewModel.swift Sources/Screenshot/ScreenshotEditorView.swift Sources/Screenshot/ScreenshotEditorWindowController.swift
git commit -m "feat: add screenshot save and clipboard actions"
```

## Task 11：接入应用、菜单、设置和用途说明

**Files:**
- Modify: `Sources/MacFanControlApp.swift`
- Modify: `Sources/MenuBarViews.swift`
- Modify: `Sources/SettingsViews.swift`
- Create: `Sources/Screenshot/ScreenshotHotKeyRecorder.swift`
- Modify: `Sources/Info.plist`
- Modify: `build-app.sh`

- [ ] **Step 1：应用启动注册快捷键**

在 `MacFanControlApp.init()` 保留 `controller.startMonitoring()`，另外设置 `GlobalHotKeyManager.shared.onTrigger = { ScreenCaptureCoordinator.shared.startCapture() }` 并调用 `start()`；失败交给协调器显示，不影响风扇监控。

- [ ] **Step 2：菜单栏增加截图按钮**

```swift
Button { ScreenCaptureCoordinator.shared.startCapture() } label: {
    Label("区域截图", systemImage: "camera.viewfinder")
    Text(GlobalHotKeyManager.shared.displayText).font(.caption2).foregroundColor(.secondary)
}
```

- [ ] **Step 3：实现快捷键录入和截图设置页**

`ScreenshotHotKeyRecorder` 使用 first-responder NSView 记录下一次 `keyDown`，只接受包含 control/shift/option/command 的组合，Esc 取消。`ScreenshotSettingsView` 展示当前组合、恢复默认、权限状态和系统设置入口。把设置窗口高度从 300 调整为 360，并新增“截图”标签页。

- [ ] **Step 4：同步用途说明**

在 `Sources/Info.plist` 和 `build-app.sh` 生成的 plist 同时加入：

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>用于通过快捷键选择并编辑屏幕区域截图。</string>
```

- [ ] **Step 5：验证并提交**

Run: `swift test && swift build -c release && bash -n build-app.sh && git diff --check`

Expected: 全部退出码 0。

```bash
git add Sources/MacFanControlApp.swift Sources/MenuBarViews.swift Sources/SettingsViews.swift Sources/Screenshot/ScreenshotHotKeyRecorder.swift Sources/Info.plist build-app.sh
git commit -m "feat: integrate screenshot tools into app"
```

## Task 12：端到端验证、资源检查和 Release 应用

**Files:**
- Modify only when verification exposes a concrete defect.

- [ ] **Step 1：执行完整自动验证**

Run: `swift test && git diff --check`

Expected: `MacFanControlCoreTests` 与 `ScreenshotKitTests` 全部通过，无空白错误。

- [ ] **Step 2：生成并验证应用包**

Run: `./build-app.sh`，运行询问输入 `n`，然后：

```bash
plutil -lint MacFanControl.app/Contents/Info.plist
codesign --verify --deep --strict MacFanControl.app
file MacFanControl.app/Contents/MacOS/MacFanControl
```

Expected: plist `OK`，签名校验退出码 0，主程序为 arm64 Mach-O。

- [ ] **Step 3：手工验收功能**

依次验证：权限拒绝和授权；默认/自定义/冲突/恢复快捷键；当前显示器正反向框选；Esc、右键和小选区取消；重复触发无多遮罩；六种编辑工具；选择、移动、缩放、删除；撤销重做；PNG/JPEG 保存；复制到预览、微信或文档；Command+V 打开剪贴板图片；截图期间风扇监控和自动控制持续运行。

- [ ] **Step 4：检查资源释放**

记录应用 PID，执行：

```bash
PID=$(pgrep -x MacFanControl | head -1)
ps -p "$PID" -o pid,rss,%cpu,command
```

连续完成并关闭 20 次编辑会话，等待 15 秒后再次检查。Expected: CPU 回到空闲基线，RSS 不随关闭次数线性增长。若异常，用 Instruments Allocations 定位 `NSWindow`、`CGImage`、`ScreenshotEditorViewModel` 和遮罩闭包。

- [ ] **Step 5：确认最终状态**

若手工验收暴露缺陷，返回对应 Task 增加失败测试、实现最小修复并使用该 Task 列出的文件级 `git add` 命令提交；修复后重新执行 Task 12 全部步骤。

最后运行 `git status --short`，Expected: 空输出。最终应用位于项目根目录 `MacFanControl.app`。
