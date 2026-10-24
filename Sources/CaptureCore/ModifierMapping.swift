import Foundation

public enum WindowsModifier: String, CaseIterable, Codable, Sendable {
    case control = "Ctrl", windows = "Windows", alt = "Alt", shift = "Shift", disabled = "Disabled"

    func key(right: Bool) -> UInt16? {
        switch self {
        case .control: right ? 62 : 59
        case .windows: right ? 54 : 55
        case .alt: right ? 61 : 58
        case .shift: right ? 60 : 56
        case .disabled: nil
        }
    }
}

public struct ModifierMapping: Codable, Equatable, Sendable {
    public var command: WindowsModifier = .windows
    public var control: WindowsModifier = .control
    public var option: WindowsModifier = .alt
    public var shift: WindowsModifier = .shift
    public init() {}
    public static let standard = ModifierMapping()
    public static var macCopyPaste: ModifierMapping {
        var mapping = ModifierMapping()
        mapping.command = .control; mapping.control = .windows
        return mapping
    }
    public var summary: String {
        "Command → \(command.rawValue) · Control → \(control.rawValue) · Option → \(option.rawValue) · Shift → \(shift.rawValue)"
    }
    public var copyPasteHint: String {
        if command == .control { return "Use Command+C/V to copy and paste in Windows." }
        if control == .control { return "Use Control+C/V to copy and paste in Windows." }
        if option == .control { return "Use Option+C/V to copy and paste in Windows." }
        if shift == .control { return "Use Shift+C/V to copy and paste in Windows." }
        return "Map a key to Ctrl to use Windows copy/paste shortcuts."
    }
    func target(for key: UInt16) -> UInt16? {
        switch key {
        case 54, 55: command.key(right: key == 54)
        case 59, 62: control.key(right: key == 62)
        case 58, 61: option.key(right: key == 61)
        case 56, 60: shift.key(right: key == 60)
        default: key
        }
    }
}

public struct ModifierTranslator: Sendable {
    public var mapping: ModifierMapping
    private var held: [UInt16: UInt16] = [:]
    public init(mapping: ModifierMapping = .standard) { self.mapping = mapping }
    public mutating func reset() { held.removeAll(keepingCapacity: true) }
    public mutating func translate(_ key: KeyStroke) -> KeyStroke? {
        guard [54, 55, 56, 58, 59, 60, 61, 62].contains(key.key) else { return key }
        if key.down {
            guard held[key.key] == nil, let target = mapping.target(for: key.key) else { return nil }
            let alreadyHeld = held.values.contains(target)
            held[key.key] = target
            return alreadyHeld ? nil : KeyStroke(key: target, down: true)
        }
        guard let target = held.removeValue(forKey: key.key), !held.values.contains(target) else { return nil }
        return KeyStroke(key: target, down: false)
    }
}
