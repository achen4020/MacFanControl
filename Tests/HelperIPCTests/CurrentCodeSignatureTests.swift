import Security
import XCTest
@testable import HelperIPC

final class CurrentCodeSignatureTests: XCTestCase {
    func testParsesTeamIdentifierFromSigningInformation() throws {
        let teamID = try CurrentCodeSignature.teamIdentifier(
            from: [kSecCodeInfoTeamIdentifier as String: "ABCDE12345"]
        )

        XCTAssertEqual(teamID, "ABCDE12345")
    }

    func testMissingTeamIdentifierReturnsStableError() {
        XCTAssertThrowsError(try CurrentCodeSignature.teamIdentifier(from: [:])) { error in
            XCTAssertEqual(error as? CurrentCodeSignatureError, .missingTeamIdentifier)
        }
    }

    func testNonStringTeamIdentifierReturnsStableError() {
        XCTAssertThrowsError(
            try CurrentCodeSignature.teamIdentifier(
                from: [kSecCodeInfoTeamIdentifier as String: 123]
            )
        ) { error in
            XCTAssertEqual(error as? CurrentCodeSignatureError, .invalidTeamIdentifier)
        }
    }
}
