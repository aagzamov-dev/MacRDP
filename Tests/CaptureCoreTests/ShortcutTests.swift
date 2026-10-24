import XCTest
import CoreGraphics
@testable import CaptureCore

final class ShortcutTests: XCTestCase {
    func testDefaultMatchesOnlyItsExactPhysicalCombination() {
        let shortcut = KeyboardShortcut.default
        XCTAssertNil(shortcut.validationError)
        XCTAssertEqual(shortcut.displayName, "⌃⌥⌘G")
        XCTAssertTrue(shortcut.matches(keyCode: 5, flags: [.maskControl, .maskAlternate, .maskCommand]))
        XCTAssertFalse(shortcut.matches(keyCode: 4, flags: [.maskControl, .maskAlternate, .maskCommand]))
        XCTAssertFalse(shortcut.matches(keyCode: 5, flags: [.maskControl, .maskCommand]))
        XCTAssertFalse(shortcut.matches(keyCode: 5, flags: [.maskControl, .maskAlternate, .maskCommand, .maskShift]))
        XCTAssertTrue(shortcut.matches(keyCode: 5, flags: [.maskControl, .maskAlternate, .maskCommand, .maskAlphaShift]))
    }

    func testCustomSimpleShortcutIsValidAndRoundTrips() throws {
        let shortcut = KeyboardShortcut(keyCode: 4, modifiers: CGEventFlags.maskControl.rawValue, keyName: "H")
        XCTAssertNil(shortcut.validationError)
        XCTAssertEqual(shortcut.displayName, "⌃H")
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
    }

    func testTypingKeysAndBareModifiersAreRejected() {
        XCTAssertNotNil(KeyboardShortcut(keyCode: 4, modifiers: 0, keyName: "H").validationError)
        XCTAssertNotNil(KeyboardShortcut(keyCode: 4, modifiers: CGEventFlags.maskShift.rawValue, keyName: "H").validationError)
        for code: UInt16 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            XCTAssertNotNil(KeyboardShortcut(keyCode: code, modifiers: CGEventFlags.maskControl.rawValue, keyName: "Modifier").validationError)
        }
    }

    func testForceQuitAndRequiredTabCombinationsCannotBecomeToggle() {
        let forceQuit = KeyboardShortcut(keyCode: 53,
            modifiers: CGEventFlags([.maskCommand, .maskAlternate]).rawValue, keyName: "Escape")
        XCTAssertNotNil(forceQuit.validationError)
        for flags: CGEventFlags in [.maskCommand, .maskAlternate, .maskControl, [.maskControl, .maskShift]] {
            XCTAssertNotNil(KeyboardShortcut(keyCode: 48, modifiers: flags.rawValue, keyName: "Tab").validationError)
        }
    }

    func testToggleWaitsForBothPrimaryKeyAndAllModifiersToLift() {
        var toggle = KeyboardToggle()
        toggle.request()
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: true, modifiersHeld: false, eligible: true))
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: false, modifiersHeld: true, eligible: true))
        XCTAssertTrue(toggle.takeIfReleased(keyHeld: false, modifiersHeld: false, eligible: true))
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: false, modifiersHeld: false, eligible: true))
    }

    func testFocusLossCancelsQueuedToggleWithoutSilentRecapture() {
        var toggle = KeyboardToggle()
        toggle.request()
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: false, modifiersHeld: false, eligible: false))
        XCTAssertFalse(toggle.pending)
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: false, modifiersHeld: false, eligible: true))
        toggle.request()
        toggle.cancel()
        XCTAssertFalse(toggle.takeIfReleased(keyHeld: false, modifiersHeld: false, eligible: true))
    }
}
