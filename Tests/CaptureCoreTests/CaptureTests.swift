import XCTest
@testable import CaptureCore

final class CaptureTests: XCTestCase {

private func activeMachine() -> CaptureMachine {
    var machine = CaptureMachine()
    machine.verifyRelease()
    XCTAssertTrue(machine.arm(eligible: true, modifiersHeld: false))
    XCTAssertTrue(machine.activate(generation: machine.generation, eligible: true))
    return machine
}

func testCaptureRequiresVerifiedExitAndEligibility() {
    var machine = CaptureMachine()
    XCTAssertTrue(!machine.arm(eligible: true, modifiersHeld: false))
    machine.verifyRelease()
    XCTAssertTrue(!machine.arm(eligible: false, modifiersHeld: false))
    XCTAssertTrue(!machine.arm(eligible: true, modifiersHeld: true))
    XCTAssertTrue(machine.arm(eligible: true, modifiersHeld: false))
    let generation = machine.generation
    XCTAssertTrue(!machine.handle(KeyStroke(key: 0, down: true), generation: generation).consume)
    XCTAssertTrue(!machine.activate(generation: generation, eligible: false))
    XCTAssertTrue(machine.state == .local)
}

func testEscapeConsumesCompletingKeyAndReleasesModifiersOnce() {
    var machine = activeMachine()
    let generation = machine.generation
    for key: UInt16 in [55, 58, 59] {
        XCTAssertTrue(machine.handle(KeyStroke(key: key, down: true), generation: generation).keys.count == 1)
    }
    let result = machine.handle(KeyStroke(key: 5, down: true), generation: generation, escape: true)
    XCTAssertTrue(result.consume && result.released)
    XCTAssertTrue(Set(result.keys.map(\.key)) == [55, 58, 59])
    XCTAssertTrue(result.keys.allSatisfy { !$0.down })
    XCTAssertTrue(!result.keys.contains { $0.key == 5 })
    XCTAssertTrue(machine.pressed.isEmpty)
    XCTAssertTrue(machine.release().isEmpty)
    XCTAssertTrue(!machine.handle(KeyStroke(key: 5, down: false), generation: generation).consume)
}

func testForceQuitIsNotSwallowed() {
    var machine = activeMachine()
    let result = machine.handle(KeyStroke(key: 53, down: true), generation: machine.generation, forceQuit: true)
    XCTAssertTrue(result.released)
    XCTAssertTrue(!result.consume)
    XCTAssertTrue(machine.state == .local)
}

func testEventsNeverCrossCaptureGenerations() {
    var machine = activeMachine()
    let old = machine.generation
    _ = machine.handle(KeyStroke(key: 0, down: true), generation: old)
    _ = machine.release()
    XCTAssertTrue(machine.arm(eligible: true, modifiersHeld: false))
    XCTAssertTrue(machine.activate(generation: machine.generation, eligible: true))
    XCTAssertTrue(!machine.handle(KeyStroke(key: 0, down: false), generation: old).consume)
    XCTAssertTrue(machine.pressed.isEmpty)
    XCTAssertTrue(!machine.activate(generation: old, eligible: true))
    XCTAssertTrue(machine.state == .captured)
}

func testDuplicateDownsAndOrphanUpsAreNotForwarded() {
    var machine = activeMachine()
    let generation = machine.generation
    let down = KeyStroke(key: 0, down: true)
    XCTAssertTrue(machine.handle(down, generation: generation).keys == [down])
    XCTAssertTrue(machine.handle(down, generation: generation).keys.isEmpty)
    let repeated = KeyStroke(key: 0, down: true, repeating: true)
    XCTAssertTrue(machine.handle(repeated, generation: generation).keys == [repeated])
    XCTAssertTrue(machine.handle(KeyStroke(key: 0, down: false), generation: generation).keys.count == 1)
    XCTAssertTrue(machine.handle(KeyStroke(key: 0, down: false), generation: generation).keys.isEmpty)
}

func testReleaseClearsBothSidesOfModifiersAndButtonsOnEveryExit() {
    var machine = activeMachine()
    for _ in 0..<50 {
        let generation = machine.generation
        for key: UInt16 in [55, 54, 56, 60, 58, 61, 59, 62] {
            _ = machine.handle(KeyStroke(key: key, down: true), generation: generation)
        }
        machine.holdButton(0)
        machine.holdButton(1)
        XCTAssertTrue(machine.release().count == 8)
        XCTAssertTrue(machine.buttons.isEmpty && machine.pressed.isEmpty)
        XCTAssertTrue(machine.release().isEmpty)
        XCTAssertTrue(machine.arm(eligible: true, modifiersHeld: false))
        XCTAssertTrue(machine.activate(generation: machine.generation, eligible: true))
    }
}

private func fingers(_ count: Int, x: Double = 0.4, y: Double = 0.4) -> [TouchPoint] {
    (0..<count).map { TouchPoint(id: $0, x: x + Double($0) * 0.02, y: y) }
}

func testFourFingerMovementReleasesInAnyDirectionOnlyOnce() {
    for position in [(0.7, 0.4), (0.1, 0.4), (0.4, 0.7), (0.4, 0.1)] {
        var gesture = TrackpadGesture()
        XCTAssertTrue(gesture.update(fingers(4)) == nil)
        XCTAssertTrue(gesture.update(fingers(4, x: position.0, y: position.1)) == .release)
        XCTAssertTrue(gesture.update(fingers(4, x: position.0, y: position.1)) == nil)
    }
}

func testThreeFingerHorizontalActionCommitsOnLift() {
    var gesture = TrackpadGesture()
    XCTAssertTrue(gesture.update(fingers(3)) == nil)
    XCTAssertTrue(gesture.update(fingers(3, x: 0.7)) == nil)
    XCTAssertTrue(gesture.update(fingers(3, x: 0.7), ended: true) == .desktopRight)
    XCTAssertTrue(gesture.update(fingers(3, x: 0.7), ended: true) == nil)
    _ = gesture.update([])
    _ = gesture.update(fingers(3))
    XCTAssertTrue(gesture.update(fingers(3, x: 0.1), ended: true) == .desktopLeft)
}

func testFourthFingerPreventsPrematureWindowsAction() {
    var gesture = TrackpadGesture()
    _ = gesture.update(fingers(3))
    _ = gesture.update(fingers(3, x: 0.6))
    XCTAssertTrue(gesture.update(fingers(4, x: 0.6)) == nil)
    XCTAssertTrue(gesture.update(fingers(4, x: 0.8)) == .release)
}

func testCancelledAndVerticalThreeFingerGesturesDoNothing() {
    var gesture = TrackpadGesture()
    _ = gesture.update(fingers(3))
    XCTAssertTrue(gesture.update(fingers(3, y: 0.8), ended: true) == nil)
    gesture.reset()
    _ = gesture.update(fingers(3))
    XCTAssertTrue(gesture.update(fingers(3, x: 0.8), ended: true, isCancelled: true) == nil)
    XCTAssertTrue(gesture.update(fingers(3, x: 0.9), ended: true) == nil)
}

func testDesktopActionsHaveBalancedOrderedKeyTransitions() {
    for action in [WindowsAction.desktopLeft, .desktopRight] {
        let events = action.keys
        XCTAssertTrue(events.prefix(3).allSatisfy(\.down))
        XCTAssertTrue(events.suffix(3).allSatisfy { !$0.down })
        XCTAssertTrue(events.prefix(3).map(\.key) == events.suffix(3).reversed().map(\.key))
        XCTAssertTrue(events[0].key == 59 && events[1].key == 55)
    }
}

}
