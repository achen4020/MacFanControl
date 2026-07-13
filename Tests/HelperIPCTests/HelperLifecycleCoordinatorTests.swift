import XCTest
@testable import HelperIPC

final class HelperLifecycleCoordinatorTests: XCTestCase {
    func testCleanupFailurePreventsUnregister() async {
        let recorder = UninstallRecorder(cleanupSucceeds: false)

        let result = await HelperUninstallCoordinator.uninstall(
            cleanup: { await recorder.cleanup() },
            unregister: { try await recorder.unregister() }
        )

        XCTAssertEqual(result, .cleanupFailed)
        let counts = await recorder.counts()
        XCTAssertEqual(counts.cleanup, 1)
        XCTAssertEqual(counts.unregister, 0)
    }

    func testCleanupSuccessAllowsUnregister() async {
        let recorder = UninstallRecorder(cleanupSucceeds: true)

        let result = await HelperUninstallCoordinator.uninstall(
            cleanup: { await recorder.cleanup() },
            unregister: { try await recorder.unregister() }
        )

        XCTAssertEqual(result, .success)
        let counts = await recorder.counts()
        XCTAssertEqual(counts.cleanup, 1)
        XCTAssertEqual(counts.unregister, 1)
    }

    func testLifecycleGateRejectsConcurrentOperationUntilFirstEnds() async {
        let gate = HelperLifecycleGate()

        let first = await gate.tryBegin()
        let overlapping = await gate.tryBegin()
        XCTAssertTrue(first)
        XCTAssertFalse(overlapping)
        await gate.end()
        let afterEnd = await gate.tryBegin()
        XCTAssertTrue(afterEnd)
        await gate.end()
    }
}

private actor UninstallRecorder {
    let cleanupSucceeds: Bool
    private var cleanupCount = 0
    private var unregisterCount = 0

    init(cleanupSucceeds: Bool) {
        self.cleanupSucceeds = cleanupSucceeds
    }

    func cleanup() -> Bool {
        cleanupCount += 1
        return cleanupSucceeds
    }

    func unregister() throws {
        unregisterCount += 1
    }

    func counts() -> (cleanup: Int, unregister: Int) {
        (cleanupCount, unregisterCount)
    }
}
