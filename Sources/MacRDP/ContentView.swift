import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var deleting: PCProfile?

    var body: some View {
        Group {
            if model.unlocked { workspace }
            else { LockView(model: model) }
        }
        .frame(minWidth: 860, minHeight: 620)
        .sheet(isPresented: $model.settings, onDismiss: { model.settingsDidClose() }) { AppSettings(model: model).permitsAppTermination() }
        .sheet(isPresented: $model.keyboardSetup) { KeyboardSetupView(model: model).permitsAppTermination() }
        .sheet(isPresented: $model.pinChange) { ChangePINView(model: model).permitsAppTermination() }
        .sheet(item: $model.editor) { pc in PCEditor(model: model, pc: pc, connecting: false) }
        .sheet(item: $model.credentialPrompt) { pc in PCEditor(model: model, pc: pc, connecting: true) }
        .confirmationDialog("Delete this saved PC?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete saved PC", role: .destructive) {
                if let pc = deleting { Task { await model.deletePC(pc) } }
                deleting = nil
            }
        } message: { Text("Its saved password will be removed from Keychain.") }
    }

    private var workspace: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
                    Section("Saved PCs") {
                        ForEach(model.pcs) { pc in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pc.name).fontWeight(.medium)
                                    Text(pc.host).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "pc") }
                            .tag(pc.id)
                            .contextMenu {
                                Button("Connect") { model.connect(pc) }.disabled(model.sessionRunning)
                                Button("Edit…") { model.editPC(pc) }
                                Button("Delete…", role: .destructive) { deleting = pc }
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                if let active = model.activePC, model.sessionRunning {
                    Button {
                        model.select(active.id); model.showSession = true
                    } label: {
                        Label("\(active.name) · \(model.phase.rawValue)", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(16)
                }
                HStack {
                    Button { model.addPC() } label: { Label("Add PC", systemImage: "plus") }
                    Spacer()
                    Button { model.openSettings() } label: { Image(systemName: "gearshape") }.help("Settings")
                }.padding(14)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 330)
        } detail: {
            if model.pcs.contains(where: { $0.id == model.selection }) { pcDetail(model.profile) }
            else {
                ContentUnavailableView {
                    Label("Your Windows PCs", systemImage: "desktopcomputer")
                } description: {
                    Text("Add a PC, save its login, and connect to your Windows desktop.")
                } actions: {
                    Button("Add PC") { model.addPC() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func pcDetail(_ pc: PCProfile) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "pc").font(.system(size: 64, weight: .light)).foregroundStyle(.tint)
            VStack(spacing: 7) {
                Text(pc.name).font(.largeTitle.weight(.semibold))
                Text("\(pc.host):\(pc.port)").font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 22) {
                Label(pc.username.isEmpty ? "Ask for login" : pc.username, systemImage: "person")
                Label(pc.optimizeRetina ? "Optimize for Retina" : "Performance resolution", systemImage: "display")
            }.font(.subheadline).foregroundStyle(.secondary)
            HStack {
                if model.activePC?.id == pc.id && model.sessionRunning {
                    Button("Open session") { model.showSession = true }.buttonStyle(.borderedProminent)
                } else {
                    Button("Connect") { model.connect(pc) }.buttonStyle(.borderedProminent).disabled(model.sessionRunning)
                }
                Button("Edit PC…") { model.editPC(pc) }
                Button("Delete…", role: .destructive) { deleting = pc }.disabled(model.activePC?.id == pc.id && model.sessionRunning)
            }.controlSize(.large)
            if model.sessionRunning && model.activePC?.id != pc.id {
                Text("One session at a time. Your current session stays connected while you browse PCs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
            Spacer()
            Text("Passwords stay in macOS Keychain. Switching Mac desktops keeps your session open.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SessionWindowView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.unlocked { SessionPane(model: model) }
            else { ContentUnavailableView("MacRDP is locked", systemImage: "lock", description: Text("Unlock from the menu bar to return to Windows.")) }
        }
        .sheet(item: $model.certificateRequest) { CertificateView(model: model, request: $0).permitsAppTermination() }
        .frame(minWidth: 640, minHeight: 400)
    }
}

struct SessionPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack(alignment: .top) {
            SessionSurface(model: model)
            if model.isConnecting {
                VStack(spacing: 14) { ProgressView(); Text(model.phase.rawValue) }
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.phase == .failed || model.phase == .disconnected {
                ContentUnavailableView {
                    Label(model.phase.rawValue, systemImage: "network.slash")
                } description: { Text(model.connectionError ?? "Ready to reconnect.") }
                actions: {
                    if let pc = model.activePC {
                        Button("Reconnect") { model.connect(pc) }.buttonStyle(.borderedProminent)
                        Button("Enter login…") { model.connect(pc, askCredentials: true) }
                    }
                }.background(.background)
            }
            if model.sessionControlsOpen {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.setSessionControlsOpen(false) }
                    .accessibilityLabel("Close session controls")
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    desktopButton(.desktopLeft, symbol: "chevron.left", title: "Previous Windows desktop")
                    Button {
                        model.setSessionControlsOpen(!model.sessionControlsOpen)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.inputMode == .mac ? "apple.logo" : "square.grid.2x2.fill")
                                .font(.title3)
                            Circle().fill(model.keyboardControlState == .active ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Image(systemName: model.sessionControlsOpen ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(SessionToolbarButtonStyle(selected: model.sessionControlsOpen))
                    .accessibilityLabel("Session controls: " + model.keyboardControlState.title)
                    .help(model.keyboardControlState.title)
                    .accessibilityValue(model.sessionControlsOpen ? "Expanded" : "Collapsed")
                    desktopButton(.desktopRight, symbol: "chevron.right", title: "Next Windows desktop")
                    if !model.buttonVerified || model.rehearsing || (model.capture && !model.captureValidated) {
                        Button("Release to Mac") { model.releaseButton() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if model.sessionControlsOpen {
                    SessionControls(model: model)
                } else if model.capture && !model.captureValidated {
                    Text(model.keyboardControlDetail)
                        .font(.callout.weight(.medium)).multilineTextAlignment(.center)
                        .padding(12).frame(maxWidth: 400)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(12)
        }
        .onDisappear { model.setSessionControlsOpen(false) }
    }

    private func desktopButton(_ action: WindowsAction, symbol: String, title: String) -> some View {
        Button { model.switchWindowsDesktop(action) } label: {
            Image(systemName: symbol).font(.headline).frame(width: 44, height: 40)
        }
        .buttonStyle(SessionToolbarButtonStyle())
        .disabled(model.phase != .connected)
        .accessibilityLabel(title)
        .help(title + " (Ctrl+Windows+Arrow)")
    }
}

struct SessionToolbarButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 40)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.45 : selected ? 0.18 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.35 : 0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SessionControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.activePC?.name ?? "Windows", systemImage: "desktopcomputer")
                .font(.headline).lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard & mouse").font(.subheadline.weight(.medium))
                Picker("Keyboard and mouse control", selection: Binding(get: { model.inputMode }, set: {
                    if $0 == .mac { model.releaseButton() }
                    model.setSessionControlsOpen(false)
                    if $0 == .windows { model.useWindowsInput() }
                })) {
                    Text("Mac").tag(InputMode.mac)
                    Text("Windows").tag(InputMode.windows)
                }
                .pickerStyle(.segmented).labelsHidden().disabled(model.phase != .connected)
                Text(model.shortcut.displayName + " to switch control")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label(model.activeResolution, systemImage: "display")
                Spacer(minLength: 8)
                Text("\(model.presentedFPS) FPS").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            Text(model.keyboardControlDetail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Keyboard setup…") { model.openKeyboardSetup() }
                Spacer()
                Menu("Desktops") {
                    Button("← Previous desktop") { model.switchWindowsDesktop(.desktopLeft) }
                    Button("Next desktop →") { model.switchWindowsDesktop(.desktopRight) }
                }.disabled(model.phase != .connected)
            }
            HStack {
                Button {
                    model.setSessionControlsOpen(false)
                    model.window?.toggleFullScreen(nil)
                } label: {
                    Label(model.isFullScreen ? "Exit full screen" : "Full screen",
                          systemImage: model.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                Spacer()
                Button {
                    model.openSettings()
                    model.setSessionControlsOpen(false)
                } label: { Label("Settings", systemImage: "gearshape") }
            }
            Button(model.isConnecting ? "Cancel connection" : "Disconnect", role: .destructive) {
                model.disconnect()
                model.setSessionControlsOpen(false)
            }.frame(maxWidth: .infinity).disabled(!model.sessionRunning)
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

struct PCEditor: View {
    @ObservedObject var model: AppModel
    @State private var draft: PCProfile
    @State private var password = ""
    @State private var saving = false
    @State private var advanced = false
    let connecting: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, pc: PCProfile, connecting: Bool) {
        self.model = model; _draft = State(initialValue: pc); self.connecting = connecting
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label(connecting ? "Connect to Windows" : "PC details", systemImage: "pc").font(.title3.weight(.semibold)); Spacer() }.padding(24)
            Form {
                Section("Connection") {
                    TextField("Name", text: $draft.name)
                    TextField("Address", text: $draft.host, prompt: Text("Hostname or IP address"))
                }
                Section("Windows login") {
                    TextField("Username", text: $draft.username)
                    SecureField(connecting ? "Windows password" : "New password (optional)", text: $password)
                    Toggle("Remember password in Keychain", isOn: $draft.rememberPassword)
                    Text(connecting ? "Use your account password, not your Windows Hello PIN." : "Leave blank to keep the saved password for this address and account. Changing either removes the old saved password.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Advanced settings", isExpanded: $advanced) {
                    TextField("Port", text: $draft.port)
                    TextField("Domain (optional)", text: $draft.domain)
                    Toggle("Optimize for Retina", isOn: $draft.optimizeRetina)
                    Picker("Windows UI scale", selection: $draft.desktopScale) {
                        Text("Automatic").tag(0)
                        ForEach([100, 125, 150, 175, 200, 250, 300], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    Toggle("Open in full screen", isOn: $draft.openFullScreen)
                    Text("Retina uses the view’s backing pixels. Resolution updates automatically when the server supports display control. Changes to this PC apply to the next connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.formStyle(.grouped)
            HStack {
                if !connecting { Button("Forget trusted certificate") { model.forgetCertificate(draft) }.font(.caption) }
                Spacer()
                Button("Cancel") { password = ""; dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Saving…" : connecting ? "Connect" : "Save PC") {
                    saving = true
                    let submitted = password; password = ""
                    Task {
                        if connecting { _ = await model.submitCredentials(draft, password: submitted) }
                        else { _ = await model.savePC(draft, password: submitted) }
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving)
            }.padding(20)
        }.frame(width: 560, height: 700).background(Color(nsColor: .windowBackgroundColor)).interactiveDismissDisabled(saving)
    }
}

enum SettingsSection: String, CaseIterable {
    case accessibility = "Accessibility"
    case keyboard = "Keyboard"
    case security = "Security"
    case updates = "Updates"
}

struct AppSettings: View {
    @ObservedObject var model: AppModel
    @State private var shortcut: KeyboardShortcut
    @State private var three: GestureMapping
    @State private var four: GestureMapping
    @State private var mapping: ModifierMapping
    @State private var exclusive: Bool
    @State private var shortcutError: String?
    @State private var confirmRestart = false
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel) {
        self.model = model
        _shortcut = State(initialValue: model.shortcut); _three = State(initialValue: model.threeFinger)
        _four = State(initialValue: model.fourFinger); _mapping = State(initialValue: model.modifierMapping); _exclusive = State(initialValue: model.captureSystemShortcuts)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Settings", systemImage: "gearshape").font(.title3.weight(.semibold)); Spacer(); Text("MacRDP " + model.updater.version).font(.caption).foregroundStyle(.secondary) }.padding(24)
            Picker("Settings section", selection: $model.settingsSection) {
                ForEach(SettingsSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24)
            Group {
                if model.settingsSection == .accessibility {
                VStack(alignment: .leading, spacing: 16) {
                GroupBox("Accessibility") {
                    Label(model.accessibilityGranted ? "Accessibility allowed" : "Accessibility required",
                          systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.accessibilityGranted ? Color.green : Color.orange)
                    HStack {
                        Button("Open Accessibility") { model.openKeyboardPermissionSettings() }
                        Button("Check permission") { model.refreshKeyboardPermission() }
                    }
                    Text(model.keyboardControlDetail).font(.caption).foregroundStyle(.secondary)
                    Button("Test keyboard control…") { openKeyboardTest() }
                    Button(model.restarting ? "Restarting…" : "Restart MacRDP") {
                        if model.sessionRunning { confirmRestart = true }
                        else { Task { await model.restartApp() } }
                    }.disabled(model.restarting)
                    Text("After enabling permission, check again. Restart if macOS still denies access.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = model.permissionMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                    Spacer(minLength: 0)
                }.padding(20)
                } else if model.settingsSection == .keyboard {
                Form {
                Section("Keyboard") {
                    HStack { Text("Mac ↔ Windows input"); Spacer(); ShortcutRecorder(shortcut: $shortcut, error: $shortcutError).frame(width: 180) }
                    Text("Click to record a shortcut. Toggling input keeps the connection and full screen intact.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore default \(KeyboardShortcut.default.displayName)") { shortcut = .default; shortcutError = nil }.buttonStyle(.link)
                    Toggle("Capture Mac system shortcuts", isOn: $exclusive)
                    Text("Accessibility and a one-time release check are required. Your release shortcut always uses the physical Mac keys.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let shortcutError { Text(shortcutError).foregroundStyle(.red).font(.caption) }
                }
                Section("Mac keys → Windows keys") {
                    Picker("Command ⌘", selection: $mapping.command) { modifierChoices }
                    Picker("Control ⌃", selection: $mapping.control) { modifierChoices }
                    Picker("Option ⌥", selection: $mapping.option) { modifierChoices }
                    Picker("Shift ⇧", selection: $mapping.shift) { modifierChoices }
                    HStack {
                        Button("Command copies & pastes") { mapping = .macCopyPaste }
                        Button("Standard Windows mapping") { mapping = .standard }
                    }
                    Text(mapping.copyPasteHint).font(.caption).foregroundStyle(.secondary)
                }
                Section("Trackpad gestures") {
                    Picker("Three fingers", selection: $three) { ForEach(GestureMapping.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Four fingers", selection: $four) { ForEach(GestureMapping.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Text(model.gestureFeedback).font(.caption).foregroundStyle(.secondary)
                    Button("Open macOS Trackpad settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.trackpad")!)
                    }
                    Text("Three-finger desktop swipes send Ctrl+Windows+Left/Right, independent of key mappings. Create a second Windows desktop first. If macOS takes the gesture, set its desktop swipe to four fingers in Trackpad settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
                }.formStyle(.grouped)
                } else if model.settingsSection == .updates {
                    VStack { UpdatesView(updater: model.updater); Spacer(minLength: 0) }
                } else {
                    Form {
                Section("App security") {
                    Button("Change app PIN…") { model.settings = false; model.error = nil; model.pinChange = true }
                    Text("MacRDP starts locked. After unlock, it stays open until you press Lock or quit. Locking the app keeps an established session connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                    }.formStyle(.grouped)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save settings") { model.saveSettings(shortcut: shortcut, three: three, four: four, exclusive: exclusive, mapping: mapping) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 620, height: 600).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshKeyboardPermission() }
        .confirmationDialog("Restart MacRDP?", isPresented: $confirmRestart) {
            Button("Disconnect and restart") { Task { await model.restartApp() } }
        } message: {
            Text("This disconnects Windows and locks MacRDP. Save settings before restarting to keep your changes.")
        }
    }
    private func openKeyboardTest() {
        model.saveSettings(shortcut: shortcut, three: three, four: four, exclusive: exclusive, mapping: mapping, dismiss: false)
        if model.error == nil { model.openKeyboardSetup() }
    }
    private var modifierChoices: some View {
        ForEach(WindowsModifier.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
}

struct CertificateView: View {
    @ObservedObject var model: AppModel
    let request: CertificateRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(request.changed ? "Windows certificate changed" : "Verify your Windows PC", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text(request.changed ? "The PC’s certificate differs from the fingerprint you trusted. Check with the PC owner before replacing it." : "macOS could not verify this PC’s certificate automatically. Verify the SHA-256 fingerprint with the PC owner before trusting it.")
            LabeledContent("Host", value: request.host)
            LabeledContent("Subject", value: request.subject)
            LabeledContent("Issuer", value: request.issuer)
            Text(request.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text("Trust applies only to this PC address and port. It does not change macOS or VPN trust.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { model.decideCertificate(accept: false, remember: false) }
                Spacer()
                Button("Trust once") { model.decideCertificate(accept: true, remember: false) }
                Button(request.changed ? "Replace trusted fingerprint" : "Trust this PC") { model.decideCertificate(accept: true, remember: true) }
            }
        }.padding(28).frame(width: 610).interactiveDismissDisabled()
    }
}
