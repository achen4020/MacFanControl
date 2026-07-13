import Foundation
import XCTest
@testable import HelperIPC

final class HelperProtocolTests: XCTestCase {
    func testProtocolCanConstructXPCInterfaceAndExposeRequiredSelectors() {
        let interface = NSXPCInterface(with: HelperToolProtocol.self)

        XCTAssertNotNil(interface)
        XCTAssertNotNil(
            protocol_getMethodDescription(
                HelperToolProtocol.self,
                #selector(HelperToolProtocol.getFanData(reply:)),
                true,
                true
            ).name
        )
        XCTAssertNotNil(
            protocol_getMethodDescription(
                HelperToolProtocol.self,
                #selector(HelperToolProtocol.setFanSpeed(index:rpm:reply:)),
                true,
                true
            ).name
        )
    }
}
