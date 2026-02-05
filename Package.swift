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
        // 主应用
        .executableTarget(
            name: "MacFanControl",
            dependencies: [],
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
            dependencies: [],
            path: "Helper",
            exclude: ["Info.plist", "com.macfancontrol.helper.plist"],
            sources: ["main.swift", "SMC.swift", "HelperProtocol.swift"],
            linkerSettings: [
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "CoreFoundation"])
            ]
        )
    ]
)
