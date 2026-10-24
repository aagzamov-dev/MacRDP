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
        .sheet(isPresented: $model.settings) { AppSettings(model: model) }
        .sheet(isPresented: $model.pinChange) { ChangePINView(model: model) }
        .sheet(item: $model.editor) { pc in PCEditor(model: model, pc: pc, connecting: false) }
        .sheet(item: $model.credentialPrompt) { pc in PCEditor(model: model, pc: pc, connecting: true) }
        .sheet(item: $model.certificateRequest) { request in CertificateView(model: model, request: request) }
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
            if model.showSession && model.activePC != nil { SessionPane(model: model) }
            else if model.pcs.contains(where: { $0.id == model.selection }) { pcDetail(model.profile) }
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

struct SessionPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.activePC?.name ?? "Windows", systemImage: "pc").font(.headline)
                Text(model.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.phase == .connected {
                    Button("Use Windows input") { model.useWindowsInput() }.disabled(model.remoteInput)
                    Button("Mac input") { model.releaseButton() }
                    Button { model.window?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .help("Toggle full screen")
                }
                Button(model.isConnecting ? "Cancel" : "Disconnect") { model.disconnect() }
                    .disabled(!model.sessionRunning)
            }.padding(.horizontal, 16).padding(.vertical, 12)
            ZStack {
                SessionSurface(model: model)
                if model.isConnecting {
                    VStack(spacing: 14) { ProgressView(); Text("\(model.phase.rawValue) \(model.activePC?.host ?? "PC")") }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if model.phase == .failed || model.phase == .disconnected {
                    ContentUnavailableView {
                        Label(model.phase.rawValue, systemImage: "network.slash")
                    } description: {
                        Text(model.connectionError ?? "Your saved PC is ready whenever you want to reconnect.")
                    } actions: {
                        if let pc = model.activePC {
                            Button("Reconnect") { model.connect(pc) }.buttonStyle(.borderedProminent)
                            Button("Enter login…") { model.connect(pc, askCredentials: true) }
                        }
                    }.background(.background)
                }
            }
            HStack(spacing: 12) {
                Label(model.remoteInput ? "Windows input" : "Mac input", systemImage: model.remoteInput ? "keyboard.fill" : "keyboard")
                    .foregroundStyle(model.remoteInput ? Color.accentColor : .secondary)
                Text(model.shortcut.displayName + " to toggle")
                Spacer()
                Text(model.activeResolution)
                if model.activePC?.optimizeRetina == true { Text("Retina") }
                Text(model.dynamicResize ? "Dynamic resize" : "Fixed / awaiting display control")
            }.font(.caption).padding(10).background(.bar)
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}

struct PCEditor: View {
    @ObservedObject var model: AppModel
    @State private var draft: PCProfile
    @State private var password = ""
    @State private var saving = false
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
                    TextField("Port", text: $draft.port)
                }
                Section("Windows login") {
                    TextField("Username", text: $draft.username)
                    TextField("Domain (optional)", text: $draft.domain)
                    SecureField(connecting ? "Windows password" : "New password (optional)", text: $password)
                    Toggle("Remember password in Keychain", isOn: $draft.rememberPassword)
                    Text(connecting ? "Use your account password, not your Windows Hello PIN." : "Leave blank to keep the saved password for this address and account. Changing either removes the old saved password.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Display") {
                    Toggle("Optimize for Retina", isOn: $draft.optimizeRetina)
                    Picker("Windows UI scale", selection: $draft.desktopScale) {
                        Text("Automatic").tag(0)
                        ForEach([100, 125, 150, 175, 200, 250, 300], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    Toggle("Open in full screen", isOn: $draft.openFullScreen)
                    Text("Retina uses the view’s backing pixels. Resolution updates automatically when the server supports display control. Changes to this PC apply to the next connection.")
                        .font(.caption).foregroundStyle(.secondary)
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

struct AppSettings: View {
    @ObservedObject var model: AppModel
    @State private var shortcut: KeyboardShortcut
    @State private var three: GestureMapping
    @State private var four: GestureMapping
    @State private var exclusive: Bool
    @State private var shortcutError: String?
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel) {
        self.model = model
        _shortcut = State(initialValue: model.shortcut); _three = State(initialValue: model.threeFinger)
        _four = State(initialValue: model.fourFinger); _exclusive = State(initialValue: model.captureSystemShortcuts)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Settings", systemImage: "gearshape").font(.title3.weight(.semibold)); Spacer() }.padding(24)
            Form {
                Section("Keyboard") {
                    HStack { Text("Mac ↔ Windows input"); Spacer(); ShortcutRecorder(shortcut: $shortcut, error: $shortcutError).frame(width: 180) }
                    Text("Click to record a shortcut. Toggling input keeps the connection and full screen intact.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore default \(KeyboardShortcut.default.displayName)") { shortcut = .default; shortcutError = nil }.buttonStyle(.link)
                    Toggle("Capture Mac system shortcuts", isOn: $exclusive)
                    Text("Optional: forwards Command+Tab as Windows+Tab. Requires MacRDP Accessibility permission and verified release controls. During initial verification, exclusive capture has a 10-second timeout. Ordinary RDP input does not need this permission.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Label("Shortcut", systemImage: model.shortcutVerified ? "checkmark.circle.fill" : "circle")
                        Label("Release", systemImage: model.buttonVerified ? "checkmark.circle.fill" : "circle")
                        Spacer()
                        Button("Verify saved toggle") { model.rehearse() }
                    }
                    if let shortcutError { Text(shortcutError).foregroundStyle(.red).font(.caption) }
                }
                Section("Trackpad gestures") {
                    Picker("Three fingers", selection: $three) { ForEach(GestureMapping.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Four fingers", selection: $four) { ForEach(GestureMapping.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Text("macOS may reserve a gesture before the app sees it. These settings do not change system gesture preferences. Mac desktop navigation releases input and leaves the RDP session open.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("App security") {
                    Button("Change app PIN…") { model.settings = false; model.error = nil; model.pinChange = true }
                    Text("MacRDP starts locked. After unlock, it stays open until you press Lock or quit. Locking the app keeps an established session connected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save settings") { model.saveSettings(shortcut: shortcut, three: three, four: four, exclusive: exclusive) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 580, height: 710).background(Color(nsColor: .windowBackgroundColor))
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
