import Foundation
import XCTest
@testable import ScreenshotKit

final class ScreenshotHotKeyStoreTests: XCTestCase {
    func testStoreRoundTripsCustomHotKey() throws {
        let suiteName = "ScreenshotHotKeyStoreTests.roundTrip"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = ScreenshotHotKeyStore(defaults: defaults)
        let value = ScreenshotHotKey(keyCode: 1, modifiers: [.command, .shift])

        try store.save(value)

        XCTAssertEqual(store.load(), value)
    }

    func testStoreFallsBackToDefaultForMissingValue() throws {
        let suiteName = "ScreenshotHotKeyStoreTests.missing"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(ScreenshotHotKeyStore(defaults: defaults).load(), .default)
    }

    func testStoreRejectsHotKeyWithoutModifier() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "ScreenshotHotKeyStoreTests.validation")
        )
        let store = ScreenshotHotKeyStore(defaults: defaults)

        XCTAssertThrowsError(
            try store.save(ScreenshotHotKey(keyCode: 0, modifiers: []))
        ) { error in
            XCTAssertEqual(error as? ScreenshotHotKeyError, .missingModifier)
        }
    }

    func testHotKeyDisplayTextUsesMacModifierSymbols() {
        XCTAssertEqual(ScreenshotHotKey.default.displayText, "⌃⇧A")
        XCTAssertEqual(
            ScreenshotHotKey(keyCode: 1, modifiers: [.command, .option]).displayText,
            "⌥⌘S"
        )
    }
}
