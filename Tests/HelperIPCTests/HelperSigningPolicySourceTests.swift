import XCTest

final class HelperSigningPolicySourceTests: XCTestCase {
    func testIdentifierOnlyPolicyRequiresExplicitLocalUnsignedBuildFlag() throws {
        let source = try helperMainSource()

        XCTAssertTrue(source.contains("#if DEBUG && LOCAL_UNSIGNED_XPC"))
        XCTAssertFalse(source.contains("#if DEBUG\n"))
        XCTAssertTrue(source.contains("local unsigned XPC mode"))
    }

    private func helperMainSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("Helper/main.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
