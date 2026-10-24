import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    @Binding var error: String?

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        configure(button)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) { configure(button) }

    private func configure(_ button: ShortcutRecorderButton) {
        button.shortcut = shortcut
        button.onChange = { shortcut = $0; error = nil }
        button.onError = { error = $0 }
        if !button.recording { button.title = shortcut.displayName }
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.stopRecording() }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut = KeyboardShortcut.default
    var onChange: ((KeyboardShortcut) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var recording = false
    private var monitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        toolTip = "Click, then press the shortcut you want. Escape cancels."
        setAccessibilityLabel("Keyboard toggle shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        stopRecording()
        recording = true
        title = "Type new shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.firstResponder === self,
                  self.window?.isKeyWindow == true, event.window === self.window, NSApp.isActive else { return event }
            if event.keyCode == 53 && event.modifierFlags.contains([.command, .option]) {
                self.stopRecording()
                return event
            }
            self.record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = UInt64(event.modifierFlags.rawValue) & KeyboardShortcut.modifierMask
        if event.keyCode == 53 && modifiers == 0 { stopRecording(); return }
        let names: [UInt16: String] = [36: "↩", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌅",
            115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let text = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let label = names[event.keyCode] ?? (text.count == 1 ? text : "Key \(event.keyCode)")
        let proposed = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers, keyName: label)
        if let error = proposed.validationError { onError?(error); return }
        shortcut = proposed
        onChange?(proposed)
        stopRecording()
    }

    func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        title = shortcut.displayName
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}
