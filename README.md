# Mac 风扇控制 (MacFanControl)

一个支持 Apple Silicon (M1/M2/M3/M4) 的 macOS 风扇监控和控制工具。

## 功能特点

- 🌡️ **实时温度监测** - 显示 CPU/GPU 温度
- 💨 **风扇转速显示** - 实时显示风扇 RPM
- 🎛️ **手动控制** - 通过滑块自定义风扇转速
- 📈 **自动控制** - 根据 CPU 温度自动调节转速
- 📊 **预设配置** - 静音/平衡/性能三种模式
- 🔔 **状态栏显示** - 在菜单栏显示温度
- 🍎 **Apple Silicon 支持** - 支持 M1/M2/M3/M4 芯片

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+ (用于编译)

## 架构说明

```
┌─────────────────────────────────────────────────────────────────┐
│                        MacFanControl.app                         │
│                      (主应用 - 用户界面)                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ XPC 通信
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    MacFanControlHelper                           │
│                  (特权辅助程序 - root 权限)                       │
│                                                                  │
│  • 写入 Ftst=1 解锁 Apple Silicon 风扇控制                       │
│  • 设置风扇模式和目标转速                                         │
│  • 读取温度传感器                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ IOKit / AppleSMC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    System Management Controller                  │
│                         (硬件 SMC 芯片)                          │
└─────────────────────────────────────────────────────────────────┘
```

## 安装和运行

### 步骤 1: 编译项目

```bash
cd /Users/chen/MacFanControl
swift build -c release
```

### 步骤 2: 安装 Helper Tool (需要管理员权限)

```bash
sudo ./install-helper.sh
```

这会将 Helper Tool 安装到 `/Library/PrivilegedHelperTools/` 并注册为系统服务。

### 步骤 3: 运行主应用

```bash
./.build/release/MacFanControl
```

## 卸载

```bash
sudo ./uninstall-helper.sh
```

## 项目结构

```
MacFanControl/
├── Package.swift               # Swift 包配置
├── README.md                   # 说明文档
├── install-helper.sh           # Helper 安装脚本
├── uninstall-helper.sh         # Helper 卸载脚本
├── Sources/
│   ├── MacFanControlApp.swift  # SwiftUI 主应用
│   ├── FanController.swift     # 风扇控制逻辑
│   ├── SMC.swift               # SMC 硬件访问
│   ├── HelperProtocol.swift    # XPC 协议定义
│   ├── HelperConnection.swift  # XPC 连接管理
│   └── Info.plist              # 应用配置
└── Helper/
    ├── main.swift              # Helper Tool 入口
    ├── SMC.swift               # SMC 访问 (副本)
    ├── HelperProtocol.swift    # XPC 协议 (副本)
    ├── Info.plist              # Helper 配置
    └── com.macfancontrol.helper.plist  # launchd 配置
```

## 技术说明

### Apple Silicon 风扇控制

Apple Silicon Mac 需要特殊处理才能控制风扇：

1. **Ftst 键** - 必须先写入 `Ftst = 1` 进入诊断模式
2. **thermalmonitord** - 系统守护进程会主动管理风扇，需要等待它让出控制权
3. **重试机制** - 写入风扇控制键后需要重试 3-6 秒

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

### M3/M4 限制

在 M3/M4 MacBook Pro + macOS Sequoia 上存在额外限制：
- 只能在系统已激活风扇后才能接管控制
- 系统冷却后会失去控制权
- 某些型号可能完全禁用第三方控制

## 故障排除

### Helper 无法启动

检查日志：
```bash
sudo log show --predicate 'subsystem == "com.macfancontrol.helper"' --last 5m
```

### 无法控制风扇

1. 确保 Helper 已安装并运行
2. 检查是否为 Apple Silicon Mac
3. M3/M4 可能有固件限制

### 温度不显示

Apple Silicon 上温度传感器访问可能需要特殊权限，Helper Tool 应该能解决此问题。

## 开发

### 编译调试版本

```bash
swift build
```

### 编译发布版本

```bash
swift build -c release
```

### 代码签名 (用于分发)

如果要分发给其他用户，需要：
1. Apple Developer Program 账号 ($99/年)
2. Developer ID 证书
3. 公证 (Notarization)

```bash
# 签名 Helper
codesign --force --sign "Developer ID Application: Your Name" \
         --options runtime \
         .build/release/MacFanControlHelper

# 签名主应用
codesign --force --sign "Developer ID Application: Your Name" \
         --options runtime \
         .build/release/MacFanControl
```

## 许可证

MIT License

## 致谢

- [SMCKit](https://github.com/beltex/SMCKit) - SMC 访问参考
- [Stats](https://github.com/exelban/stats) - 开源系统监控工具
- [Macs Fan Control](https://crystalidea.com/macs-fan-control) - 商业风扇控制软件
