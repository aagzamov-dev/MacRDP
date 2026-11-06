import XCTest
@testable import CaptureCore

final class InputOwnershipTests: XCTestCase {
    func testNewSessionDefaultsToWindowsButRequiresEligibleDesktop() {
        var ownership = InputOwnership()
        XCTAssertEqual(ownership.mode, .windows)
        XCTAssertFalse(ownership.shouldResume(eligible: false))
        XCTAssertTrue(ownership.shouldResume(eligible: true))
    }
    func testSpaceSwipeWaitsForDepartureThenAutomaticallyReturns() {
        var ownership = InputOwnership()
        ownership.swipeToMac()
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        XCTAssertFalse(ownership.shouldResume(eligible: false))
        XCTAssertTrue(ownership.shouldResume(eligible: true))
        XCTAssertEqual(ownership.mode, .windows)
    }
    func testExplicitMacChoiceSurvivesClickFocusAndSpaceChanges() {
        var ownership = InputOwnership()
        ownership.select(.mac)
        XCTAssertFalse(ownership.shouldResume(eligible: false))
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        ownership.swipeToMac()
        XCTAssertFalse(ownership.shouldResume(eligible: false))
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        ownership.select(.windows)
        XCTAssertTrue(ownership.shouldResume(eligible: true))
    }
    func testFaultNeverAutomaticallyRecaptures() {
        var ownership = InputOwnership()
        ownership.fail()
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        XCTAssertFalse(ownership.shouldResume(eligible: false))
        XCTAssertFalse(ownership.shouldResume(eligible: true))
        ownership.select(.windows)
        XCTAssertTrue(ownership.shouldResume(eligible: true))
    }
    func testTemporaryDialogOrFullScreenTransitionPreservesWindowsChoice() {
        var ownership = InputOwnership()
        for _ in 0..<50 {
            XCTAssertFalse(ownership.shouldResume(eligible: false))
            XCTAssertTrue(ownership.shouldResume(eligible: true))
        }
    }
}

extension InputOwnershipTests {
func testMacModeKeepsSystemShortcutsLocalAndAllowsOrdinaryInput() {
    for key: UInt16 in [0, 9, 12, 48, 49] {
        XCTAssertTrue(RemoteKeyboardPolicy.keepsShortcutLocal(mode: .mac, key: key, command: true, control: false))
        XCTAssertTrue(!RemoteKeyboardPolicy.keepsShortcutLocal(mode: .windows, key: key, command: true, control: false))
        XCTAssertTrue(!RemoteKeyboardPolicy.keepsShortcutLocal(mode: .mac, key: key, command: false, control: false))
    }
    for key: UInt16 in 123...126 {
        XCTAssertTrue(RemoteKeyboardPolicy.keepsShortcutLocal(mode: .mac, key: key, command: false, control: true))
    }
    XCTAssertTrue(RemoteKeyboardPolicy.pastesMacText(mode: .mac, key: 9, command: true, control: false, option: false, shift: false))
    XCTAssertTrue(!RemoteKeyboardPolicy.pastesMacText(mode: .windows, key: 9, command: true, control: false, option: false, shift: false))
    XCTAssertTrue(!RemoteKeyboardPolicy.pastesMacText(mode: .mac, key: 9, command: true, control: false, option: false, shift: true))
}
}
