import Foundation
import CoreGraphics

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var keyName: String

    public init(keyCode: UInt16, modifiers: UInt64, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    public static let modifierMask = CGEventFlags([.maskControl, .maskAlternate, .maskCommand, .maskShift]).rawValue
    public static let `default` = KeyboardShortcut(keyCode: 5,
        modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue, keyName: "G")

    public var validationError: String? {
        let flags = CGEventFlags(rawValue: modifiers)
        guard modifiers & ~Self.modifierMask == 0,
              !flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty,
              keyCode < 127, !(54...63).contains(keyCode) else {
            return "Choose a key with Control, Option or Command."
        }
        if keyCode == 53 && flags.contains([.maskCommand, .maskAlternate]) {
            return "Command Option Escape is reserved for Force Quit."
        }
        if keyCode == 48 { return "Keep Tab combinations available for Windows. Choose another key." }
        return nil
    }

    public func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && flags.rawValue & Self.modifierMask == modifiers
    }

    public var displayName: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return (flags.contains(.maskControl) ? "⌃" : "")
            + (flags.contains(.maskAlternate) ? "⌥" : "")
            + (flags.contains(.maskShift) ? "⇧" : "")
            + (flags.contains(.maskCommand) ? "⌘" : "") + keyName
    }
}

public struct KeyboardToggle: Sendable {
    public private(set) var pending = false
    public init() {}
    public mutating func request() { pending = true }
    public mutating func cancel() { pending = false }

    public mutating func takeIfReleased(keyHeld: Bool, modifiersHeld: Bool, eligible: Bool) -> Bool {
        guard eligible else { cancel(); return false }
        guard pending, !keyHeld, !modifiersHeld else { return false }
        pending = false
        return true
    }
}
