import XCTest
@testable import MacFanControlHelperCore

final class LegacyHelperRemovalTests: XCTestCase {
    func testBootsOutBeforeDeletingOnlyFixedLegacyPaths() {
        let recorder = LegacyOperationRecorder()
        let remover = LegacyHelperRemover(executor: recorder, fileRemover: recorder)

        let result = remover.remove()

        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
        XCTAssertEqual(recorder.operations, [
            .execute(
                executable: "/bin/launchctl",
                arguments: [
                    "bootout",
                    "system",
                    "/Library/LaunchDaemons/com.macfancontrol.helper.plist"
                ]
            ),
            .execute(
                executable: "/bin/launchctl",
                arguments: [
                    "bootout",
                    "system",
                    "/Library/LaunchDaemons/com.macfancontrol.smchelper.plist"
                ]
            ),
            .remove("/Library/LaunchDaemons/com.macfancontrol.helper.plist"),
            .remove("/Library/PrivilegedHelperTools/com.macfancontrol.helper"),
            .remove("/Library/LaunchDaemons/com.macfancontrol.smchelper.plist"),
            .remove("/Library/PrivilegedHelperTools/com.macfancontrol.smchelper"),
            .remove("/var/run/com.macfancontrol.smchelper.sock")
        ])
    }

    func testServiceNotLoadedIsNonfatalAndStillDeletesLegacyFiles() {
        let recorder = LegacyOperationRecorder()
        recorder.commandResult = .init(
            terminationStatus: 3,
            output: "Boot-out failed: 3: Could not find service"
        )
        let remover = LegacyHelperRemover(executor: recorder, fileRemover: recorder)

        let result = remover.remove()

        XCTAssertTrue(result.success)
        XCTAssertEqual(recorder.operations.filter(\.isRemoval).count, 5)
    }

    func testFatalBootoutFailureDoesNotDeleteAnything() {
        let recorder = LegacyOperationRecorder()
        recorder.commandResult = .init(
            terminationStatus: 5,
            output: "Boot-out failed: 5: Input/output error"
        )
        let remover = LegacyHelperRemover(executor: recorder, fileRemover: recorder)

        let result = remover.remove()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "legacy_bootout_failed")
        XCTAssertEqual(recorder.operations.filter(\.isRemoval), [])
    }

    func testFileRemovalFailureIsReportedAndRemainingFixedPathsAreAttempted() {
        let recorder = LegacyOperationRecorder()
        recorder.failingRemovalPath = "/Library/PrivilegedHelperTools/com.macfancontrol.smchelper"
        let remover = LegacyHelperRemover(executor: recorder, fileRemover: recorder)

        let result = remover.remove()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "legacy_file_removal_failed")
        XCTAssertEqual(recorder.operations.filter(\.isRemoval).count, 5)
    }

    func testConcreteFileRemoverDeletesDanglingSymbolicLink() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let link = temporaryDirectory.appendingPathComponent("legacy.sock")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: temporaryDirectory.appendingPathComponent("missing-target")
        )

        try FileManagerLegacyFileRemover().removeItemIfPresent(atPath: link.path)

        XCTAssertThrowsError(try FileManager.default.attributesOfItem(atPath: link.path))
    }

    func testConcreteFileRemoverIgnoresMissingFile() throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path

        XCTAssertNoThrow(try FileManagerLegacyFileRemover().removeItemIfPresent(atPath: missingPath))
    }
}

private final class LegacyOperationRecorder: LegacyCommandExecuting, LegacyFileRemoving {
    enum Operation: Equatable {
        case execute(executable: String, arguments: [String])
        case remove(String)

        var isRemoval: Bool {
            if case .remove = self { return true }
            return false
        }
    }

    var operations: [Operation] = []
    var commandResult = LegacyCommandResult(terminationStatus: 0, output: "")
    var failingRemovalPath: String?

    func execute(executable: String, arguments: [String]) throws -> LegacyCommandResult {
        operations.append(.execute(executable: executable, arguments: arguments))
        return commandResult
    }

    func removeItemIfPresent(atPath path: String) throws {
        operations.append(.remove(path))
        if path == failingRemovalPath {
            throw LegacyTestError.removalFailed
        }
    }
}

private enum LegacyTestError: Error {
    case removalFailed
}
