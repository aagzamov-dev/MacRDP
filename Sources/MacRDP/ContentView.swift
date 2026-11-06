import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var deleting: PCProfile?
    @State private var search = ""

    var body: some View {
        Group {
            if model.unlocked { workspace }
            else { LockView(model: model) }
        }
        .frame(minWidth: 860, minHeight: 620)
        .sheet(isPresented: $model.settings, onDismiss: { model.settingsDidClose() }) { AppSettings(model: model).permitsAppTermination() }
        .sheet(isPresented: $model.keyboardSetup) { KeyboardSetupView(model: model).permitsAppTermination() }
        .sheet(isPresented: $model.pinReset) { ResetPINView(model: model).permitsAppTermination() }
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
                    if !filteredPCs.filter(\.favorite).isEmpty {
                        Section("Favorites") { ForEach(filteredPCs.filter(\.favorite)) { pc in pcRow(pc) } }
                    }
                    if !filteredPCs.filter({ !$0.favorite && $0.lastConnected != nil }).isEmpty {
                        Section("Recent PCs") { ForEach(filteredPCs.filter { !$0.favorite && $0.lastConnected != nil }) { pc in pcRow(pc) } }
                    }
                    Section("Saved PCs") { ForEach(filteredPCs.filter { !$0.favorite && $0.lastConnected == nil }) { pc in pcRow(pc) } }
                }.listStyle(.sidebar).searchable(text: $search, prompt: "Find a PC")
                Divider()
                ForEach(model.sessions.filter { $0.sessionRunning }, id: \.activePC?.id) { session in
                    Button { session.showSession = true } label: {
                        Label("\(session.activePC?.name ?? "Windows") · \(session.phase.rawValue)", systemImage: "circle.fill")
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

    private var filteredPCs: [PCProfile] {
        model.pcs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
    }
    private func pcRow(_ pc: PCProfile) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(pc.name).fontWeight(.medium)
                Text(pc.host).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: pc.favorite ? "star.fill" : "pc") }
        .tag(pc.id)
        .contextMenu {
            Button("Connect") { model.connect(pc) }
            Button(pc.favorite ? "Remove favorite" : "Add favorite") { model.toggleFavorite(pc) }
            Button("Duplicate…") { model.duplicatePC(pc) }
            Button("Edit…") { model.editPC(pc) }
            Button("Delete…", role: .destructive) { deleting = pc }
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
                if model.session(for: pc.id)?.sessionRunning == true {
                    Button("Open session") { model.showSession(for: pc.id) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Connect") { model.connect(pc) }.buttonStyle(.borderedProminent)
                }
                Button("Edit PC…") { model.editPC(pc) }
                Button("Delete…", role: .destructive) { deleting = pc }.disabled(model.session(for: pc.id)?.sessionRunning == true)
            }.controlSize(.large)
            if let last = pc.lastConnected { Text("Last connected \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if let failure = model.session(for: pc.id)?.connectionError {
                Text(failure).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                Button("Enter login…") { model.connect(pc, askCredentials: true) }
            } else if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
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
        .sheet(isPresented: $model.keyboardSetup) { KeyboardSetupView(model: model).permitsAppTermination() }
        .sheet(item: $model.credentialPrompt) { pc in PCEditor(model: model, pc: pc, connecting: true) }
        .sheet(item: $model.certificateRequest) { CertificateView(model: model, request: $0).permitsAppTermination() }
        .frame(minWidth: 640, minHeight: 400)
    }
}

struct SessionPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: model.effectiveSessionControlsPosition.alignment) {
            SessionSurface(model: model)
                .zIndex(0)
            if model.isConnecting {
                VStack(spacing: 14) { ProgressView(); Text(model.vpnStatus ?? model.phase.rawValue)
                    if model.vpnStatus != nil { Button("Cancel") { model.disconnect() } }
                }
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.phase == .failed || model.phase == .disconnected || model.phase == .reconnecting {
                ContentUnavailableView {
                    Label(model.phase.rawValue, systemImage: "network.slash")
                } description: {
                    Text(model.connectionError ?? "Ready to reconnect.")
                    if let message = model.reconnectMessage { Text(message) }
                }
                actions: {
                    if let pc = model.activePC {
                        if model.phase == .reconnecting {
                            ProgressView()
                            Button("Cancel retry") { model.cancelReconnect() }
                        }
                        Button("Reconnect now") { model.cancelReconnect(); model.connect(pc) }.buttonStyle(.borderedProminent)
                        Button("Enter login…") { model.cancelReconnect(); model.connect(pc, askCredentials: true) }
                    }
                }.background(.background)
            }
            if model.sessionControlsOpen {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.setSessionControlsOpen(false) }
                    .accessibilityLabel("Close session controls")
            }
            VStack(alignment: model.effectiveSessionControlsPosition.horizontalAlignment, spacing: 8) {
                if model.effectiveSessionControlsPosition.isBottom { controlsPanel(availableHeight: geometry.size.height) }
                controlsButtons
                if !model.effectiveSessionControlsPosition.isBottom { controlsPanel(availableHeight: geometry.size.height) }
            }
            .padding(12)
            .compositingGroup()
            .zIndex(1)
        }
        }
        .onDisappear { model.setSessionControlsOpen(false) }
    }

    private var controlsButtons: some View {
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
                    Image(systemName: (model.sessionControlsOpen != model.effectiveSessionControlsPosition.isBottom) ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(SessionToolbarButtonStyle(selected: model.sessionControlsOpen))
            .accessibilityLabel("Session controls: " + model.keyboardControlState.title)
            .help(model.keyboardControlState.title)
            .accessibilityValue(model.sessionControlsOpen ? "Expanded" : "Collapsed")
            desktopButton(.desktopRight, symbol: "chevron.right", title: "Next Windows desktop")
            if !model.buttonVerified || model.rehearsing || (model.capture && !model.captureValidated) {
                Button { model.releaseButton() } label: {
                    Image(systemName: "escape").font(.headline).frame(width: 44, height: 40)
                }
                .buttonStyle(SessionToolbarButtonStyle())
                .accessibilityLabel("Release to Mac")
                .help("Release to Mac — return keyboard control to your Mac without disconnecting")
            }
        }
    }

    @ViewBuilder
    private func controlsPanel(availableHeight: CGFloat) -> some View {
        if model.sessionControlsOpen {
            SessionControls(model: model, availableHeight: availableHeight)
        } else if model.capture && !model.captureValidated {
            Text(model.keyboardControlDetail)
                .font(.callout.weight(.medium)).multilineTextAlignment(.center)
                .padding(12).frame(maxWidth: 400)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
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
    var availableHeight: CGFloat = 720
    @State private var detailsExpanded = false

    var body: some View {
        ScrollView {
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
            Picker("Controls position", selection: Binding(get: { model.activePC?.sessionControlsPosition }, set: { model.setSessionControlsPosition($0) })) {
                Text("Use app setting").tag(SessionControlsPosition?.none)
                ForEach(SessionControlsPosition.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            DisclosureGroup("Display & performance", isExpanded: $detailsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Resolution", selection: Binding(get: { model.activePC?.resolution ?? .dynamic }, set: { model.setDisplay(resolution: $0) })) {
                        ForEach(DesktopResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("View", selection: Binding(get: { model.activePC?.viewMode ?? .fit }, set: { model.setDisplay(mode: $0) })) {
                        ForEach(DesktopViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }

                    if !model.dynamicResize { Text("Live resize unavailable. Resolution changes need reconnect.").font(.caption).foregroundStyle(.orange) }
                    Text(model.performanceDetail).font(.caption.monospaced()).textSelection(.enabled)
                    Text("GPU completion includes queue time; it is not network or input latency.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
            if let notice = model.sessionNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            Text(model.keyboardControlDetail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Keyboard setup…") { model.openKeyboardSetup() }
                Spacer()
                Menu("Windows actions") {
                    Button("Ctrl+Alt+Delete") { model.switchWindowsDesktop(.secureAttention) }
                    Button("Task Manager") { model.switchWindowsDesktop(.taskManager) }
                    Button("Paste Mac text into Windows") { model.pasteMacText() }.disabled(model.activePC?.allowMacPaste == false)
                    Divider()
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
            Button(model.isConnecting || model.phase == .reconnecting ? "Cancel connection" : "Disconnect", role: .destructive) {
                model.disconnect()
                model.setSessionControlsOpen(false)
            }.frame(maxWidth: .infinity).disabled(!model.sessionRunning)
        }
        .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 360, height: max(160, min(availableHeight - 76, detailsExpanded ? 650 : 440)))
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
    @State private var vpnProfiles: [VPNProfile] = []
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
                Section("VPN") {
                    Toggle("Wait for VPN before connecting", isOn: $draft.useVPN)
                    if draft.useVPN {
                        Picker("VPN connection", selection: $draft.vpnServiceID) {
                            Text("Select a VPN").tag(Optional<String>.none)
                            ForEach(vpnProfiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                            if let selected = draft.vpnServiceID, !vpnProfiles.contains(where: { $0.id == selected }) {
                                Text("Selected VPN unavailable").tag(Optional(selected))
                            }
                        }
                        Button("Refresh VPN connections") { vpnProfiles = SystemVPNConnection.profiles() }
                        Text("Connect this VPN yourself. MacRDP waits until it is connected before opening Windows and never connects or disconnects your VPN.")
                            .font(.caption).foregroundStyle(.secondary)
                        if vpnProfiles.isEmpty { Text("No supported VPN profiles found. Configure one in your VPN client or macOS settings first.").font(.caption).foregroundStyle(.orange) }
                    }
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
                    Picker("Resolution", selection: $draft.resolution) {
                        ForEach(DesktopResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("View", selection: $draft.viewMode) {
                        ForEach(DesktopViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Session controls position", selection: $draft.sessionControlsPosition) {
                        Text("Use app setting").tag(SessionControlsPosition?.none)
                        ForEach(SessionControlsPosition.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Toggle("Open in full screen", isOn: $draft.openFullScreen)
                    Toggle("Reconnect after network interruptions", isOn: $draft.reconnectAutomatically)
                    Text("Automatic retries use a saved password, stop after five attempts, and never retry a rejected login.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Play Windows audio on this Mac", isOn: $draft.audioPlayback)
                    Toggle("Use Mac microphone in Windows", isOn: $draft.microphoneCapture)
                    Text("Microphone access is requested when connecting. Locking MacRDP disconnects microphone-enabled sessions to stop recording. Audio changes apply after reconnecting.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Typing", selection: $draft.textInputMode) {
                        ForEach(TextInputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text("Mac text / IME supports composition and international text. System shortcut capture is disabled in this mode.").font(.caption).foregroundStyle(.secondary)
                    Picker("Windows → Mac clipboard", selection: Binding(get: {
                        draft.clipboardSharing.map { $0 ? "on" : "off" } ?? "default"
                    }, set: { draft.clipboardSharing = $0 == "default" ? nil : $0 == "on" })) {
                        Text("Use app setting").tag("default"); Text("On").tag("on"); Text("Off").tag("off")
                    }
                    Toggle("Allow Paste Mac text action", isOn: $draft.allowMacPaste)
                    Toggle("Use PC-specific keyboard mapping", isOn: Binding(get: { draft.modifierMapping != nil }, set: { draft.modifierMapping = $0 ? model.modifierMapping : nil }))
                    if draft.modifierMapping != nil {
                        pcModifier("Command ⌘", \.command)
                        pcModifier("Control ⌃", \.control)
                        pcModifier("Option ⌥", \.option)
                        pcModifier("Shift ⇧", \.shift)
                    }
                    Text("Match window uses Retina backing pixels when enabled. Fixed resolution overrides that size. Live resizing requires host support. Changes to this PC apply to the next connection.")
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
            .onAppear { vpnProfiles = SystemVPNConnection.profiles() }
    }
    private func pcModifier(_ title: String, _ key: WritableKeyPath<ModifierMapping, WindowsModifier>) -> some View {
        Picker(title, selection: Binding(get: { (draft.modifierMapping ?? model.modifierMapping)[keyPath: key] }, set: {
            var mapping = draft.modifierMapping ?? model.modifierMapping; mapping[keyPath: key] = $0; draft.modifierMapping = mapping
        })) {
            ForEach(WindowsModifier.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case accessibility = "Accessibility"
    case keyboard = "Keyboard"
    case session = "Session"
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
    @State private var controlsPosition: SessionControlsPosition
    @State private var reverseHorizontalScrolling: Bool
    @State private var keepAwake: Bool
    @State private var clipboardSharing: Bool
    @State private var shortcutError: String?
    @State private var confirmRestart = false
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel) {
        self.model = model
        _shortcut = State(initialValue: model.shortcut); _three = State(initialValue: model.threeFinger)
        _controlsPosition = State(initialValue: model.sessionControlsPosition)
        _reverseHorizontalScrolling = State(initialValue: model.reverseHorizontalScrolling)
        _keepAwake = State(initialValue: model.keepAwake)
        _clipboardSharing = State(initialValue: model.clipboardSharing)
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
                        if model.hasRunningSessions { confirmRestart = true }
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
                } else if model.settingsSection == .session {
                    Form {
                        Section("Power") {
                            Toggle("Keep awake while connected", isOn: $keepAwake)
                            Text("Keeps your Mac and display awake during a connected session. Manual sleep and closing the lid still work.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Clipboard") {
                            Toggle("Share text clipboard: Windows → Mac", isOn: $clipboardSharing)
                            Text("Copy text in Windows with your configured shortcut or menu, then paste on Mac. Changes apply to new copies after saving. Mac text is sent only through the session’s Paste Mac text action when allowed for that PC.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Session controls") {
                            Picker("Position", selection: $controlsPosition) {
                                ForEach(SessionControlsPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            Text("Place the menu and Windows desktop buttons along the top or bottom of the session.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Scrolling") {
                            Toggle("Reverse horizontal scrolling", isOn: $reverseHorizontalScrolling)
                            Text("Reverse left/right scrolling with two fingers or a horizontal mouse wheel. Vertical scrolling stays the same.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.formStyle(.grouped)
                } else if model.settingsSection == .updates {
                    VStack { UpdatesView(updater: model.updater); Spacer(minLength: 0) }
                } else {
                    Form {
                Section("App security") {
                    Button("Change app PIN…") { model.settings = false; model.error = nil; model.pinChange = true }
                    Button("Reset PIN with Mac account…") { model.settings = false; model.error = nil; model.pinReset = true }
                    Text("MacRDP starts locked. After unlock, it stays open until you press Lock or quit. Locking disconnects microphone-enabled sessions to stop recording; other established sessions stay connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                    }.formStyle(.grouped)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save settings") { model.saveSettings(shortcut: shortcut, three: three, four: four, exclusive: exclusive, mapping: mapping, controlsPosition: controlsPosition, reverseHorizontalScrolling: reverseHorizontalScrolling, clipboardSharing: clipboardSharing, keepAwake: keepAwake) }
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
        model.saveSettings(shortcut: shortcut, three: three, four: four, exclusive: exclusive, mapping: mapping, controlsPosition: controlsPosition, reverseHorizontalScrolling: reverseHorizontalScrolling, clipboardSharing: clipboardSharing, keepAwake: keepAwake, dismiss: false)
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
