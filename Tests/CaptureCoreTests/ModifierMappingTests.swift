import XCTest
@testable import CaptureCore

final class ModifierMappingTests: XCTestCase {
    func testCommandControlSwapPreservesSidesAndKeyUps() {
        var translator = ModifierTranslator(mapping: .macCopyPaste)
        for (source, target): (UInt16, UInt16) in [(55,59),(54,62),(59,55),(62,54),(58,58),(61,61),(56,56),(60,60)] {
            XCTAssertEqual(translator.translate(KeyStroke(key: source, down: true)), KeyStroke(key: target, down: true))
            XCTAssertEqual(translator.translate(KeyStroke(key: source, down: false)), KeyStroke(key: target, down: false))
        }
    }
    func testSharedTargetsStayHeldUntilEveryPhysicalKeyIsReleased() {
        var mapping = ModifierMapping.standard
        mapping.command = .control
        var translator = ModifierTranslator(mapping: mapping)
        XCTAssertEqual(translator.translate(KeyStroke(key: 55, down: true)), KeyStroke(key: 59, down: true))
        XCTAssertNil(translator.translate(KeyStroke(key: 59, down: true)))
        XCTAssertNil(translator.translate(KeyStroke(key: 55, down: false)))
        XCTAssertEqual(translator.translate(KeyStroke(key: 59, down: false)), KeyStroke(key: 59, down: false))
    }
    func testDisabledModifierAndRepeatedTransitionsAreIgnored() {
        var mapping = ModifierMapping.standard
        mapping.option = .disabled
        var translator = ModifierTranslator(mapping: mapping)
        XCTAssertNil(translator.translate(KeyStroke(key: 58, down: true)))
        XCTAssertNil(translator.translate(KeyStroke(key: 58, down: false)))
        XCTAssertNotNil(translator.translate(KeyStroke(key: 55, down: true)))
        XCTAssertNil(translator.translate(KeyStroke(key: 55, down: true)))
        translator.reset()
        XCTAssertNil(translator.translate(KeyStroke(key: 55, down: false)))
        XCTAssertNotNil(translator.translate(KeyStroke(key: 55, down: true)))
    }
    func testTypingCapsLockAndReleaseShortcutStayPhysical() {
        var translator = ModifierTranslator(mapping: .macCopyPaste)
        for code: UInt16 in [0, 5, 48, 53, 57, 123] {
            for down in [true, false] {
                let event = KeyStroke(key: code, down: down, repeating: true)
                XCTAssertEqual(translator.translate(event), event)
            }
        }
        XCTAssertTrue(KeyboardShortcut.default.matches(keyCode: 5, flags: [.maskControl, .maskAlternate, .maskCommand]))
    }
    func testSettingsRoundTripAndWindowsDesktopChord() throws {
        let mapping = ModifierMapping.macCopyPaste
        XCTAssertEqual(try JSONDecoder().decode(ModifierMapping.self, from: JSONEncoder().encode(mapping)), mapping)
        XCTAssertEqual(WindowsAction.desktopLeft.keys.prefix(3).map(\.key), [59,55,123])
        XCTAssertEqual(WindowsAction.desktopRight.keys.prefix(3).map(\.key), [59,55,124])
    }
}

final class GestureLiftTests: XCTestCase {
    private func points(_ count: Int, x: Double) -> [TouchPoint] {
        (0..<count).map { TouchPoint(id: $0, x: x, y: 0.5) }
    }
    func testPartialLiftCommitsLastThreeFingerMovementOnlyOnce() {
        var gesture = TrackpadGesture()
        _ = gesture.update(points(3, x: 0.4))
        XCTAssertNil(gesture.update(points(3, x: 0.52)))
        XCTAssertEqual(gesture.update(points(2, x: 0.52), ended: true), .desktopRight)
        XCTAssertNil(gesture.update([], ended: true))
    }
    func testEmptyLiftCommitsButCancellationAndFourthFingerDoNot() {
        var gesture = TrackpadGesture()
        _ = gesture.update(points(3, x: 0.5))
        _ = gesture.update(points(3, x: 0.3))
        XCTAssertEqual(gesture.update([], ended: true), .desktopLeft)
        _ = gesture.update(points(3, x: 0.5))
        _ = gesture.update(points(3, x: 0.3))
        XCTAssertNil(gesture.update([], ended: true, isCancelled: true))
        _ = gesture.update(points(3, x: 0.5))
        _ = gesture.update(points(3, x: 0.3))
        _ = gesture.update(points(4, x: 0.3))
        XCTAssertNil(gesture.update([], ended: true))
    }
}
