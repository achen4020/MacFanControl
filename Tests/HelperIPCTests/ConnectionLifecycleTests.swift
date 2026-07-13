import XCTest
@testable import HelperIPC

private final class FakeInvalidatableConnection {
    private(set) var invalidationCount = 0

    func invalidate() {
        invalidationCount += 1
    }
}

final class ConnectionLifecycleTests: XCTestCase {
    func testTimeoutClearsAvailabilityAndInvalidatesConnection() {
        let connection = FakeInvalidatableConnection()
        let lifecycle = ConnectionLifecycle<FakeInvalidatableConnection> { $0.invalidate() }
        lifecycle.install(connection)
        lifecycle.markRoundTripSuccessful(connection)

        let accepted = lifecycle.acceptReply(from: connection, didReply: false)

        XCTAssertFalse(accepted)
        XCTAssertNil(lifecycle.current())
        XCTAssertFalse(lifecycle.isAvailable)
        XCTAssertEqual(connection.invalidationCount, 1)
    }

    func testRepeatedCleanupInvalidatesConnectionOnlyOnce() {
        let connection = FakeInvalidatableConnection()
        let lifecycle = ConnectionLifecycle<FakeInvalidatableConnection> { $0.invalidate() }
        lifecycle.install(connection)

        XCTAssertFalse(lifecycle.acceptReply(from: connection, didReply: false))
        XCTAssertFalse(lifecycle.acceptReply(from: connection, didReply: false))

        XCTAssertEqual(connection.invalidationCount, 1)
    }
}
