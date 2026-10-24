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
