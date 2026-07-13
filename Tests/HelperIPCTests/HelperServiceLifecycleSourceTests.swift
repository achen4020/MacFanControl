import XCTest

final class HelperServiceLifecycleSourceTests: XCTestCase {
    func testManagerUsesBundledDaemonAndMapsEveryServiceStatus() throws {
        let source = try readSource("Sources/HelperServiceManager.swift")

        XCTAssertTrue(source.contains(#"SMAppService.daemon(plistName: "com.macfancontrol.helper.plist")"#))
        XCTAssertTrue(source.contains("case .notRegistered:"))
        XCTAssertTrue(source.contains("case .enabled:"))
        XCTAssertTrue(source.contains("case .requiresApproval:"))
        XCTAssertTrue(source.contains("case .notFound:"))
        XCTAssertTrue(source.contains("SMAppService.openSystemSettingsLoginItems()"))
    }

    func testAppHasNoAutomaticHelperInstallationOrTransitionalPlaceholder() throws {
        let controller = try readSource("Sources/FanController.swift")
        let menu = try readSource("Sources/MenuBarViews.swift")
        let settings = try readSource("Sources/SettingsViews.swift")
        let client = try readSource("Sources/SMCHelperClient.swift")

        XCTAssertFalse(controller.contains("checkAndInstallHelper"))
        XCTAssertFalse(menu.contains("自动检查并安装 helper"))
        XCTAssertFalse(settings.contains("服务管理将在 SMAppService 接管后启用"))
        XCTAssertFalse(client.contains("Helper 安装将在 SMAppService 接管后启用"))
    }

    private func readSource(_ path: String) throws -> String {
        let fileURL = repositoryRoot.appendingPathComponent(path)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
