import XCTest
@testable import HelperIPC

final class ReplyGateTests: XCTestCase {
    func testFirstReplyWins() async {
        let gate = ReplyGate<Int>()

        gate.resolve(41)
        gate.resolve(99)

        let result = await gate.wait(timeout: .seconds(1), fallback: -1)
        XCTAssertEqual(result, 41)
    }

    func testTimeoutReturnsFallback() async {
        let gate = ReplyGate<String>()

        let result = await gate.wait(timeout: .milliseconds(20), fallback: "timeout")

        XCTAssertEqual(result, "timeout")
    }

    func testResolveBeforeWaitReturnsResolvedValue() async {
        let gate = ReplyGate<String>()
        gate.resolve("ready")

        let result = await gate.wait(timeout: .seconds(1), fallback: "timeout")

        XCTAssertEqual(result, "ready")
    }

    func testReplyRacingTimeoutCompletesExactlyOnce() async {
        for iteration in 0..<100 {
            let gate = ReplyGate<Int>()
            let result = await withTaskGroup(of: Void.self, returning: Int.self) { group in
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(1))
                    gate.resolve(iteration)
                }
                let value = await gate.wait(timeout: .milliseconds(1), fallback: -1)
                await group.waitForAll()
                return value
            }
            XCTAssertTrue(result == iteration || result == -1)
        }
    }
}
