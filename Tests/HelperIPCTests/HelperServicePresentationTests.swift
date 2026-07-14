import XCTest
@testable import HelperIPC

final class HelperServicePresentationTests: XCTestCase {
    func testEnabledButUnavailableShowsRetryInsteadOfSuccess() {
        let presentation = HelperServicePresentation(
            registrationState: .enabled,
            isConnectionAvailable: false
        )

        XCTAssertEqual(presentation.message, "服务已启用，但当前无法连接")
        XCTAssertEqual(presentation.action, .retryConnection)
        XCTAssertFalse(presentation.isSuccess)
    }

    func testEnabledAndAvailableShowsSuccessWithoutAction() {
        let presentation = HelperServicePresentation(
            registrationState: .enabled,
            isConnectionAvailable: true
        )

        XCTAssertEqual(presentation.message, "风扇控制服务已启用")
        XCTAssertNil(presentation.action)
        XCTAssertTrue(presentation.isSuccess)
    }

    func testRegistrationStatesExposeTheirSpecificActions() {
        XCTAssertEqual(presentation(.notRegistered).action, .register)
        XCTAssertEqual(presentation(.requiresApproval).action, .openApprovalSettings)
        XCTAssertEqual(presentation(.notFound).action, .register)
        XCTAssertEqual(presentation(.notFound).message, "风扇控制服务尚未注册")
    }

    private func presentation(_ state: HelperRegistrationState) -> HelperServicePresentation {
        HelperServicePresentation(registrationState: state, isConnectionAvailable: false)
    }
}
