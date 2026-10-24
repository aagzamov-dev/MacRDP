import XCTest
@testable import CaptureCore

final class PCAndDisplayTests: XCTestCase {
    func testProfilesRoundTripWithoutPasswordsAndMigrateLegacyIdentity() throws {
        let suite = "MacRDP.profiles.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var pc = PCProfile(); pc.host = "office.example"; pc.username = "user"; pc.domain = "OFFICE"
        let legacy = try JSONEncoder().encode(pc)
        defaults.set(legacy, forKey: "savedPC")
        let store = PCStore(defaults: defaults)
        XCTAssertEqual(try store.load(), [pc])
        XCTAssertEqual(try store.load().first?.id, pc.id)
        var second = PCProfile(); second.host = "home.example"
        try store.save([pc, second])
        XCTAssertEqual(try store.load(), [pc, second])
        try store.save([second]); XCTAssertEqual(try store.load(), [second])
        let json = String(data: defaults.data(forKey: "pcs")!, encoding: .utf8)!
        XCTAssertFalse(json.contains("password"))
        defaults.set(Data("corrupt".utf8), forKey: "pcs")
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: "pcs"), Data("corrupt".utf8))
    }
    func testLegacyDefaultsAndConnectionValidation() throws {
        let pc = try JSONDecoder().decode(PCProfile.self, from: Data(#"{"host":"host"}"#.utf8))
        XCTAssertEqual(pc.port, "3389"); XCTAssertTrue(pc.optimizeRetina)
        XCTAssertNil(pc.validationError)
        var invalid = pc; invalid.port = "65536"; XCTAssertNotNil(invalid.validationError)
        invalid.port = "0"; XCTAssertNotNil(invalid.validationError)
        invalid.port = "3389"; invalid.host = "rdp://host"; XCTAssertNotNil(invalid.validationError)
        var renamed = pc; renamed.name = "Renamed"
        XCTAssertEqual(pc.credentialIdentity, renamed.credentialIdentity)
        renamed.host = "different"; XCTAssertNotEqual(pc.credentialIdentity, renamed.credentialIdentity)
    }
    func testRetinaBackingPixelsWindowsScaleAndPerformanceRemainSeparate() {
        let points = CGSize(width: 1512, height: 982), backing = CGSize(width: 3024, height: 1964)
        let retina = DisplayLayout(points: points, backing: backing, retina: true, scale: 0)
        XCTAssertEqual(retina.width, 3024); XCTAssertEqual(retina.height, 1964)
        XCTAssertEqual(retina.desktopScale, 200); XCTAssertEqual(retina.deviceScale, 100)
        let override = DisplayLayout(points: points, backing: backing, retina: true, scale: 150)
        XCTAssertEqual(override.width, retina.width); XCTAssertEqual(override.desktopScale, 150)
        let performance = DisplayLayout(points: points, backing: backing, retina: false, scale: 0)
        XCTAssertEqual(performance.width, 1512); XCTAssertEqual(performance.desktopScale, 100)
        let hostile = DisplayLayout(points: .zero, backing: CGSize(width: Double.greatestFiniteMagnitude, height: .infinity), retina: true, scale: 0)
        XCTAssertEqual(hostile.width, 8192); XCTAssertEqual(hostile.height, 200)
        let odd = DisplayLayout(points: CGSize(width: 801, height: 601), backing: .zero, retina: false, scale: 200)
        XCTAssertEqual(odd.width, 800)
    }
    func testLetterboxingCursorAndDragCoordinatesAtRetinaResolution() {
        let geometry = RemoteGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), remote: CGSize(width: 3000, height: 1800))
        XCTAssertEqual(geometry.imageRect, CGRect(x: 0, y: 100, width: 1000, height: 600))
        XCTAssertNil(geometry.point(CGPoint(x: 500, y: 50)))
        XCTAssertEqual(geometry.point(CGPoint(x: 500, y: 400)), CGPoint(x: 1500, y: 900))
        XCTAssertEqual(geometry.point(CGPoint(x: 1100, y: 850), clamp: true), CGPoint(x: 2999, y: 1799))
        XCTAssertEqual(geometry.point(CGPoint(x: -100, y: 0), clamp: true), .zero)
    }
    func testGestureConfigurationSupportsDisableAndSwappingFingerCounts() {
        func points(_ count: Int, _ dx: Double) -> [TouchPoint] { (0..<count).map { TouchPoint(id: $0, x: 0.2 + dx, y: 0.3) } }
        var gesture = TrackpadGesture()
        XCTAssertNil(gesture.update(points(3, 0), threeFinger: .disabled))
        XCTAssertNil(gesture.update(points(3, 0.3), ended: true, threeFinger: .disabled))
        gesture.reset()
        XCTAssertNil(gesture.update(points(3, 0), threeFinger: .macDesktops))
        XCTAssertEqual(gesture.update(points(3, 0.3), ended: true, threeFinger: .macDesktops), .release)
        gesture.reset()
        XCTAssertNil(gesture.update(points(4, 0), fourFinger: .windowsDesktops))
        XCTAssertEqual(gesture.update(points(4, -0.3), ended: true, fourFinger: .windowsDesktops), .desktopLeft)
        gesture.reset()
        XCTAssertNil(gesture.update(points(3, 0), threeFinger: .taskView))
        XCTAssertEqual(gesture.update(points(3, 0.3), ended: true, threeFinger: .taskView), .taskView)
    }
    func testPhysicalScanCodesKeepModifierSidesAndExtendedKeys() {
        XCTAssertEqual(MacScanCode.code(0), 0x1e)
        XCTAssertEqual(MacScanCode.code(59), 0x1d)
        XCTAssertEqual(MacScanCode.code(62), 0x11d)
        XCTAssertEqual(MacScanCode.code(55), 0x15b)
        XCTAssertEqual(MacScanCode.code(54), 0x15c)
        XCTAssertEqual(MacScanCode.code(123), 0x14b)
        XCTAssertNil(MacScanCode.code(255))
    }
}

extension PCAndDisplayTests {
    func testCapsLockTogglesAlwaysSendCompletePairsInCapture() {
        var capture = CaptureMachine(); capture.verifyRelease()
        XCTAssertTrue(capture.arm(eligible: true, modifiersHeld: false))
        XCTAssertTrue(capture.activate(generation: capture.generation, eligible: true))
        for down in [true, false, true, false] {
            let result = capture.handle(KeyStroke(key: 57, down: down), generation: capture.generation, toggle: true)
            XCTAssertEqual(result.keys, [KeyStroke(key: 57, down: true), KeyStroke(key: 57, down: false)])
            XCTAssertTrue(result.consume); XCTAssertTrue(capture.pressed.isEmpty)
        }
    }
    func testConnectionErrorsGiveLoginAndNetworkSpecificRecovery() {
        XCTAssertTrue(ConnectionFailure.message(0x20015).contains("Windows rejected"))
        XCTAssertTrue(ConnectionFailure.message(0x20006).contains("VPN"))
        XCTAssertTrue(ConnectionFailure.message(0x20018).contains("locked"))
        XCTAssertTrue(ConnectionFailure.message(0).contains("ended"))
    }
}
