# Developer ID 直分发与安全 Helper 设计

## 目标

在不进入 Mac App Store、不启用 App Sandbox 的前提下，为 MacFanControl 建立可重复的 Developer ID 签名、公证和 GitHub Release 流程，同时完整保留风扇控制、自动曲线、硬件监控、截图与编辑功能。

本次改造还要消除当前 root Helper 使用 `0666` Unix Socket、任意本地进程均可发送风扇控制命令的安全风险。最低系统版本继续保持 macOS 13，因此采用 `SMAppService`，不保留旧版 macOS 的 `SMJobBless` 兼容路径。

## 发行边界

- 发行渠道是 GitHub Releases 或官网直接下载，不提交 Mac App Store。
- 主应用保持非沙盒运行，但所有主可执行文件启用 Hardened Runtime。
- 使用同一 Apple Developer Team 的 `Developer ID Application` 身份分别签署 Helper 和主应用。
- 主应用保持现有 Bundle ID `com.macfancontrol.app`；安全 Helper 使用 `com.macfancontrol.helper.v2`，避免与已安装的旧版同名 LaunchDaemon 冲突。
- Developer ID 默认 designated requirement 作为稳定身份，不再使用仅校验 Bundle ID 的宽松自定义 requirement。
- 公证凭据只保存在用户登录钥匙串，不进入脚本、Git 或构建产物。
- 发布包同时支持 `arm64` 和 `x86_64`；如果某个目标无法构建为 Universal Binary，发布脚本必须失败，不能生成与 README 声明不一致的包。

## Helper 架构

### 应用包布局

正式应用包采用以下结构：

```text
MacFanControl.app/
└── Contents/
    ├── MacOS/MacFanControl
    ├── Resources/MacFanControlHelper
    └── Library/LaunchDaemons/com.macfancontrol.helper.v2.plist
```

LaunchDaemon plist 使用 `BundleProgram` 指向 `Contents/Resources/MacFanControlHelper`，通过 `MachServices` 发布 `com.macfancontrol.helper.v2`。主应用使用 `SMAppService.daemon(plistName:)` 注册、查询状态和注销服务；未获批准时向用户说明，并提供打开“系统设置 > 通用 > 登录项与扩展”的入口。

当前 `smc_helper.c`、AppleScript 安装代码、`/var/run/com.macfancontrol.smchelper.sock` 和对 `/Library/PrivilegedHelperTools` 的手工复制不再进入正式构建。两个旧安装脚本明确停用，只保留旧服务卸载工具。

### XPC 协议

项目已有的 Swift `MacFanControlHelper` 作为唯一正式 Helper。共享 XPC 协议提供以下能力：

- 获取 Helper 版本和可用状态。
- 一次返回全部风扇的当前、最小、最大、目标转速和模式。
- 为指定风扇设置经过边界校验的目标转速。
- 恢复全部风扇到系统自动模式。
- 在支持的机型上解锁或释放 Apple Silicon 风扇控制。
- 获取可识别的 SMC 温度数据。

主应用的 `SMCHelperClient` 改为 `NSXPCConnection(machServiceName:options: [.privileged])`。客户端调用设置有限超时；连接中断、失效或 Helper 错误时返回失败，不阻塞主线程，并保持现有 `FanControlProvider` 对上层的接口不变。

### 调用者认证与安全约束

Helper 启动时从自身有效代码签名读取 Apple Team ID，并在 `NSXPCListener` 激活前调用 macOS 13 提供的 `setConnectionCodeSigningRequirement(_:)`。launchd/XPC 在调用 delegate 前自动拒绝不符合要求的连接。主应用也在激活 `NSXPCConnection` 前调用 `setCodeSigningRequirement(_:)`，只接受预期 Helper。双方要求同时满足：

- Helper 只接受 Bundle ID 为 `com.macfancontrol.app` 的主应用。
- 主应用只接受 Bundle ID 为 `com.macfancontrol.helper.v2` 的 Helper。
- Apple Team ID 与构建时写入的允许 Team ID 一致。
- 签名有效且由 Apple Developer ID 信任链锚定。

开发构建使用单独、明确的开发允许策略，不能把“任意同 Bundle ID 进程”作为正式发行策略。

所有写操作还必须在 Helper 内再次校验：风扇索引存在，RPM 为有限整数，并限制在对应风扇的最小和最大转速之间。收到无效请求时返回失败且不写入 SMC。每次请求只控制指定风扇，避免当前调用一次却重复覆盖全部风扇。Helper 被正常终止时尝试恢复系统自动模式；主应用退出时仍显式调用恢复逻辑。

## 构建与签名

新增非交互式发布脚本，替代 `build-app.sh` 中的临时签名发布路径。开发构建仍可使用临时签名，但正式发布必须显式提供：

- `DEVELOPER_ID_APPLICATION`：钥匙串中的 Developer ID Application 身份或 SHA-1。
- `DEVELOPMENT_TEAM`：Apple Developer Team ID。
- `NOTARY_PROFILE`：`notarytool` 钥匙串配置名称，默认 `MacFanControl-Notary`。

构建流程：

1. 分别构建 `arm64` 和 `x86_64` 的主应用与 Swift Helper。
2. 使用 `lipo` 合并并验证两种架构。
3. 组装标准应用包、Info.plist、图标、Helper 和 LaunchDaemon plist。
4. 使用 `Developer ID Application`、`--timestamp` 和 `--options runtime` 先签 Helper，再签主应用。
5. 使用 `codesign --verify --strict` 校验完整签名，并确认主应用和 Helper 的 Team ID、架构及 Hardened Runtime。

脚本不得使用 `codesign --deep` 完成正式签名，也不得在日志中输出钥匙串密码或 App 专用密码。

## 公证与发布产物

签名通过后，使用 `ditto --keepParent` 生成临时 ZIP，并运行：

```bash
xcrun notarytool submit <zip> --keychain-profile <profile> --wait
```

只有返回 `Accepted` 才继续。成功后对 `.app` 执行 `stapler staple` 和 `stapler validate`，再用 `spctl --assess --type execute` 验证 Gatekeeper，最后重新生成带票据的发布 ZIP 和 SHA-256。

公证失败时保留 submission ID，自动获取公证日志并退出，不覆盖上一次有效发布包。GitHub Release 上传仍是显式的独立步骤，只有本地全部验证通过后才允许执行。

## 迁移与用户体验

应用启动时先检查 `SMAppService` 状态：

- 已启用：建立 XPC 连接并立即开始风扇监控和自动控制。
- 未注册：展示安装 Helper 操作，调用注册接口。
- 等待批准或被拒绝：明确提示需要在系统设置中批准，不反复弹出管理员请求。
- Helper 不可用：监控和截图功能继续工作，风扇控制界面显示不可用原因。

对于已经安装旧 `com.macfancontrol.helper` 或 `com.macfancontrol.smchelper` LaunchDaemon 的用户，v2 Helper 首次成功连接后先恢复全部风扇为系统自动模式，再自动停止并删除固定路径中的旧服务，避免旧版无签名 Helper 与新 XPC Helper 同时控制风扇。

## 测试与验收

自动化测试覆盖：

- Helper 请求参数的风扇索引和 RPM 边界校验。
- XPC 数据传输模型与 `FanControlProvider` 映射。
- `SMAppService.Status` 到用户可见状态的映射。
- 构建脚本拒绝缺少证书、Team ID、单架构产物或未签名 Helper。
- LaunchDaemon plist 使用 `BundleProgram`、正确 Mach Service 和标准包内路径。
- 发布包中不再包含 `smc_helper` C 守护进程、`0666` Socket 或 AppleScript 安装代码。

完整验收执行：

```bash
swift test
swift build -c release
codesign --verify --strict --verbose=2 MacFanControl.app
xcrun stapler validate MacFanControl.app
spctl --assess --type execute --verbose=4 MacFanControl.app
```

还需在一台未安装旧 Helper 的 Mac 上进行人工验证：首次批准、重启后自动连接、手动/自动风扇控制、退出恢复系统模式、截图权限、离线 Gatekeeper 校验。已有旧 Helper 的机器再验证一次迁移路径。

## 不在本次范围

- Mac App Store 发行或 App Sandbox 版本。
- 自动更新框架、付费功能、应用内购买。
- Intel 与 Apple Silicon 之外的架构。
- macOS 12 及更早版本的 Helper 安装兼容。
