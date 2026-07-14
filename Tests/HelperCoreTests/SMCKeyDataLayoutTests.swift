import XCTest
import SMCKit

final class SMCKeyDataLayoutTests: XCTestCase {
    func testKeyDataMatchesAppleSMCUserClientABI() {
        XCTAssertEqual(MemoryLayout<SMCKeyDataKeyInfo>.size, 12)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.result), 40)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.data8), 42)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.bytes), 48)
    }

    func testValueKeepsMetadataFromKeyInfoResponse() {
        var keyInfo = SMCKeyDataKeyInfo()
        keyInfo.dataSize = 4
        keyInfo.dataType = "flt ".smcKey
        var response = SMCKeyData()
        response.bytes.0 = 0
        response.bytes.1 = 0
        response.bytes.2 = 122
        response.bytes.3 = 68

        let value = SMCValue(keyInfo: keyInfo, data: response)

        XCTAssertEqual(value.dataSize, 4)
        XCTAssertEqual(value.dataType, "flt ".smcKey)
        XCTAssertEqual(value.bytes.2, 122)
    }

    func testFloatValueDecodesFanSpeedAndTemperature() {
        var value = SMCValue()
        value.dataSize = 4
        value.dataType = "flt ".smcKey
        value.bytes.0 = 0
        value.bytes.1 = 0
        value.bytes.2 = 122
        value.bytes.3 = 68

        XCTAssertEqual(value.toFanSpeed(), 1_000)
        guard let temperature = value.toTemperature() else {
            return XCTFail("Expected float temperature")
        }
        XCTAssertEqual(temperature, 1_000, accuracy: 0.01)
    }

    func testLegacyFPE2ValueStillDecodesFanSpeed() {
        var value = SMCValue()
        value.dataSize = 2
        value.dataType = "fpe2".smcKey
        value.bytes.0 = 15
        value.bytes.1 = 160

        XCTAssertEqual(value.toFanSpeed(), 1_000)
    }

    func testFanSpeedEncodingMatchesSMCDataType() {
        let floatValue = SMCValue.fanSpeed(1_000, dataType: "flt ".smcKey)
        XCTAssertEqual(floatValue?.dataSize, 4)
        XCTAssertEqual(floatValue?.bytes.0, 0)
        XCTAssertEqual(floatValue?.bytes.1, 0)
        XCTAssertEqual(floatValue?.bytes.2, 122)
        XCTAssertEqual(floatValue?.bytes.3, 68)

        let fpe2Value = SMCValue.fanSpeed(1_000, dataType: "fpe2".smcKey)
        XCTAssertEqual(fpe2Value?.dataSize, 2)
        XCTAssertEqual(fpe2Value?.bytes.0, 15)
        XCTAssertEqual(fpe2Value?.bytes.1, 160)

        XCTAssertNil(SMCValue.fanSpeed(1_000, dataType: "ui16".smcKey))
    }
}
