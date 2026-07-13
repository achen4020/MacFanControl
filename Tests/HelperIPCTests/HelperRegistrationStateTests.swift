import XCTest
@testable import HelperIPC

final class HelperRegistrationStateTests: XCTestCase {
    func testRegistrationStateActionsAreActionable() {
        XCTAssertEqual(HelperRegistrationState.notRegistered.actionTitle, "安装风扇控制服务")
        XCTAssertEqual(HelperRegistrationState.requiresApproval.actionTitle, "打开系统设置")
        XCTAssertNil(HelperRegistrationState.notFound.actionTitle)
        XCTAssertNil(HelperRegistrationState.enabled.actionTitle)
    }

    func testRegistrationStateMessagesDescribeCurrentState() {
        XCTAssertEqual(HelperRegistrationState.notRegistered.message, "需要安装风扇控制服务")
        XCTAssertEqual(HelperRegistrationState.requiresApproval.message, "需要在系统设置中批准风扇控制服务")
        XCTAssertEqual(HelperRegistrationState.notFound.message, "应用不完整，请重新下载或安装")
        XCTAssertEqual(HelperRegistrationState.enabled.message, "风扇控制服务已启用")
    }
}
