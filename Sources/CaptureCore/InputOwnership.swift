public enum InputMode: String, Sendable, CaseIterable {
    case mac = "Mac", windows = "Windows"
}

public struct InputOwnership: Sendable {
    public private(set) var mode: InputMode = .windows
    public private(set) var blocked = false
    private var awaitingReturn = false
    private var departed = false

    public init() {}
    public mutating func select(_ mode: InputMode) {
        self.mode = mode
        blocked = false
        awaitingReturn = false
        departed = false
    }
    public mutating func swipeToMac() {
        awaitingReturn = true
        departed = false
    }
    public mutating func fail() { blocked = true }
    public mutating func shouldResume(eligible: Bool) -> Bool {
        guard eligible else {
            if awaitingReturn { departed = true }
            return false
        }
        if awaitingReturn {
            guard departed else { return false }
            awaitingReturn = false
        }
        return mode == .windows && !blocked
    }
}

public enum RemoteKeyboardPolicy {
    public static func keepsShortcutLocal(mode: InputMode, key: UInt16, command: Bool, control: Bool) -> Bool {
        mode == .mac && (command || (control && (123...126).contains(key)))
    }
    public static func pastesMacText(mode: InputMode, key: UInt16, command: Bool,
                                    control: Bool, option: Bool, shift: Bool) -> Bool {
        mode == .mac && key == 9 && command && !control && !option && !shift
    }
}
