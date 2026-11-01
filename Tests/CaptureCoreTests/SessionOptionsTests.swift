import XCTest
@testable import CaptureCore

final class SessionOptionsTests: XCTestCase {
    func testExistingProfilesKeepTheirDisplayAndInputDefaults() throws {
        let bytes = Data(#"{"host":"test.invalid","optimizeRetina":true,"desktopScale":150}"#.utf8)
        let pc = try JSONDecoder().decode(PCProfile.self, from: bytes)
        XCTAssertEqual(pc.resolution, .dynamic)
        XCTAssertEqual(pc.viewMode, .fit)
        XCTAssertEqual(pc.textInputMode, .physical)
        XCTAssertNil(pc.modifierMapping)
        XCTAssertNil(pc.clipboardSharing)
        XCTAssertFalse(pc.audioPlayback)
        XCTAssertTrue(pc.allowMacPaste)
        XCTAssertFalse(pc.useVPN)
        XCTAssertNil(pc.vpnServiceID)
        XCTAssertEqual(pc.desktopScale, 150)
    }

    func testHostOptionsRoundTripWithoutAffectingAnotherProfile() throws {
        var pc = PCProfile(); pc.host = "test.invalid"
        pc.useVPN = true; pc.vpnServiceID = "fixture-vpn-service"
        pc.favorite = true; pc.lastConnected = Date(timeIntervalSince1970: 123456)
        pc.resolution = .qhd; pc.viewMode = .actual; pc.audioPlayback = true
        pc.clipboardSharing = false; pc.allowMacPaste = false; pc.reconnectAutomatically = false
        pc.modifierMapping = .macCopyPaste; pc.textInputMode = .text
        let stored = try JSONDecoder().decode(PCProfile.self, from: JSONEncoder().encode(pc))
        XCTAssertEqual(stored, pc)
        let other = PCProfile()
        XCTAssertNil(other.modifierMapping); XCTAssertNil(other.clipboardSharing)
        XCTAssertEqual(other.resolution, .dynamic)
    }

    func testFixedResolutionDoesNotDoubleRetinaPixelsOrAlterWindowsScale() {
        let layout = DisplayLayout(points: CGSize(width: 1200, height: 800), backing: CGSize(width: 2400, height: 1600),
                                   retina: true, scale: 150, fixed: .uhd)
        XCTAssertEqual(layout.width, 3840); XCTAssertEqual(layout.height, 2160)
        XCTAssertEqual(layout.desktopScale, 150); XCTAssertEqual(layout.deviceScale, 100)
    }

    func testActualPixelsPanClampsAndKeepsPointerAligned() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        var geometry = RemoteGeometry(bounds: bounds, remote: CGSize(width: 3840, height: 2160),
                                      mode: .actual, backingScale: 2)
        XCTAssertEqual(geometry.imageRect.size, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(geometry.point(CGPoint(x: 500, y: 300)), CGPoint(x: 1920, y: 1080))
        geometry.pan = CGPoint(x: 10000, y: 10000)
        XCTAssertEqual(geometry.imageRect.origin, .zero)
        XCTAssertEqual(geometry.point(.zero), .zero)
        XCTAssertNil(geometry.point(CGPoint(x: -1, y: 20)))
        geometry.pan = CGPoint(x: -10000, y: -10000)
        XCTAssertEqual(geometry.imageRect.maxX, bounds.maxX)
        XCTAssertEqual(geometry.imageRect.maxY, bounds.maxY)
        XCTAssertEqual(geometry.point(CGPoint(x: 1200, y: 800), clamp: true), CGPoint(x: 3839, y: 2159))
    }

    func testRetriesAreBoundedAndNeverRepeatAuthenticationOrCertificateFailures() {
        XCTAssertEqual((0..<5).compactMap { ConnectionFailure.retryDelay(code: 0x2000d, attempt: $0) }, [2, 4, 8, 16, 30])
        XCTAssertNil(ConnectionFailure.retryDelay(code: 0x2000d, attempt: 5))
        for code: UInt32 in [0, 0x20008, 0x20009, 0x20012, 0x20014, 0x2000b] {
            XCTAssertNil(ConnectionFailure.retryDelay(code: code, attempt: 0))
        }
    }

    func testWindowsActionsReleaseEveryKeyInReverseOrder() {
        for action in [WindowsAction.secureAttention, .taskManager] {
            let down = action.keys.filter(\.down)
            let up = action.keys.filter { !$0.down }
            XCTAssertEqual(down.map(\.key), up.reversed().map(\.key))
        }
        XCTAssertEqual(WindowsAction.secureAttention.keys.prefix(3).map(\.key), [59, 58, 117])
        XCTAssertEqual(WindowsAction.taskManager.keys.prefix(3).map(\.key), [59, 56, 53])
    }
    func testVPNRequiresExplicitSelectionOnlyWhenEnabled() {
        var pc = PCProfile(); pc.host = "test.invalid"
        XCTAssertNil(pc.validationError)
        pc.useVPN = true
        XCTAssertNotNil(pc.validationError)
        pc.vpnServiceID = "fixture-service"
        XCTAssertNil(pc.validationError)
        pc.useVPN = false; pc.vpnServiceID = nil
        XCTAssertNil(pc.validationError)
    }

}
