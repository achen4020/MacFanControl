// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacFanControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacFanControl", targets: ["MacFanControl"]),
        .executable(name: "MacFanControlHelper", targets: ["MacFanControlHelper"])
    ],
    targets: [
        // 共享 SMC 访问层
        .target(
            name: "SMCKit",
            dependencies: [],
            path: "Shared",
            linkerSettings: [
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "CoreFoundation"])
            ]
        ),
        // 核心数据模型和协议（可测试）
        .target(
            name: "MacFanControlCore",
            dependencies: [],
            path: "Core"
        ),
        // 截图、编辑和输出核心
        .target(
            name: "ScreenshotKit",
            dependencies: [],
            path: "ScreenshotKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .target(
            name: "HelperIPC",
            dependencies: [],
            path: "HelperIPC",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "MacFanControlHelperCore",
            dependencies: ["SMCKit", "HelperIPC"],
            path: "HelperCore"
        ),
        // 主应用
        .executableTarget(
            name: "MacFanControl",
            dependencies: ["SMCKit", "MacFanControlCore", "ScreenshotKit", "HelperIPC"],
            path: "Sources",
            exclude: ["Info.plist", "MacFanControl.entitlements"],
            linkerSettings: [
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "CoreFoundation"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
                .unsafeFlags(["-framework", "Security"])
            ]
        ),
        // Helper Tool
        .executableTarget(
            name: "MacFanControlHelper",
            dependencies: ["SMCKit", "HelperIPC", "MacFanControlHelperCore"],
            path: "Helper",
            exclude: ["Info.plist", "com.macfancontrol.helper.v2.plist"],
            sources: ["main.swift"],
            linkerSettings: [
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "CoreFoundation"]),
                .linkedFramework("Security")
            ]
        ),
        // 单元测试
        .testTarget(
            name: "MacFanControlCoreTests",
            dependencies: ["MacFanControlCore"],
            path: "Tests/MacFanControlCoreTests"
        ),
        .testTarget(
            name: "ScreenshotKitTests",
            dependencies: ["ScreenshotKit"],
            path: "Tests/ScreenshotKitTests"
        ),
        .testTarget(
            name: "HelperIPCTests",
            dependencies: ["HelperIPC"],
            path: "Tests/HelperIPCTests"
        ),
        .testTarget(
            name: "HelperCoreTests",
            dependencies: ["MacFanControlHelperCore", "HelperIPC", "SMCKit"],
            path: "Tests/HelperCoreTests"
        )
    ]
)
