# Mac 风扇控制 (MacFanControl)

一个支持 Apple Silicon (M1/M2/M3/M4) 的 macOS 风扇监控和控制工具。

## 功能特点

- 实时温度监测 — 通过 HID 传感器显示 CPU 各核心温度
- 风扇转速显示 — 实时显示风扇 RPM 和百分比
- 手动控制 — 通过滑块自定义风扇转速
- 自动控制 — 根据温度曲线自动调节转速
- 预设配置 — 静音/平衡/性能三种模式 + 自定义曲线编辑
- 系统监控 — CPU 使用率、内存占用实时显示
- 高温通知 — 温度超过阈值时发送系统通知
- 开机启动 — 支持设置登录时自动启动
- 菜单栏应用 — 在状态栏显示温度，不占用 Dock

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Apple Silicon (M1/M2/M3/M4) 或 Intel Mac
- Xcode 15+ / Swift 5.9+ (用于编译)

## 架构说明

```
┌─────────────────────────────────────────────────────────────────┐
│                      MacFanControl.app                          │
│                    (SwiftUI 菜单栏应用)                          │
│                                                                  │
│  MacFanControlCore ─ 数据模型、协议、错误类型                     │
│  FanController ──── 核心控制逻辑 (依赖注入)                      │
│  TemperatureReader ─ IOHIDEventSystemClient 温度读取             │
│  SystemMonitor ──── CPU/内存监控                                 │
│  SMCHelperClient ── Unix Socket 客户端                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Unix Socket (/var/run/...)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    MacFanControlHelper                           │
│                  (特权辅助程序 - root 权限)                       │
│                                                                  │
│  • 写入 Ftst=1 解锁 Apple Silicon 风扇控制                       │
│  • 设置风扇模式和目标转速                                         │
│  • 读取 SMC 温度传感器                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ IOKit / AppleSMC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    System Management Controller                  │
│                         (硬件 SMC 芯片)                          │
└─────────────────────────────────────────────────────────────────┘
```

### 模块依赖

```
MacFanControlCoreTests ──▶ MacFanControlCore (纯数据模型/协议)
MacFanControl (主应用) ───▶ MacFanControlCore + SMCKit
MacFanControlHelper ──────▶ SMCKit (共享 SMC 访问层)
```

## 安装和运行

### 编译

```bash
swift build
```

### 安装 Helper (需要管理员权限)

```bash
sudo ./install-helper.sh
```

Helper 会安装到 `/Library/PrivilegedHelperTools/` 并注册为 launchd 系统服务。

### 运行

```bash
.build/debug/MacFanControl
```

### 卸载 Helper

```bash
sudo ./uninstall-helper.sh
```

## 项目结构

```
MacFanControl/
├── Package.swift                          # SPM 包配置 (4 targets + 1 test)
├── README.md
├── Core/
│   └── Models.swift                       # 数据模型、协议、错误类型 (public)
├── Shared/
│   └── SMC.swift                          # SMCManager (app 和 helper 共享)
├── Sources/
│   ├── MacFanControlApp.swift             # @main 入口 + 窗口控制器
│   ├── FanController.swift                # 核心控制逻辑 (依赖注入)
│   ├── MenuBarViews.swift                 # 菜单栏 UI 组件
│   ├── FanCurveEditor.swift               # 风扇曲线编辑器
│   ├── SettingsViews.swift                # 设置视图
│   ├── TemperatureReader.swift            # HID 温度传感器读取
│   ├── SystemMonitor.swift                # CPU/内存监控
│   └── SMCHelperClient.swift              # Unix Socket 通信客户端
├── Helper/
│   ├── main.swift                         # Helper daemon 入口
│   └── HelperProtocol.swift               # 通信协议定义
└── Tests/
    └── MacFanControlCoreTests/
        └── ModelsTests.swift              # 24 个单元测试
```

## 测试

```bash
swift test
```

覆盖范围：
- 风扇曲线插值算法（边界值、中间值、空曲线）
- 温度警告级别阈值判断
- 传感器名称中英文映射
- 风扇速度百分比计算
- 错误类型描述文本
- 预设配置文件完整性

## 技术说明

### Apple Silicon 温度读取

通过 `IOHIDEventSystemClient` 私有 API（dlsym 动态加载）读取 HID 温度传感器：
- `PMU tdie*` — CPU 性能核心温度
- `PMU2 tdie*` — CPU 效率核心温度
- `PMU tdev*` — 芯片区域温度
- `NAND CH0 temp` — SSD 温度

### Apple Silicon 风扇控制

需要特权 Helper daemon 通过 SMC 控制：

1. 写入 `Ftst = 1` 进入诊断模式
2. 设置 `F0Md = 1` 切换手动模式
3. 写入 `F0Tg` 设置目标转速

### SMC 键说明

| 键名 | 说明 | 格式 |
|------|------|------|
| FNum | 风扇数量 | UInt8 |
| F0Ac | 风扇 0 实际转速 | fpe2 (14.2 定点) |
| F0Mn | 风扇 0 最小转速 | fpe2 |
| F0Mx | 风扇 0 最大转速 | fpe2 |
| F0Tg | 风扇 0 目标转速 | fpe2 |
| F0Md | 风扇 0 模式 | UInt8 (0=自动, 1=手动) |
| FS!  | 强制模式位掩码 | UInt16 |
| Ftst | 诊断/测试模式 | UInt8 (Apple Silicon 必需) |

### 设计模式

- **协议抽象** — `TemperatureProvider` / `FanControlProvider` 解耦硬件访问
- **依赖注入** — FanController 通过 init 参数接收依赖，支持测试替换
- **类型化错误** — `AppError` 枚举替代字符串错误，提供结构化错误处理
- **模块化** — Core（纯逻辑）/ SMCKit（硬件）/ App（UI）/ Helper（特权）

### 性能优化

- **后台线程 I/O** — HID 温度读取和 Socket 风扇通信均在 `DispatchQueue.global` 执行，不阻塞主线程
- **@Published 变更检测** — 所有 @Published 属性仅在值实际变化时赋值，避免不必要的 SwiftUI 重绘
  - 温度值：变化 ≥ 0.5°C 才更新
  - CPU/内存使用率：变化 ≥ 0.1% 才更新
  - 数组（temperatures/fans）：逐元素比较，无变化不触发
- **并发保护** — `isUpdatingFanInfo` / `isUpdatingTemperatures` 防止定时器回调堆积
- **智能发送** — 自动控制模式下，风扇转速变化 ≥ 1% 才发送 Socket 命令
- **静态缓存** — 传感器名称映射表、总内存大小等不变数据仅初始化一次
- **Socket 超时** — 2 秒读写超时防止 Helper 无响应时阻塞

## 故障排除

### Helper 无法启动

```bash
sudo log show --predicate 'subsystem == "com.macfancontrol.helper"' --last 5m
```

### 无法控制风扇

1. 确认 Helper 已安装：`ls /var/run/com.macfancontrol.smchelper.sock`
2. 检查 Helper 状态：`sudo launchctl list | grep macfancontrol`
3. M3/M4 可能有固件限制（仅在系统激活风扇后可接管）

### 温度不显示

Apple Silicon 上温度通过 HID 传感器读取，无需 root 权限。如果无数据，会回退到 CPU 负载估算。

## 许可证

MIT License

## 致谢

- [SMCKit](https://github.com/beltex/SMCKit) — SMC 访问参考
- [Stats](https://github.com/exelban/stats) — 开源系统监控工具