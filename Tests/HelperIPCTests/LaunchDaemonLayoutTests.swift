import XCTest

final class LaunchDaemonLayoutTests: XCTestCase {
    func testLaunchDaemonUsesBundleProgramAndMachService() throws {
        let plist = try loadPlist()

        XCTAssertEqual(plist["Label"] as? String, "com.macfancontrol.helper")
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/Resources/MacFanControlHelper")
        XCTAssertEqual((plist["MachServices"] as? [String: Bool])?["com.macfancontrol.helper"], true)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
    }

    func testLaunchDaemonContainsNoLegacyAbsoluteProgramPath() throws {
        let plist = try loadPlist()
        let serialized = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let text = try XCTUnwrap(String(data: serialized, encoding: .utf8))

        XCTAssertNil(plist["Program"])
        XCTAssertNil(plist["ProgramArguments"])
        XCTAssertFalse(text.contains("/Library/PrivilegedHelperTools"))
    }

    private func loadPlist() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("Helper/com.macfancontrol.helper.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
