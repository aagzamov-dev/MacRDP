import Foundation

public enum CaptureState: String, Sendable {
    case local, arming, captured, releasing
}

public struct KeyStroke: Equatable, Sendable {
    public let key: UInt16
    public let down: Bool
    public let repeating: Bool

    public init(key: UInt16, down: Bool, repeating: Bool = false) {
        self.key = key
        self.down = down
        self.repeating = repeating
    }
}

public struct InputResult: Sendable {
    public var consume = false
    public var released = false
    public var keys: [KeyStroke] = []
}

public struct CaptureMachine: Sendable {
    public private(set) var state: CaptureState = .local
    public private(set) var generation: UInt64 = 0
    public private(set) var pressed: Set<UInt16> = []
    public private(set) var buttons: Set<UInt8> = []
    public private(set) var releaseArmed = false

    public init() {}

    public mutating func verifyRelease() { releaseArmed = true }

    @discardableResult
    public mutating func arm(eligible: Bool, modifiersHeld: Bool) -> Bool {
        guard state == .local, releaseArmed, eligible, !modifiersHeld else { return false }
        state = .arming
        generation &+= 1
        return true
    }

    @discardableResult
    public mutating func activate(generation expected: UInt64, eligible: Bool) -> Bool {
        guard state == .arming, expected == generation, eligible else {
            if expected == generation { _ = release() }
            return false
        }
        state = .captured
        return true
    }

    public mutating func handle(_ key: KeyStroke, generation expected: UInt64,
                                escape: Bool = false, forceQuit: Bool = false, toggle: Bool = false) -> InputResult {
        guard state == .captured, generation == expected else { return InputResult() }
        if escape || forceQuit {
            let ups = release()
            return InputResult(consume: !forceQuit, released: true, keys: ups)
        }
        if toggle {
            return InputResult(consume: true, keys: [KeyStroke(key: key.key, down: true), KeyStroke(key: key.key, down: false)])
        }
        if key.down {
            if pressed.contains(key.key) && !key.repeating { return InputResult(consume: true) }
            pressed.insert(key.key)
        } else if pressed.remove(key.key) == nil {
            return InputResult(consume: true)
        }
        return InputResult(consume: true, keys: [key])
    }

    public mutating func holdButton(_ button: UInt8) {
        if state == .captured { buttons.insert(button) }
    }

    @discardableResult
    public mutating func release() -> [KeyStroke] {
        guard state != .local else { return [] }
        state = .releasing
        let ups = pressed.sorted().map { KeyStroke(key: $0, down: false) }
        pressed.removeAll(keepingCapacity: true)
        buttons.removeAll(keepingCapacity: true)
        generation &+= 1
        state = .local
        return ups
    }
}

public enum WindowsAction: String, Sendable {
    case taskView = "Windows Task View"
    case appSwitcher = "Windows app switcher"
    case nextTab = "Next Windows tab"
    case previousTab = "Previous Windows tab"
    case desktopLeft = "Previous Windows desktop"
    case desktopRight = "Next Windows desktop"

    public var keys: [KeyStroke] {
        let codes: [UInt16]
        switch self {
        case .taskView: codes = [55, 48]
        case .appSwitcher: codes = [58, 48]
        case .nextTab: codes = [59, 48]
        case .previousTab: codes = [59, 56, 48]
        case .desktopLeft: codes = [59, 55, 123]
        case .desktopRight: codes = [59, 55, 124]
        }
        return codes.map { KeyStroke(key: $0, down: true) }
            + codes.reversed().map { KeyStroke(key: $0, down: false) }
    }
}
