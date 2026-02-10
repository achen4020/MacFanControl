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
        // 主应用
        .executableTarget(
            name: "MacFanControl",
            dependencies: ["SMCKit", "MacFanControlCore"],
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
            dependencies: ["SMCKit"],
            path: "Helper",
            exclude: ["Info.plist", "com.macfancontrol.helper.plist"],
            sources: ["main.swift", "HelperProtocol.swift"],
            linkerSettings: [
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "CoreFoundation"])
            ]
        ),
        // 单元测试
        .testTarget(
            name: "MacFanControlCoreTests",
            dependencies: ["MacFanControlCore"],
            path: "Tests/MacFanControlCoreTests"
        )
    ]
)
