import XCTest
@testable import HelperIPC

final class CodeSigningRequirementTests: XCTestCase {
    func testBuildsRequirementBoundToIdentifierAndTeamID() throws {
        let requirement = try CodeSigningRequirement(
            identifier: "com.macfancontrol.app",
            teamID: "ABCDE12345"
        )

        XCTAssertEqual(
            requirement.text,
            "anchor apple generic and identifier \"com.macfancontrol.app\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testRejectsInvalidIdentifiers() {
        assertThrows(
            identifier: "com.macfancontrol.app injected",
            teamID: "ABCDE12345",
            expected: .invalidIdentifier
        )
        assertThrows(
            identifier: "com.macfancontrol.app\n",
            teamID: "ABCDE12345",
            expected: .invalidIdentifier
        )
        assertThrows(identifier: "", teamID: "ABCDE12345", expected: .invalidIdentifier)
    }

    func testRejectsInvalidTeamIDs() {
        assertThrows(identifier: "com.macfancontrol.app", teamID: "abcde12345", expected: .invalidTeamID)
        assertThrows(identifier: "com.macfancontrol.app", teamID: "ABCDE12345\n", expected: .invalidTeamID)
        assertThrows(identifier: "com.macfancontrol.app", teamID: "ABCDE1234", expected: .invalidTeamID)
        assertThrows(identifier: "com.macfancontrol.app", teamID: "ABCDE123456", expected: .invalidTeamID)
    }

    private func assertThrows(
        identifier: String,
        teamID: String,
        expected: CodeSigningRequirementError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CodeSigningRequirement(identifier: identifier, teamID: teamID),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? CodeSigningRequirementError, expected, file: file, line: line)
        }
    }
}
