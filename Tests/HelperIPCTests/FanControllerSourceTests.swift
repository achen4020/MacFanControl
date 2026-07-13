import XCTest

final class FanControllerSourceTests: XCTestCase {
    func testApplyAutoControlGuardsAgainstReentryAtItsOwnEntryPoint() throws {
        let source = try controllerSource()
        let method = try XCTUnwrap(source.range(of: "private func applyAutoControl() async"))
        let suffix = source[method.lowerBound...]
        let nextMethod = suffix.range(of: "\n    func disableAutoControl() async")?.lowerBound ?? suffix.endIndex
        let body = suffix[..<nextMethod]

        XCTAssertTrue(body.contains("guard !isApplyingAutoControl"))
        XCTAssertTrue(body.contains("autoControlApplyGate.begin()"))
    }

    private func controllerSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/FanController.swift"),
            encoding: .utf8
        )
    }
}
