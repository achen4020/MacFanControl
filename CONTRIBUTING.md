# 参与贡献 (Contributing)

感谢你有兴趣为 MacFanControl 贡献代码！我们非常欢迎所有的建议、Bug 反馈及 Pull Request (PR)。

## 如何提交反馈

如果你发现了 Bug 或是想要新的功能，请按照以下步骤：

1. 请先在 [Issues](https://github.com/AlvinChen/MacFanControl/issues) 里搜索是否已经有人提出了相同的问题。
2. 如果没有，请点击 **New Issue**：
   - 如果是 **Bug**，请尽量提供详细的环境信息（macOS 版本、机器型号，例如 M2 Air、M4 Pro）以及重现步骤。
   - 如果是 **特征请求 (Feature Request)**，请清晰地描述你期望添加的功能及它的应用场景。

## 本地编译指南

参与开发前，请确保你的环境符合以下要求：
- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+ / Swift 5.9+

### 克隆并运行项目

```bash
git clone https://github.com/AlvinChen/MacFanControl.git
cd MacFanControl
```

你可以直接用 Xcode 打开 `Package.swift` 文件进行开发和调试，或者在终端运行：

```bash
# 编译应用
swift build

# 运行单元测试
swift test
```

*注意：控制风扇功能依赖于特权辅助工具 (`Helper`)，因此在修改 Helper 相关的代码时，你可能需要使用 `build-app.sh` 脚本构建完整的 App 并安装 Helper 才能进行完整的测试。*

## 提交 Pull Request (PR)

1. Fork 本仓库。
2. 创建一个新的分支 (`git checkout -b feature/your-feature-name` 或 `fix/your-bug-fix`)。
3. 提交你的修改 (`git commit -am 'Add some feature'`)。
4. 将分支推送到你的 Fork 仓库 (`git push origin feature/your-feature-name`)。
5. 在 GitHub 上发起 Pull Request。

在提交 PR 时，请在描述中详细说明修改的意图、相关的 Issue 编号（如果有）以及进行过的测试。

再次感谢你的支持！
