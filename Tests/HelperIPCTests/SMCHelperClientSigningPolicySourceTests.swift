import XCTest

final class SMCHelperClientSigningPolicySourceTests: XCTestCase {
    func testClientPinsHelperIdentifierAndCurrentTeamBeforeActivation() throws {
        let source = try clientSource()

        XCTAssertTrue(source.contains("CurrentCodeSignature.teamIdentifier()"))
        XCTAssertTrue(source.contains("identifier: helperBundleIdentifier"))
        XCTAssertTrue(source.contains("connection.setCodeSigningRequirement(requirement)"))

        let requirementOffset = try XCTUnwrap(source.range(of: "connection.setCodeSigningRequirement(requirement)")?.lowerBound)
        let activationOffset = try XCTUnwrap(source.range(of: "connection.activate()")?.lowerBound)
        XCTAssertLessThan(requirementOffset, activationOffset)
    }

    func testIdentifierOnlyPolicyRequiresExplicitLocalUnsignedBuildFlag() throws {
        let source = try clientSource()

        XCTAssertTrue(source.contains("#if DEBUG && LOCAL_UNSIGNED_XPC"))
        XCTAssertFalse(source.contains("#if DEBUG\n"))
        XCTAssertTrue(source.contains("local unsigned XPC mode"))
    }

    private func clientSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("Sources/SMCHelperClient.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
