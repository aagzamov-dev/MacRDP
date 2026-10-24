import AppKit
import ApplicationServices

@MainActor
struct KeyboardAccess {
    var isTrusted: () -> Bool
    var request: () -> Void
    var openSettings: () -> Bool

    static let live = KeyboardAccess(
        isTrusted: { AXIsProcessTrusted() },
        request: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) },
        openSettings: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    )
}

enum KeyboardControlState: Equatable {
    case disconnected, locked, mac, paused, permissionRequired, setupRequired, typingOnly, starting, testing, active
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "Not connected"
        case .locked: "MacRDP is locked"
        case .mac: "Mac control"
        case .paused: "Windows control paused"
        case .permissionRequired: "Accessibility permission needed"
        case .setupRequired: "Keyboard setup needed"
        case .typingOnly: "Windows typing only"
        case .starting: "Starting Windows control…"
        case .testing: "Testing Windows control"
        case .active: "Windows control active"
        case .failed: "Windows control stopped"
        }
    }

    var symbol: String {
        switch self {
        case .active: "checkmark.shield.fill"
        case .permissionRequired, .setupRequired, .failed: "exclamationmark.triangle.fill"
        case .paused: "pause.circle"
        default: "keyboard"
        }
    }
}
