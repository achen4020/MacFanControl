import XCTest

final class AppLifecycleSourceTests: XCTestCase {
    func testTerminationResetsThroughFanControllerBeforeReplyingOnce() throws {
        let source = try appSource()

        XCTAssertTrue(source.contains("await FanController.shared.resetAllFansToAuto()"))
        XCTAssertFalse(source.contains("await SMCHelperClient.shared.resetAllFansToAuto()"))
        XCTAssertTrue(source.contains("guard !terminationReplyPending else { return .terminateLater }"))
        XCTAssertEqual(source.components(separatedBy: "reply(toApplicationShouldTerminate: true)").count - 1, 1)
    }

    private func appSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/MacFanControlApp.swift"),
            encoding: .utf8
        )
    }
}
