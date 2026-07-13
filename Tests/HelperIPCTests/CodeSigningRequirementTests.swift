import XCTest
@testable import HelperIPC

final class CodeSigningRequirementTests: XCTestCase {
    func testBuildsRequirementBoundToIdentifierAndTeamID() throws {
        let requirement = try XCTUnwrap(
            CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "ABCDE12345")
        )

        XCTAssertEqual(
            requirement.text,
            "anchor apple generic and identifier \"com.macfancontrol.app\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testRejectsInvalidIdentifiers() {
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app injected", teamID: "ABCDE12345"))
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app\n", teamID: "ABCDE12345"))
        XCTAssertNil(CodeSigningRequirement(identifier: "", teamID: "ABCDE12345"))
    }

    func testRejectsInvalidTeamIDs() {
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "abcde12345"))
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "ABCDE12345\n"))
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "ABCDE1234"))
        XCTAssertNil(CodeSigningRequirement(identifier: "com.macfancontrol.app", teamID: "ABCDE123456"))
    }
}
