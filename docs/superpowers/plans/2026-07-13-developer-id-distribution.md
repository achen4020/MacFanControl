# Developer ID Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the insecure socket helper with a signed XPC LaunchDaemon and add repeatable Universal Binary, Developer ID signing, notarization, and release packaging.

**Architecture:** A new `HelperIPC` library owns the XPC contract, payloads, validation, and signing-requirement construction. `MacFanControlHelper` exposes SMC operations over an `NSXPCListener` registered by `SMAppService`; the app uses an asynchronous XPC client while `FanController` remains the main-actor coordinator. Shell release scripts build both architectures, sign nested code inside-out, notarize a temporary archive, staple the app, and create the final ZIP.

**Tech Stack:** Swift 5.9, SwiftPM, Foundation XPC, ServiceManagement `SMAppService`, Security.framework code-signing requirements, IOKit/SMC, Bash, `codesign`, `lipo`, `notarytool`, `stapler`, `spctl`, `ditto`.

---

## File Structure

- `HelperIPC/HelperProtocol.swift`: Objective-C-compatible XPC protocol and service identifiers.
- `HelperIPC/HelperModels.swift`: Codable fan/temperature payloads and response codec.
- `HelperIPC/FanRequestValidator.swift`: Pure fan index and RPM validation.
- `HelperIPC/CodeSigningRequirement.swift`: Team-ID-bound app/helper requirement strings.
- `HelperIPC/CurrentCodeSignature.swift`: Reads the current executable's Team ID from Security.framework.
- `HelperCore/HelperService.swift`: Testable implementation of the XPC operations.
- `HelperCore/SMCFanHardware.swift`: Adapter from `SMCManager` to the service's hardware protocol.
- `Helper/main.swift`: Minimal privileged listener bootstrap and connection policy.
- `Sources/HelperServiceManager.swift`: `SMAppService` registration/status abstraction.
- `Sources/SMCHelperClient.swift`: Asynchronous XPC client replacing Unix Socket and AppleScript.
- `scripts/build-developer-id-release.sh`: Universal app assembly and inside-out signing.
- `scripts/notarize-release.sh`: Keychain-backed notarization, stapling, assessment, and final ZIP.
- `Tests/HelperIPCTests/`: Payload, validator, and requirement tests.
- `Tests/HelperCoreTests/`: Helper behavior tests using fake hardware.
- `Tests/DeveloperIDReleaseTests.sh`: Static and fake-tool release pipeline checks.

### Task 1: Shared XPC contract and validation

**Files:**
- Modify: `Package.swift`
- Create: `HelperIPC/HelperProtocol.swift`
- Create: `HelperIPC/HelperModels.swift`
- Create: `HelperIPC/FanRequestValidator.swift`
- Create: `HelperIPC/CodeSigningRequirement.swift`
- Create: `Tests/HelperIPCTests/HelperModelsTests.swift`
- Create: `Tests/HelperIPCTests/FanRequestValidatorTests.swift`
- Create: `Tests/HelperIPCTests/CodeSigningRequirementTests.swift`

- [ ] **Step 1: Add the failing shared-model and validation tests**

```swift
import XCTest
@testable import HelperIPC

final class FanRequestValidatorTests: XCTestCase {
    func testAcceptsExistingFanInsideItsRange() {
        XCTAssertEqual(
            FanRequestValidator.validate(index: 1, rpm: 3200, ranges: [1800...5200, 2000...5000]),
            .valid
        )
    }

    func testRejectsMissingFanAndOutOfRangeRPM() {
        XCTAssertEqual(FanRequestValidator.validate(index: 2, rpm: 3200, ranges: [1800...5200]), .invalidFan)
        XCTAssertEqual(FanRequestValidator.validate(index: 0, rpm: 6000, ranges: [1800...5200]), .invalidRPM)
    }
}

final class HelperModelsTests: XCTestCase {
    func testFanSnapshotsRoundTripThroughXPCData() throws {
        let value = [HelperFanSnapshot(index: 0, currentRPM: 2400, minimumRPM: 1700, maximumRPM: 5200, targetRPM: 2600, mode: 1)]
        XCTAssertEqual(try HelperPayloadCodec.decodeFans(HelperPayloadCodec.encode(value)), value)
    }
}

final class CodeSigningRequirementTests: XCTestCase {
    func testRequirementBindsIdentifierAndTeam() throws {
        XCTAssertEqual(
            try CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "ABCDE12345").text,
            "anchor apple generic and identifier \"com.macfancontrol.app\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testRequirementRejectsUnsafeValues() {
        XCTAssertThrowsError(try CodeSigningRequirement(identifier: "com.example.\"bad", teamID: "ABCDE12345"))
        XCTAssertThrowsError(try CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "bad team"))
    }
}
```

- [ ] **Step 2: Register `HelperIPC` and its test target, then run RED**

Add these targets to `Package.swift` without yet creating implementations:

```swift
.target(name: "HelperIPC", path: "HelperIPC"),
.testTarget(name: "HelperIPCTests", dependencies: ["HelperIPC"], path: "Tests/HelperIPCTests"),
```

Run:

```bash
swift test --filter 'HelperIPC'
```

Expected: compilation fails because `FanRequestValidator`, payload types, codec, and signing requirement are undefined.

- [ ] **Step 3: Implement the minimal shared contract**

`HelperIPC/HelperProtocol.swift`:

```swift
import Foundation

public let helperMachServiceName = "com.macfancontrol.helper"
public let helperBundleIdentifier = "com.macfancontrol.helper"
public let mainAppBundleIdentifier = "com.macfancontrol.app"

@objc public protocol HelperToolProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func getFanData(reply: @escaping (Data?, String?) -> Void)
    func setFanSpeed(index: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func resetFanToAuto(index: Int, reply: @escaping (Bool, String?) -> Void)
    func resetAllFansToAuto(reply: @escaping (Bool, String?) -> Void)
    func getTemperatures(reply: @escaping (Data?, String?) -> Void)
    func removeLegacyHelper(reply: @escaping (Bool, String?) -> Void)
}
```

`HelperModels.swift` defines `HelperFanSnapshot` and `HelperTemperatureSnapshot` as `Codable`, `Equatable`, `Sendable` structs and `HelperPayloadCodec` using one configured `JSONEncoder`/`JSONDecoder` per call. `FanRequestValidator.swift` defines `ValidationResult` cases `valid`, `invalidFan`, and `invalidRPM`; it rejects negative indices and any RPM outside the selected closed range. `CodeSigningRequirement.swift` accepts only identifiers matching `[A-Za-z0-9.-]+` and Team IDs matching `[A-Z0-9]{10}` before producing the exact requirement asserted above.

- [ ] **Step 4: Run GREEN**

```bash
swift test --filter 'HelperIPC'
```

Expected: all `HelperIPCTests` pass.

- [ ] **Step 5: Commit the shared contract**

```bash
git add Package.swift HelperIPC Tests/HelperIPCTests
git commit -m "feat: add secure helper IPC contract"
```

### Task 2: Testable Swift Helper service

**Files:**
- Modify: `Package.swift`
- Modify: `Shared/SMC.swift`
- Create: `HelperCore/HelperService.swift`
- Create: `HelperCore/SMCFanHardware.swift`
- Create: `Tests/HelperCoreTests/HelperServiceTests.swift`

- [ ] **Step 1: Write failing Helper behavior tests**

Create a fake `FanHardwareControlling` that records writes, then assert:

```swift
func testSetFanSpeedRejectsInvalidRequestsWithoutWriting() async {
    let hardware = FakeFanHardware(ranges: [1800...5200])
    let service = HelperService(hardware: hardware)

    let invalidFan = await service.setFanSpeed(index: 1, rpm: 3000)
    let invalidRPM = await service.setFanSpeed(index: 0, rpm: 6000)

    XCTAssertFalse(invalidFan.success)
    XCTAssertFalse(invalidRPM.success)
    XCTAssertEqual(hardware.writes, [])
}

func testSetFanSpeedWritesOnlyRequestedFan() async {
    let hardware = FakeFanHardware(ranges: [1800...5200, 2000...5000])
    let service = HelperService(hardware: hardware)

    let result = await service.setFanSpeed(index: 1, rpm: 3200)

    XCTAssertTrue(result.success)
    XCTAssertEqual(hardware.writes, [.init(index: 1, rpm: 3200)])
}

func testResetAllAttemptsEveryFan() async {
    let hardware = FakeFanHardware(ranges: [1800...5200, 2000...5000])
    let service = HelperService(hardware: hardware)
    XCTAssertTrue((await service.resetAllFansToAuto()).success)
    XCTAssertEqual(hardware.resets, [0, 1])
}
```

- [ ] **Step 2: Add the empty targets and run RED**

```swift
.target(name: "MacFanControlHelperCore", dependencies: ["SMCKit", "HelperIPC"], path: "HelperCore"),
.testTarget(name: "HelperCoreTests", dependencies: ["MacFanControlHelperCore"], path: "Tests/HelperCoreTests"),
```

Run `swift test --filter HelperServiceTests` and confirm failure because the service and hardware protocol do not exist.

- [ ] **Step 3: Implement the service and SMC adapter**

Define this boundary in `HelperCore/HelperService.swift`:

```swift
public protocol FanHardwareControlling: AnyObject {
    func fanCount() -> Int
    func currentRPM(index: Int) -> Int?
    func minimumRPM(index: Int) -> Int?
    func maximumRPM(index: Int) -> Int?
    func targetRPM(index: Int) -> Int?
    func mode(index: Int) -> Int?
    func setFanSpeed(index: Int, rpm: Int) throws
    func resetFanToAuto(index: Int) throws
    func temperatures() -> [HelperTemperatureSnapshot]
}

public struct HelperOperationResult: Equatable, Sendable {
    public let success: Bool
    public let error: String?
}
```

`HelperService` serializes SMC access on a private dispatch queue, constructs fan snapshots from the hardware adapter, validates every write using current hardware ranges, and implements all reset operations. Add `getFanTargetSpeed(index:)` and `getFanMode(index:)` readers to `Shared/SMC.swift`; `SMCFanHardware` delegates to `SMCManager.shared`.

- [ ] **Step 4: Run focused and full GREEN tests**

```bash
swift test --filter HelperServiceTests
swift test
```

Expected: new Helper tests and all existing tests pass.

- [ ] **Step 5: Commit the Helper core**

```bash
git add Package.swift Shared/SMC.swift HelperCore Tests/HelperCoreTests
git commit -m "feat: implement validated fan helper service"
```

### Task 3: Privileged XPC listener and mutual code-signing policy

**Files:**
- Modify: `Package.swift`
- Create: `HelperIPC/CurrentCodeSignature.swift`
- Replace: `Helper/main.swift`
- Delete: `Helper/HelperProtocol.swift`
- Modify: `Helper/com.macfancontrol.helper.plist`
- Create: `Tests/HelperIPCTests/LaunchDaemonLayoutTests.swift`

- [ ] **Step 1: Add failing plist and requirement tests**

The test reads `Helper/com.macfancontrol.helper.plist` and asserts:

```swift
XCTAssertEqual(plist["Label"] as? String, helperMachServiceName)
XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/Resources/MacFanControlHelper")
XCTAssertNil(plist["Program"])
XCTAssertEqual((plist["MachServices"] as? [String: Bool])?[helperMachServiceName], true)
```

Run `swift test --filter LaunchDaemonLayoutTests`; expected failure because the plist still uses absolute `Program` and `ProgramArguments` paths.

- [ ] **Step 2: Replace the plist with the SMAppService layout**

Use `Label`, `BundleProgram`, `MachServices`, `RunAtLoad`, and `KeepAlive`; remove every `/Library/PrivilegedHelperTools` path. The `BundleProgram` value must be `Contents/Resources/MacFanControlHelper`.

- [ ] **Step 3: Implement the signed XPC listener**

Change the executable target dependencies to `SMCKit`, `HelperIPC`, and `MacFanControlHelperCore`, and link Security.framework. `CurrentCodeSignature.teamIdentifier()` calls `SecCodeCopySelf`, `SecCodeCopySigningInformation`, and reads `kSecCodeInfoTeamIdentifier`; absence of a Team ID is an explicit error in Release builds. `Helper/main.swift` must:

```swift
let listener = NSXPCListener(machServiceName: helperMachServiceName)
let ownTeamID = try CurrentCodeSignature.teamIdentifier()
let appRequirement = try CodeSigningRequirement(identifier: mainAppBundleIdentifier, teamID: ownTeamID).text
listener.setConnectionCodeSigningRequirement(appRequirement)
listener.delegate = HelperListenerDelegate(service: HelperService(hardware: SMCFanHardware()))
listener.activate()
RunLoop.current.run()
```

The delegate exports only `HelperToolProtocol`, activates accepted connections, removes invalidated connections from its collection, and forwards calls to `HelperService`. Release builds exit with a logged configuration error if no Team ID exists. Debug builds may use identifier-only requirements so local unsigned testing remains possible.

- [ ] **Step 4: Run tests and compile both executables**

```bash
swift test
swift build -c release --product MacFanControlHelper
```

Expected: all tests pass and the Helper executable links Foundation, Security, IOKit, and CoreFoundation successfully.

- [ ] **Step 5: Commit the XPC daemon**

```bash
git add Package.swift Helper HelperIPC Tests/HelperIPCTests
git commit -m "feat: secure helper with signed XPC connections"
```

### Task 4: Asynchronous app-side XPC client

**Files:**
- Modify: `Core/Models.swift`
- Modify: `Package.swift`
- Replace: `Sources/SMCHelperClient.swift`
- Modify: `Sources/FanController.swift`
- Modify: `Sources/MacFanControlApp.swift`
- Modify: `Sources/MenuBarViews.swift`
- Create: `Tests/HelperIPCTests/ReplyGateTests.swift`

- [ ] **Step 1: Add a failing single-resume timeout test**

```swift
func testReplyGateUsesFirstReplyOnly() async {
    let gate = ReplyGate<Int>()
    async let value = gate.wait(timeout: .milliseconds(50), fallback: -1)
    gate.resolve(42)
    gate.resolve(99)
    XCTAssertEqual(await value, 42)
}

func testReplyGateReturnsFallbackAfterTimeout() async {
    let gate = ReplyGate<Int>()
    XCTAssertEqual(await gate.wait(timeout: .milliseconds(10), fallback: -1), -1)
}
```

Run `swift test --filter ReplyGateTests`; expected compile failure because `ReplyGate` does not exist.

- [ ] **Step 2: Implement `ReplyGate` in `HelperIPC` and run GREEN**

Use `NSLock` to protect one stored continuation and one resolved value. Only the first result resumes the continuation; the timeout uses `Task.sleep(for:)` and supplies the fallback. Run `swift test --filter ReplyGateTests` and confirm both tests pass.

- [ ] **Step 3: Make `FanControlProvider` asynchronous and index-specific**

Replace the protocol methods with:

```swift
public protocol FanControlProvider: Sendable {
    var isAvailable: Bool { get }
    func getFanData() async -> [FanDataSnapshot]
    func setFanSpeed(index: Int, rpm: Int) async -> Bool
    func resetFanToAuto(index: Int) async -> Bool
    func resetAllFansToAuto() async -> Bool
}
```

Update `FanController` so monitoring, manual changes, automatic curves, and resets await the provider off the synchronous UI path, then apply published-state changes on `MainActor`. Remove the old pattern that loops over fans while each provider call changes every fan.

Add `applicationShouldTerminate(_:)` to `MacFanControlAppDelegate`. It returns `.terminateLater`, awaits `SMCHelperClient.shared.resetAllFansToAuto()`, then calls `NSApp.reply(toApplicationShouldTerminate: true)`; a two-second client timeout guarantees termination cannot hang indefinitely.

- [ ] **Step 4: Replace the socket client with XPC**

`SMCHelperClient` creates `NSXPCConnection(machServiceName: helperMachServiceName, options: [.privileged])`, sets the Helper requirement using the current app Team ID before `activate()`, configures `remoteObjectInterface`, and recreates the connection after interruption/invalidation. Each callback API is wrapped with `ReplyGate` and a two-second timeout. There must be no socket APIs, `/var/run` paths, AppleScript, `Thread.sleep`, or filesystem checks under `/Library/PrivilegedHelperTools`.

- [ ] **Step 5: Update call sites and verify**

```bash
rg -n '/var/run/com\.macfancontrol|NSAppleScript|sendViaSocket|SOCK_STREAM' Sources
swift test
swift build -c release
```

Expected: `rg` returns no matches; all tests and release build pass.

- [ ] **Step 6: Commit the app-side XPC client**

```bash
git add Package.swift Core HelperIPC Sources Tests/HelperIPCTests
git commit -m "feat: connect fan control through async XPC"
```

### Task 5: SMAppService registration and legacy migration

**Files:**
- Create: `HelperIPC/HelperRegistrationState.swift`
- Create: `Sources/HelperServiceManager.swift`
- Modify: `Sources/FanController.swift`
- Modify: `Sources/MenuBarViews.swift`
- Modify: `Sources/SettingsViews.swift`
- Modify: `HelperIPC/HelperProtocol.swift`
- Modify: `HelperCore/HelperService.swift`
- Create: `Tests/HelperIPCTests/HelperRegistrationStateTests.swift`
- Create: `Tests/HelperCoreTests/LegacyHelperRemovalTests.swift`

- [ ] **Step 1: Write failing registration-state tests**

```swift
func testRegistrationStateMessagesAreActionable() {
    XCTAssertEqual(HelperRegistrationState.notRegistered.actionTitle, "安装风扇控制服务")
    XCTAssertEqual(HelperRegistrationState.requiresApproval.actionTitle, "打开系统设置")
    XCTAssertNil(HelperRegistrationState.enabled.actionTitle)
}
```

Add a fake legacy-removal executor test proving that removal runs `launchctl bootout system /Library/LaunchDaemons/com.macfancontrol.smchelper.plist` before deleting the old plist, executable, and socket. Define `HelperRegistrationState` in `HelperIPC` so its action title is testable without importing the executable app target. Run focused tests and observe RED for missing types.

- [ ] **Step 2: Implement state mapping and `SMAppService` manager**

`HelperServiceManager` owns:

```swift
private let service = SMAppService.daemon(plistName: "com.macfancontrol.helper.plist")

func register() throws { try service.register() }
func unregister() async throws { try await service.unregister() }
func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
```

Map `.notRegistered`, `.enabled`, `.requiresApproval`, and `.notFound` into `HelperRegistrationState`. `FanController` publishes that state and no longer automatically repeats an installation prompt.

- [ ] **Step 3: Implement authenticated legacy cleanup**

Add `removeLegacyHelper` to the XPC service. It is callable only after the listener's code-signing requirement has accepted the main app. The root Helper runs `/bin/launchctl bootout system <legacy-plist>`, treats “service not loaded” as nonfatal, then removes exactly these paths:

```text
/Library/LaunchDaemons/com.macfancontrol.smchelper.plist
/Library/PrivilegedHelperTools/com.macfancontrol.smchelper
/var/run/com.macfancontrol.smchelper.sock
```

No user-controlled path or command fragment may enter `Process` arguments.

- [ ] **Step 4: Update UI and tests**

Replace “安装服务（需要管理员密码）” logic with status-specific actions: register, open system settings, retry connection, or show enabled. Remove the uninstall AppleScript from `SettingsViews.swift`; unregister the new service through `SMAppService` and request legacy cleanup through XPC.

Run:

```bash
swift test
swift build -c release
rg -n 'do shell script|NSAppleScript|launchctl unload' Sources
```

Expected: tests/build pass and the search returns no matches.

- [ ] **Step 5: Commit service lifecycle support**

```bash
git add Sources HelperIPC HelperCore Tests
git commit -m "feat: manage privileged helper with SMAppService"
```

### Task 6: Universal Developer ID build and signing

**Files:**
- Create: `scripts/build-developer-id-release.sh`
- Create: `Tests/DeveloperIDReleaseTests.sh`
- Modify: `Sources/Info.plist`
- Modify: `Sources/MacFanControl.entitlements`
- Modify: `README.md`

- [ ] **Step 1: Write a failing release-script contract test**

The shell test must require:

```bash
rg -q 'DEVELOPER_ID_APPLICATION' scripts/build-developer-id-release.sh
rg -q 'DEVELOPMENT_TEAM' scripts/build-developer-id-release.sh
rg -q -- '--arch arm64' scripts/build-developer-id-release.sh
rg -q -- '--arch x86_64' scripts/build-developer-id-release.sh
rg -q -- '--timestamp' scripts/build-developer-id-release.sh
rg -q -- '--options runtime' scripts/build-developer-id-release.sh
rg -q 'Contents/Library/LaunchDaemons' scripts/build-developer-id-release.sh
! rg -q -- '--deep|--sign -' scripts/build-developer-id-release.sh
```

Run `bash Tests/DeveloperIDReleaseTests.sh`; expected failure because the script is absent.

- [ ] **Step 2: Implement Universal build assembly**

The script uses `set -euo pipefail`, verifies both required environment variables are nonempty, verifies the identity with `security find-identity`, builds app and Helper into separate arm64/x86_64 scratch paths, merges each with `lipo -create`, and confirms both architectures with `lipo -archs`. It copies `Sources/Info.plist`, the icon, Helper, and LaunchDaemon plist into the standard bundle layout. Add `NSHumanReadableCopyright` with `Copyright © 2026 achen4020.` and `LSApplicationCategoryType` with `public.app-category.utilities` to the source plist.

Reduce `Sources/MacFanControl.entitlements` to an empty dictionary because direct Developer ID distribution is intentionally non-sandboxed and the existing Sandbox temporary exceptions are not used. Pass that file explicitly when signing the main app so the release entitlement set remains reviewable and deterministic.

- [ ] **Step 3: Implement inside-out signing and verification**

Use these signing forms:

```bash
codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" \
  --identifier com.macfancontrol.helper "$APP/Contents/Resources/MacFanControlHelper"
codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$APP"
codesign --verify --strict --verbose=2 "$APP"
```

Extract and compare Team IDs for both executables, and fail if either signature lacks `runtime` or a secure timestamp.

- [ ] **Step 4: Run script contract and normal project verification**

```bash
bash -n scripts/build-developer-id-release.sh
bash Tests/DeveloperIDReleaseTests.sh
swift test
```

Expected: all checks pass without accessing the user's certificate or network.

- [ ] **Step 5: Commit the signed-build pipeline**

```bash
git add scripts Tests/DeveloperIDReleaseTests.sh Sources/Info.plist README.md
git commit -m "build: add Developer ID release signing"
```

### Task 7: Notarization and final package

**Files:**
- Create: `scripts/notarize-release.sh`
- Modify: `Tests/DeveloperIDReleaseTests.sh`
- Modify: `README.md`

- [ ] **Step 1: Extend RED tests for notarization invariants**

Require `notarytool submit --keychain-profile --wait`, `notarytool log`, `stapler staple`, `stapler validate`, `spctl --assess --type execute`, `ditto --keepParent`, and `shasum -a 256`. Also assert the script never accepts a password argument or reads an Apple ID password environment variable. Run the test and observe failure because the script is absent.

- [ ] **Step 2: Implement the notarization script**

The script accepts exactly three positional arguments: app path, semantic version, and keychain profile. It creates a temporary ZIP, submits it with JSON output and `--wait`, requires status `Accepted`, fetches the log on every non-accepted result, staples and validates the app, assesses it with `spctl`, then creates `MacFanControl_v<version>.zip` and `.sha256` only after every check succeeds.

- [ ] **Step 3: Document one-time credential setup**

Add this exact interactive command to README without any real secrets:

```bash
xcrun notarytool store-credentials "MacFanControl-Notary" \
  --apple-id "$APPLE_ID" \
  --team-id "$DEVELOPMENT_TEAM"
```

Document that the App-specific password is entered interactively and never committed.

- [ ] **Step 4: Run release pipeline tests**

```bash
bash -n scripts/notarize-release.sh
bash Tests/DeveloperIDReleaseTests.sh
swift test
```

Expected: all local non-network checks pass.

- [ ] **Step 5: Commit notarization support**

```bash
git add scripts/notarize-release.sh Tests/DeveloperIDReleaseTests.sh README.md
git commit -m "build: add Apple notarization pipeline"
```

### Task 8: Real certificate build, manual Helper validation, and handoff

**Files:**
- Modify only if validation exposes a defect in files already listed above.

- [ ] **Step 1: Detect the installed Developer ID identity without printing secrets**

```bash
security find-identity -v -p codesigning
```

Collect only identities whose label starts with `Developer ID Application:`. Stop and request the identity choice only if more than one valid identity exists; when exactly one exists, derive the ten-character Team ID from the final parenthesized suffix.

- [ ] **Step 2: Build and verify the signed Universal app**

```bash
IDENTITY="$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) [A-F0-9]+ "(Developer ID Application:.*)"/\1/p')"
TEAM_ID="$(printf '%s\n' "$IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
DEVELOPER_ID_APPLICATION="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  scripts/build-developer-id-release.sh

lipo -archs MacFanControl.app/Contents/MacOS/MacFanControl
lipo -archs MacFanControl.app/Contents/Resources/MacFanControlHelper
codesign --verify --strict --verbose=2 MacFanControl.app
```

Expected: both binaries report `arm64 x86_64`; signature verification exits zero.

- [ ] **Step 3: Perform local Helper smoke testing**

Register the LaunchDaemon from the signed app, approve it in System Settings, confirm XPC version/fan-data calls, set one fan within its valid range, restore automatic mode, quit the app, and confirm the fan returns to system control. Confirm an unsigned test client cannot connect.

- [ ] **Step 4: Notarize only after the user confirms the keychain profile exists**

```bash
scripts/notarize-release.sh MacFanControl.app 1.2.0 MacFanControl-Notary
```

Expected: notarization status `Accepted`, stapler validation succeeds, Gatekeeper assessment succeeds, and the final ZIP plus SHA-256 file exist.

- [ ] **Step 5: Run final verification**

```bash
swift test
swift build -c release
bash Tests/DeveloperIDReleaseTests.sh
git diff --check
git status --short
```

Expected: all automated tests/builds pass and only intentional release artifacts are ignored.

- [ ] **Step 6: Commit any validation-only corrections**

If no correction was required, skip this commit. If a correction was required, stage only the files touched for that defect and commit:

```bash
git commit -m "fix: complete Developer ID release validation"
```

Do not create or upload a GitHub Release until the user explicitly requests publication of the resulting version.
