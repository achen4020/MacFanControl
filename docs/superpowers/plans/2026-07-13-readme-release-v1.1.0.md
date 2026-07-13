# MacFanControl v1.1.0 README and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the repository documentation and application metadata to match the current feature set, then publish a verified `v1.1.0` GitHub Release.

**Architecture:** Keep release metadata in the existing plist, build script, and About view, with a shell regression check enforcing consistency. Build the existing Swift package into the app bundle, validate its signature and metadata, archive it with `ditto`, then publish the exact verified commit and ZIP through GitHub CLI.

**Tech Stack:** Swift 5.9, Swift Package Manager, Bash, macOS `plutil`/`codesign`/`ditto`, Git, GitHub CLI.

---

## File Structure

- Modify `README.md`: describe the current monitoring, fan-control, screenshot, install, permission, architecture, and test behavior.
- Modify `Sources/Info.plist`: set short and build versions to `1.1.0`.
- Modify `Sources/SettingsViews.swift`: show `1.1.0` in About.
- Modify `build-app.sh`: generate a `1.1.0` bundle.
- Create `Tests/ReleaseMetadataTests.sh`: verify version consistency and required README feature coverage.
- Create `docs/releases/v1.1.0.md`: durable GitHub Release notes.

## Task 1: Add Release Metadata Regression Check

**Files:**
- Create: `Tests/ReleaseMetadataTests.sh`

- [ ] **Step 1: Add the failing metadata check**

```bash
#!/bin/bash
set -euo pipefail

VERSION="1.1.0"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Info.plist)" == "${VERSION}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Info.plist)" == "${VERSION}" ]]
rg -q '<string>1\.1\.0</string>' build-app.sh
rg -q '版本 1\.1\.0' Sources/SettingsViews.swift

for text in '区域截图' 'SSD 存储' '网络上传下载' '自定义曲线' '屏幕录制权限'; do
    rg -q "${text}" README.md
done

echo "Release metadata and README checks passed for ${VERSION}"
```

- [ ] **Step 2: Run the check and verify RED**

Run: `bash Tests/ReleaseMetadataTests.sh`

Expected: non-zero exit because plist, About, build script, and README do not yet describe `1.1.0`.

## Task 2: Rewrite README and Synchronize v1.1.0

**Files:**
- Modify: `README.md`
- Modify: `Sources/Info.plist`
- Modify: `Sources/SettingsViews.swift`
- Modify: `build-app.sh`
- Create: `docs/releases/v1.1.0.md`
- Test: `Tests/ReleaseMetadataTests.sh`

- [ ] **Step 1: Rewrite README against current behavior**

Document these exact user-facing capabilities:

```markdown
- CPU、GPU、SSD 温度和风扇转速
- CPU、内存、当前启动磁盘容量、当前活跃物理网络接口合计速率
- 手动控制、三种预设、自定义曲线和自动控制配置持久化
- Control + Shift + A 可配置区域截图快捷键
- 裁剪、矩形、箭头、画笔、文字、马赛克、选择移动缩放、撤销重做
- PNG/JPEG 保存、复制到剪贴板、Command + V 打开剪贴板图片
```

Keep the existing Chinese-first structure, update architecture and project trees for `ScreenshotKit`, and provide release download plus source-build instructions. Explicitly explain Helper administrator access and Screen Recording permission.

- [ ] **Step 2: Synchronize application version fields**

Set both plist values and generated plist values to:

```xml
<key>CFBundleVersion</key>
<string>1.1.0</string>
<key>CFBundleShortVersionString</key>
<string>1.1.0</string>
```

Set About text to:

```swift
Text("版本 1.1.0")
```

- [ ] **Step 3: Add durable Release notes**

Create `docs/releases/v1.1.0.md` with sections for new screenshot workflow, monitoring additions, persistence/startup fixes, permission/signing fixes, requirements, and installation.

- [ ] **Step 4: Run metadata check and verify GREEN**

Run: `bash Tests/ReleaseMetadataTests.sh && git diff --check`

Expected: both commands exit `0` and print `Release metadata and README checks passed for 1.1.0`.

- [ ] **Step 5: Commit documentation and version metadata**

```bash
git add README.md Sources/Info.plist Sources/SettingsViews.swift build-app.sh Tests/ReleaseMetadataTests.sh docs/releases/v1.1.0.md
git commit -m "docs: prepare v1.1.0 release"
```

## Task 3: Build and Validate Release Asset

**Files:**
- Generate ignored `MacFanControl.app`
- Generate ignored `MacFanControl_v1.1.0.zip`

- [ ] **Step 1: Run full automated verification**

Run: `swift test && swift build -c release && bash Tests/ReleaseMetadataTests.sh && bash -n build-app.sh`

Expected: 60 tests pass, Release build succeeds, metadata check succeeds, and shell syntax is valid.

- [ ] **Step 2: Build app bundle**

Run: `./build-app.sh`, answer `n` to the launch prompt.

Expected: `MacFanControl.app` exists and build exits `0`.

- [ ] **Step 3: Validate app bundle**

Run:

```bash
plutil -lint MacFanControl.app/Contents/Info.plist
codesign --verify --deep --strict MacFanControl.app
bash Tests/BuildAppSigningTests.sh MacFanControl.app
file MacFanControl.app/Contents/MacOS/MacFanControl
```

Expected: plist is `OK`, signature and stable requirement checks pass, and executable is arm64 Mach-O.

- [ ] **Step 4: Create and validate ZIP**

Run:

```bash
ditto -c -k --sequesterRsrc --keepParent MacFanControl.app MacFanControl_v1.1.0.zip
unzip -t MacFanControl_v1.1.0.zip
shasum -a 256 MacFanControl_v1.1.0.zip
```

Expected: archive test reports no errors and a SHA-256 digest is recorded for final verification.

## Task 4: Push, Tag, and Publish GitHub Release

**Files:**
- No additional repository changes expected.

- [ ] **Step 1: Confirm releasable Git state**

Run:

```bash
git fetch origin
git status --short
git rev-list --left-right --count main...origin/main
git tag --list v1.1.0
gh release view v1.1.0
```

Expected: worktree is clean, local history only contains intended release commits, and tag/release do not already exist.

- [ ] **Step 2: Push release commit**

Run: `git push origin main`

Expected: `main -> main` succeeds.

- [ ] **Step 3: Create the formal Release and upload ZIP**

Run:

```bash
gh release create v1.1.0 MacFanControl_v1.1.0.zip \
  --target main \
  --title "MacFanControl v1.1.0" \
  --notes-file docs/releases/v1.1.0.md \
  --latest
```

Expected: GitHub returns the new Release URL; release is neither draft nor prerelease.

- [ ] **Step 4: Verify remote publication**

Run:

```bash
gh release view v1.1.0 --json name,tagName,publishedAt,isDraft,isPrerelease,assets,url,targetCommitish
git ls-remote --tags origin refs/tags/v1.1.0
git rev-parse HEAD
```

Expected: Release tag is `v1.1.0`, target is the verified commit, asset is `MacFanControl_v1.1.0.zip`, and the Release URL is available.
