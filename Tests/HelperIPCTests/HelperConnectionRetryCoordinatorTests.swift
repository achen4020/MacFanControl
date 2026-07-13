import XCTest
@testable import HelperIPC

final class HelperConnectionRetryCoordinatorTests: XCTestCase {
    func testNotFoundDisconnectsAndAttemptsConnection() async {
        let recorder = RetryRecorder()

        let attempted = await HelperConnectionRetryCoordinator.retry(
            for: .notFound,
            disconnect: { await recorder.recordDisconnect() },
            request: { await recorder.recordRequest() }
        )

        XCTAssertTrue(attempted)
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, .init(disconnects: 1, requests: 1))
    }

    func testEnabledDisconnectsAndAttemptsConnection() async {
        let recorder = RetryRecorder()

        let attempted = await HelperConnectionRetryCoordinator.retry(
            for: .enabled,
            disconnect: { await recorder.recordDisconnect() },
            request: { await recorder.recordRequest() }
        )

        XCTAssertTrue(attempted)
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, .init(disconnects: 1, requests: 1))
    }

    func testRegistrationActionsDoNotAttemptConnection() async {
        for state in [HelperRegistrationState.notRegistered, .requiresApproval] {
            let recorder = RetryRecorder()

            let attempted = await HelperConnectionRetryCoordinator.retry(
                for: state,
                disconnect: { await recorder.recordDisconnect() },
                request: { await recorder.recordRequest() }
            )

            XCTAssertFalse(attempted)
            let snapshot = await recorder.snapshot()
            XCTAssertEqual(snapshot, .init(disconnects: 0, requests: 0))
        }
    }
}

private actor RetryRecorder {
    struct Snapshot: Equatable {
        let disconnects: Int
        let requests: Int
    }

    private var disconnects = 0
    private var requests = 0

    func recordDisconnect() {
        disconnects += 1
    }

    func recordRequest() {
        requests += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(disconnects: disconnects, requests: requests)
    }
}
