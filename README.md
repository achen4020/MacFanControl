<div align="center">
  <img src="logo.png" alt="MacFanControl Logo" width="128" />

  # Mac 风扇控制 (MacFanControl)

  **原生 macOS 菜单栏硬件监控、风扇控制与区域截图工具**

  ![macOS](https://img.shields.io/badge/macOS-13.0+-000000?style=flat-square&logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?style=flat-square&logo=swift)
  ![Version](https://img.shields.io/badge/version-1.1.0-blue?style=flat-square)
  ![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)
</div>

MacFanControl 是一款不占用 Dock 的 SwiftUI 菜单栏应用。它把温度、风扇、CPU、内存、启动磁盘和网络状态集中在一个面板中，同时提供可持久化的风扇曲线控制和带编辑器的区域截图。

## 功能

### 硬件与系统监控

- CPU 温度、可用时的 GPU 温度、SSD 温度和风扇实时转速。
- CPU 使用率以及内存已用容量、总容量和使用比例。
- 当前 macOS 启动磁盘的 SSD 存储已用容量、总容量和使用比例。
- 当前活跃物理网络接口的网络上传下载速度合计。
- 仅显示能够明确识别的温度传感器，避免展示含义不确定的原始名称。

### 风扇控制

- 系统自动、手动无级调速和实时 RPM 反馈。
- 静音、平衡、性能三种预设温度曲线。
- 可视化自定义曲线编辑器。
- 自动控制开关、当前配置和自定义曲线会持久化，重新启动应用后自动恢复。
- 应用启动后立即开始监控和自动控制，不需要先点击菜单栏图标。
- 退出应用时恢复系统自动风扇模式。

### 区域截图与编辑

- 默认使用 `Control + Shift + A`（`⌃⇧A`）触发区域截图，快捷键可在设置中修改或恢复默认值。
- 在鼠标所在显示器上自由框选任意大小区域，支持反向拖动、尺寸提示、放大镜、`Esc` 和右键取消。
- 截图后始终打开编辑器，支持裁剪、矩形、箭头、画笔、文字和马赛克。
- 支持标注选择、移动、八方向缩放、删除、撤销和重做。
- 支持保存 PNG/JPEG、复制到剪贴板，以及在编辑器中使用 `Command + V` 打开剪贴板图片。
- 多个截图可以分别打开编辑窗口；关闭未保存内容前会提示确认。

> 当前版本按鼠标所在的单个显示器截图，不支持跨显示器框选、滚动截图、OCR、窗口自动识别或录屏。

## 系统要求

- macOS 13.0 Ventura 或更高版本。
- Apple Silicon 或 Intel Mac；实际温度传感器和可控风扇数量取决于具体机型与固件。
- 区域截图需要开启“隐私与安全性 > 屏幕与系统音频录制”中的屏幕录制权限。
- 风扇调速需要安装应用内置的特权 Helper，并输入管理员密码。
- 从源码构建需要 Xcode 15 或更高版本、Swift 5.9 或更高版本。

## 安装

### 下载 Release

1. 从 [GitHub Releases](https://github.com/achen4020/MacFanControl/releases/latest) 下载 `MacFanControl_v1.1.0.zip`。
2. 解压后将 `MacFanControl.app` 拖入 `/Applications`。
3. 首次启动后，根据菜单栏提示安装风扇控制 Helper。
4. 首次使用区域截图时，按提示授予屏幕录制权限并重新启动应用。

当前发布包使用稳定的本地临时签名，但没有 Apple Developer ID 公证。如果 macOS 阻止首次启动，可在“系统设置 > 隐私与安全性”中选择仍要打开；仍无法运行时可执行：

```bash
xattr -dr com.apple.quarantine /Applications/MacFanControl.app
open /Applications/MacFanControl.app
```

### 从源码构建应用包

```bash
git clone https://github.com/achen4020/MacFanControl.git
cd MacFanControl
./build-app.sh
```

构建完成后，应用位于项目根目录的 `MacFanControl.app`。脚本会生成 Release 二进制、编译并内置 `smc_helper`、创建 plist，并使用稳定的指定要求进行临时签名。

### 开发模式

```bash
swift build
swift test
swift run MacFanControl
```

直接运行 SwiftPM 可执行文件适合开发调试，但完整的 Helper 安装、应用图标、屏幕录制权限和稳定签名测试应使用 `./build-app.sh` 生成的应用包。

## 权限说明

### 屏幕录制权限

区域截图需要读取显示器画面。授权后必须退出并重新打开 MacFanControl。开发构建使用稳定指定要求，避免每次重新编译都因 `cdhash` 变化而丢失屏幕录制权限。

### 风扇控制 Helper

温度和系统状态监控不要求 root 权限；修改风扇模式和目标转速需要特权 Helper。应用会将 Helper 安装到 `/Library/PrivilegedHelperTools/com.macfancontrol.smchelper`，并通过 Unix Socket `/var/run/com.macfancontrol.smchelper.sock` 通信。

也可以手动安装或卸载：

```bash
sudo ./install-helper.sh
sudo ./uninstall-helper.sh
```

## 架构

```text
MacFanControl.app (SwiftUI / AppKit 菜单栏应用)
├── MacFanControlCore   数据模型、曲线、配置、存储和网络计算
├── ScreenshotKit       截图几何、历史、快捷键存储、渲染和编码
├── FanController       监控、配置恢复和风扇控制协调
├── TemperatureReader   HID 温度读取
├── SystemMonitor       CPU、内存、启动磁盘和网络监控
├── Screenshot          全局快捷键、选区遮罩和编辑器窗口
└── SMCHelperClient ── Unix Socket ── MacFanControlHelper (root)
                                           │
                                           └── IOKit / AppleSMC
```

主应用依赖 `MacFanControlCore`、`ScreenshotKit` 和 `SMCKit`；特权 Helper 仅依赖共享的 `SMCKit`。截图模块与 `FanController` 解耦，只在用户触发时读取屏幕和创建编辑窗口，不影响持续运行的风扇监控。

## 项目结构

```text
MacFanControl/
├── Package.swift
├── Core/                         # 可测试的监控、风扇和配置模型
├── ScreenshotKit/                # 截图核心模型、几何、历史与渲染
├── Shared/                       # 应用和 Helper 共享的 SMC 访问层
├── Sources/
│   ├── MacFanControlApp.swift    # 应用入口和窗口控制器
│   ├── FanController.swift       # 监控与风扇控制协调
│   ├── MenuBarViews.swift        # 菜单栏面板
│   ├── FanCurveEditor.swift      # 风扇曲线编辑器
│   ├── SettingsViews.swift       # 通用、配置、截图和关于设置
│   ├── SystemMonitor.swift       # CPU、内存、磁盘和网络监控
│   └── Screenshot/               # 快捷键、选区和截图编辑器
├── Helper/                       # Swift Helper 目标
├── smc_helper.c                  # 发布包内置的 Helper 实现
└── Tests/
    ├── MacFanControlCoreTests/
    ├── ScreenshotKitTests/
    ├── BuildAppSigningTests.sh
    └── ReleaseMetadataTests.sh
```

## 测试与发布校验

```bash
swift test
swift build -c release
bash Tests/BuildAppSigningTests.sh MacFanControl.app
bash Tests/ReleaseMetadataTests.sh
```

当前测试覆盖风扇曲线与配置持久化、传感器名称、CPU/内存/磁盘/网络计算、截图坐标与 Retina 映射、快捷键存储、会话去重、编辑历史、裁剪、马赛克、PNG 编码、剪贴板限制和编辑器窗口尺寸。

## 故障排除

### 已开启屏幕录制权限但仍无法截图

确认运行的是 `/Applications/MacFanControl.app`，退出应用后重新打开。如果系统中保存了旧开发构建的权限记录，可执行以下命令，然后重新授权一次：

```bash
tccutil reset ScreenCapture com.macfancontrol.app
open /Applications/MacFanControl.app
```

### Helper 无法启动

```bash
sudo log show --predicate 'subsystem == "com.macfancontrol.helper"' --last 5m
sudo launchctl list | grep macfancontrol
ls -l /var/run/com.macfancontrol.smchelper.sock
```

### 无法控制风扇

- 确认 Helper 已安装并且 Socket 存在。
- 部分无风扇机型只能监控，无法调速。
- 部分 Apple Silicon 固件可能只允许在系统已经激活风扇后接管控制。

### 温度不显示

应用优先读取能够明确识别的 HID 温度传感器，再回退到 SMC。不同机型暴露的传感器并不相同，无法明确对应的原始传感器不会显示。

## 许可证

MIT License

## 致谢

- [SMCKit](https://github.com/beltex/SMCKit) - SMC 访问参考
- [Stats](https://github.com/exelban/stats) - 开源 macOS 系统监控工具
