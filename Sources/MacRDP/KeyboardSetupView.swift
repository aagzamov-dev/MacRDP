import SwiftUI
import AppKit

struct KeyboardSetupView: View {
    @ObservedObject var model: AppModel
    @State private var confirmRestart = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Keyboard setup", systemImage: "keyboard")
                .font(.title2.weight(.semibold))
            Text("Send Mac keyboard shortcuts to Windows, with an easy way back.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        step("1. Allow Accessibility", done: model.accessibilityGranted)
                        Text(model.accessibilityGranted ? "Permission granted for this running copy of MacRDP." : "Enable MacRDP in the Accessibility list, then return here. Permission is checked automatically.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Open Accessibility") { model.openKeyboardPermissionSettings() }
                            Button("Check again") { model.refreshKeyboardPermission() }
                        }
                        HStack {
                            Text("Already enabled, but still not working?").font(.caption).foregroundStyle(.secondary)
                            Button(model.restarting ? "Restarting…" : "Restart MacRDP") {
                                if model.sessionRunning { confirmRestart = true }
                                else { Task { await model.restartApp() } }
                            }.disabled(model.restarting)
                        }
                        if let message = model.permissionMessage {
                            Text(message).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        step("2. Check your way back to Mac", done: model.releaseVerified)
                        Label(model.shortcutVerified ? "\(model.shortcut.displayName) verified" : "Press \(model.shortcut.displayName) now",
                              systemImage: model.shortcutVerified ? "checkmark.circle.fill" : "keyboard")
                        HStack {
                            Button("Release to Mac") { model.releaseButton() }
                            Text(model.buttonVerified ? "Release button verified" : "Click to verify the release button")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("This step stays on your Mac. No keys are sent to Windows.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        step("3. Test Windows control", done: model.captureValidated)
                        Text(model.captureValidated ? "Setup saved. Windows control can start automatically when you return to your session." : "The test opens your Windows desktop. Press \(model.shortcut.displayName) within 10 seconds to confirm you can return to Mac. Otherwise control releases automatically.")
                            .font(.callout).foregroundStyle(.secondary)
                        if model.phase != .connected {
                            Text("Connect to a PC first, then return to Keyboard setup.").font(.caption)
                        }
                        if let issue = model.captureIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                        Button(model.captureValidated ? "Use Windows control" : "Start 10-second test") { model.testWindowsControl() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.accessibilityGranted || !model.releaseVerified || model.phase != .connected || model.restarting)
                    }
                    Divider()
                    Text(model.modifierMapping.summary + "\n" + model.modifierMapping.copyPasteHint)
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 560, height: 650)
        .background(KeyboardSetupWindowReader(model: model).frame(width: 0, height: 0))
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshKeyboardPermission() }
        .confirmationDialog("Restart MacRDP?", isPresented: $confirmRestart) {
            Button("Disconnect and restart") { Task { await model.restartApp() } }
        } message: {
            Text("This disconnects the remote session and locks MacRDP. It does not sign out of Windows.")
        }
    }

    private func step(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.headline).foregroundStyle(done ? Color.green : Color.primary)
    }
}

private struct KeyboardSetupWindowReader: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WindowView { WindowView(model: model) }
    func updateNSView(_ view: WindowView, context: Context) {}

    final class WindowView: NSView {
        weak var model: AppModel?
        init(model: AppModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            model?.keyboardSetupWindow = window
        }
    }
}
