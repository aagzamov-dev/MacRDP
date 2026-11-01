import SwiftUI

struct LockView: View {
    @ObservedObject var model: AppModel
    @State private var pin = ""
    @State private var confirmation = ""
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 54, weight: .light)).foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text(model.needsPIN ? "Make MacRDP yours" : "Welcome back").font(.largeTitle.weight(.semibold))
                Text(model.needsPIN ? "Create a 4–12 digit PIN to protect your saved PCs." : "Enter your app PIN to open your workspace.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                SecureField(model.needsPIN ? "New PIN" : "App PIN", text: $pin)
                    .focused($pinFocused).onSubmit(submit)
                    .accessibilityIdentifier("appPIN")
                if model.needsPIN { SecureField("Confirm PIN", text: $confirmation).onSubmit(submit) }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                Button(action: submit) {
                    HStack {
                        if model.loading { ProgressView().controlSize(.small) }
                        Text(model.needsPIN ? "Create PIN & open" : "Unlock MacRDP")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.loading || pin.isEmpty || (model.needsPIN && confirmation.isEmpty))
                Divider()
                Button("Unlock with Touch ID or Mac password") {
                    pin = ""; confirmation = ""
                    Task { await model.unlockWithMac() }
                }.disabled(model.loading)
                Button("Forgot PIN? Reset with Mac account") {
                    pin = ""; confirmation = ""; model.error = nil; model.pinReset = true
                }.buttonStyle(.link).disabled(model.loading)
            }.textFieldStyle(.roundedBorder).frame(width: 350)
            Text("Starts locked every launch. Stays open until you press Lock.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Saved passwords stay in macOS Keychain. Your Mac account can reset this app’s PIN.")
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .onAppear { pinFocused = true }
    }

    private func submit() {
        guard !model.loading else { return }
        model.unlock(pin: pin, confirmation: confirmation)
        pin = ""
        confirmation = ""
    }
}

struct ChangePINView: View {
    @ObservedObject var model: AppModel
    @State private var current = ""
    @State private var replacement = ""
    @State private var confirmation = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Change app PIN", systemImage: "lock.rotation").font(.title3.weight(.semibold))
            SecureField("Current PIN", text: $current)
            SecureField("New PIN · 4–12 digits", text: $replacement)
            SecureField("Confirm new PIN", text: $confirmation)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Change PIN") {
                    saving = true
                    let old = current, new = replacement, repeated = confirmation
                    current = ""; replacement = ""; confirmation = ""
                    Task {
                        _ = await model.changePIN(current: old, replacement: new, confirmation: repeated)
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).disabled(saving || current.isEmpty || replacement.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 400)
            .interactiveDismissDisabled(saving)
    }
}

struct ResetPINView: View {
    @ObservedObject var model: AppModel
    @State private var replacement = ""
    @State private var confirmation = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Reset app PIN", systemImage: "lock.rotation").font(.title3.weight(.semibold))
            Text("Verify with Touch ID or your Mac login password. Your saved PCs and passwords will be kept.")
                .foregroundStyle(.secondary)
            SecureField("New PIN · 4–12 digits", text: $replacement)
            SecureField("Confirm new PIN", text: $confirmation)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { model.error = nil; dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(model.loading)
                Button("Authenticate & reset PIN") {
                    let new = replacement, repeated = confirmation
                    replacement = ""; confirmation = ""
                    Task { await model.resetPINWithMac(replacement: new, confirmation: repeated) }
                }.buttonStyle(.borderedProminent)
                    .disabled(model.loading || replacement.isEmpty || confirmation.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 430)
            .interactiveDismissDisabled(model.loading)
    }
}
