import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import Combine

actor VaultService {
    private var vault: AppVault?
    private let store: any SecretStore
    init(store: any SecretStore) { self.store = store }
    private func loaded() throws -> AppVault {
        if let vault { return vault }
        let created = try AppVault(store: store)
        vault = created
        return created
    }
    func needsSetup() throws -> Bool { try loaded().needsSetup }
    func open(pin: String, setup: Bool) throws {
        if setup { try loaded().setup(pin: pin) } else { try loaded().unlock(pin: pin) }
    }
    func openAfterOwnerAuthentication() throws { try loaded().unlockAfterOwnerAuthentication() }
    func resetPINAfterOwnerAuthentication(_ pin: String) throws {
        vault = try AppVault.resetPINAfterOwnerAuthentication(pin, store: store)
    }
    func lock() { vault?.lock() }
    func password(_ id: UUID) throws -> String? { try loaded().password(profile: id) }
    func hasPassword(_ id: UUID) throws -> Bool { try loaded().password(profile: id) != nil }
    func savePassword(_ password: String, id: UUID) throws { try loaded().savePassword(password, profile: id) }
    func forgetPassword(_ id: UUID) throws { try loaded().forgetPassword(profile: id) }
    func changePIN(current: String, replacement: String) throws {
        try loaded().changePIN(current: current, replacement: replacement)
    }
}

@MainActor
final class AppModel: ObservableObject {
    weak var workspace: AppModel?
    @Published private(set) var sessions: [AppModel] = []
    private var sessionSubscriptions: [ObjectIdentifier: AnyCancellable] = [:]
    var sessionCreated: ((AppModel) -> Void)?
    var allSessions: [AppModel] { workspace == nil ? sessions : [self] }
    var hasRunningSessions: Bool { sessionRunning || sessions.contains { $0.sessionRunning } }
    var hasConnectedSession: Bool { phase == .connected || sessions.contains { $0.phase == .connected } }
    private var keyboardTestSession: AppModel? {
        if let selection, let selected = session(for: selection), selected.phase == .connected { return selected }
        return sessions.first { $0.phase == .connected }
    }
    func session(for id: UUID) -> AppModel? { sessions.first { $0.activePC?.id == id } }
    func showSession(for id: UUID) { session(for: id)?.showSession = true }
    func suspendAllInput(reason: String) {
        suspendInput(reason: reason)
        for session in sessions { session.suspendInput(reason: reason) }
    }
    @Published var unlocked = false
    @Published var needsPIN = false
    @Published var loading = true
    @Published var error: String?
    @Published var captureValidated = false
    @Published var capture = false
    @Published var remoteInput = false
    @Published var preparingCapture = false
    @Published var rehearsing = false
    @Published var shortcutVerified = false
    @Published var buttonVerified = false
    @Published var status = "Choose a PC to connect."
    @Published var lastAction: String?
    @Published var gestureFeedback = "No three-finger swipe received yet."
    private var gestureTouchCount = 0
    @Published var remaining = 10
    @Published var pcs: [PCProfile] = [] {
        didSet {
            for session in sessions {
                guard let id = session.activePC?.id, let pc = pcs.first(where: { $0.id == id }) else { continue }
                let mappingChanged = session.activePC?.modifierMapping != pc.modifierMapping
                let clipboardChanged = session.activePC?.clipboardSharing != pc.clipboardSharing
                session.activePC = pc
                if mappingChanged || clipboardChanged {
                    session.suspendInput(reason: "PC input settings changed")
                    session.transport?.setModifierMapping(session.effectiveModifierMapping)
                    session.clipboardGeneration += 1
                    session.transport?.setClipboardSharing(session.effectiveClipboardSharing, generation: session.clipboardGeneration)
                }
            }
        }
    }
    @Published var selection: UUID?
    @Published var editor: PCProfile?
    @Published var credentialPrompt: PCProfile?
    @Published var certificateRequest: CertificateRequest?
    @Published var showSession = false {
        didSet { if showSession { showSessionWindow?() } }
    }
    @Published private(set) var sessionControlsOpen = false
    @Published private(set) var sessionControlsPosition = SessionControlsPosition.topCenter
    var effectiveSessionControlsPosition: SessionControlsPosition {
        activePC?.sessionControlsPosition ?? sessionControlsPosition
    }
    func setSessionControlsPosition(_ position: SessionControlsPosition?) {
        guard unlocked, let activePC else { return }
        let owner = workspace ?? self
        var updated = owner.pcs.first { $0.id == activePC.id } ?? activePC
        updated.sessionControlsPosition = position
        owner.persistProfile(updated)
        self.activePC = updated
    }
    @Published private(set) var reverseHorizontalScrolling = false
    @Published private(set) var keepAwake = true
    private(set) var sleepActivity: NSObjectProtocol?
    @Published private(set) var clipboardSharing = true
    private var clipboardGeneration: UInt64 = 1
    var writeClipboard: (String) -> Void = { text in
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
    }
    @Published var isFullScreen = false
    @Published var inputMode: InputMode = .windows
    @Published var presentedFPS = 0
    @Published var performanceDetail = "Waiting for display updates"
    @Published var reconnectMessage: String?
    @Published var sessionNotice: String?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var intentionalDisconnect = false
    private var sessionEstablished = false
    private(set) var pendingPaste: String?
    var readClipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    var effectiveModifierMapping: ModifierMapping { activePC?.modifierMapping ?? modifierMapping }
    var effectiveClipboardSharing: Bool { activePC?.clipboardSharing ?? clipboardSharing }
    var usesTextInput: Bool { activePC?.textInputMode == .text }
    var wantsExclusiveCapture: Bool { captureSystemShortcuts && !usesTextInput }
    @Published var settingsSection = SettingsSection.accessibility
    @Published var updates = false
    @Published var keyboardSetup = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var permissionMessage: String?
    @Published private(set) var captureIssue: String?
    @Published private(set) var captureTestRequested = false
    @Published private(set) var restarting = false
    weak var keyboardSetupWindow: NSWindow?
    var restartApplication: (() async throws -> Void)?
    var terminateApplication: (() -> Void)?
    private let keyboardAccess: KeyboardAccess
    private let microphoneAccess: MicrophoneAccess
    private var microphoneSession = false
    private var setupAfterSettings = false
    private var permissionCheckTime = Date.distantPast
    var closeSessionWindow: (() -> Void)?
    var showSessionWindow: (() -> Void)?
    var showMainWindow: (() -> Void)?
    var fullScreenTransition = false
    var menuOpen = false
    private var ownership = InputOwnership()
    @Published var activePC: PCProfile?
    @Published var phase: SessionPhase = .disconnected {
        didSet { updateSleepActivity() }
    }
    @Published var connectionError: String?
    @Published var activeResolution = "Waiting for desktop"
    @Published var dynamicResize = false
    @Published var hasPassword = false
    @Published var settings = false
    @Published var pinChange = false
    @Published var pinReset = false
    private let macAuthentication: any MacAuthenticating
    private var authenticationGeneration = UUID()
    @Published private(set) var shortcut = KeyboardShortcut.default
    @Published var threeFinger: GestureMapping = .windowsDesktops
    @Published var fourFinger: GestureMapping = .macDesktops
    @Published private(set) var modifierMapping = ModifierMapping.standard
    @Published var captureSystemShortcuts = true
    private var pendingDesktopAction: WindowsAction?
    weak var window: NSWindow?
    weak var surface: RemoteDesktopView?
    let updater = AppUpdater()
    private let vault: VaultService
    private let defaults: UserDefaults
    private let store: PCStore
    private let sessionPresentation: SessionPresentation
    private var timer: Timer?
    private var began = Date()
    private var keyboardMonitor: Any?
    private var pointerMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var keyboardToggle = KeyboardToggle()
    private var vpnTask: Task<Void, Never>?
    private let sessionVPN: SessionVPN
    @Published var vpnStatus: String?
    private var pendingStart: (PCProfile, String)?
    private var sessionGeneration = UUID()
    private var credentialGeneration = UUID()
    private(set) var transport: RDPTransport?
    private var gestureRecognizer = TrackpadGesture()
    private lazy var tap: KeyboardTap = KeyboardTap { [weak self] notice in
        DispatchQueue.main.async {
            guard let self else { return }
            switch notice {
            case .ready:
                if self.preparingCapture { self.preparingCapture = false; self.beginCapture() }
            case .released(let reason, let generation):
                guard self.tap.generation == generation else { return }
                if self.capture && reason == "Shortcut released to Mac" {
                    self.captureValidated = true
                    self.shareReleaseVerification()
                    self.defaults.set(try? JSONEncoder().encode(self.shortcut), forKey: "verifiedCaptureShortcut")
                    self.ownership.select(.mac); self.inputMode = .mac
                } else { self.ownership.fail(); self.captureIssue = reason }
                self.finishRelease(reason: reason)
            case .action(let action): self.lastAction = action.rawValue
            }
        }
    }

    var profile: PCProfile { pcs.first { $0.id == selection } ?? PCProfile() }
    var releaseVerified: Bool { shortcutVerified && buttonVerified }
    var isConnecting: Bool { phase == .connecting || phase == .authenticating }
    var sessionRunning: Bool { isConnecting || phase == .connected || phase == .reconnecting }
    var canCapture: Bool { unlocked && phase == .connected && releaseVerified && !capture && !preparingCapture && !rehearsing && !sessionControlsOpen && !keyboardSetup && !settings && !pinChange && !pinReset && certificateRequest == nil && credentialPrompt == nil }

    init(defaults: UserDefaults = .standard, secretStore: any SecretStore = HelperSecretStore(), keyboardAccess: KeyboardAccess = .live, macAuthentication: any MacAuthenticating = MacAuthentication(), sessionPresentation: SessionPresentation = SessionPresentation(), sessionVPN: SessionVPN = SessionVPN(), sharedVault: VaultService? = nil, microphoneAccess: MicrophoneAccess = .live) {
        self.microphoneAccess = microphoneAccess
        self.sessionVPN = sessionVPN
        self.sessionPresentation = sessionPresentation
        self.macAuthentication = macAuthentication
        self.keyboardAccess = keyboardAccess
        accessibilityGranted = keyboardAccess.isTrusted()
        vault = sharedVault ?? VaultService(store: secretStore)
        self.defaults = defaults
        store = PCStore(defaults: defaults)
        if let data = defaults.data(forKey: "keyboardToggleShortcut"),
           let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), saved.validationError == nil { shortcut = saved }
        if let data = defaults.data(forKey: "modifierMapping"),
           let saved = try? JSONDecoder().decode(ModifierMapping.self, from: data) { modifierMapping = saved }
        threeFinger = GestureMapping(rawValue: defaults.string(forKey: "threeFingerAction") ?? "") ?? .windowsDesktops
        fourFinger = GestureMapping(rawValue: defaults.string(forKey: "fourFingerAction") ?? "") ?? .macDesktops
        captureSystemShortcuts = defaults.object(forKey: "captureSystemShortcuts") == nil || defaults.bool(forKey: "captureSystemShortcuts")
        sessionControlsPosition = SessionControlsPosition(rawValue: defaults.string(forKey: "sessionControlsPosition") ?? "") ?? .topCenter
        reverseHorizontalScrolling = defaults.bool(forKey: "reverseHorizontalScrolling")
        keepAwake = defaults.object(forKey: "keepAwake") == nil || defaults.bool(forKey: "keepAwake")
        clipboardSharing = defaults.object(forKey: "clipboardSharing") == nil || defaults.bool(forKey: "clipboardSharing")
        if let data = defaults.data(forKey: "verifiedCaptureShortcut"),
           let verified = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), verified == shortcut {
            shortcutVerified = true; buttonVerified = true; captureValidated = true
        }
        do { pcs = try sharedVault == nil ? store.loadWithAudioDefaultsMigration() : store.load(); selection = pcs.first { $0.id.uuidString == defaults.string(forKey: "lastPC") }?.id ?? pcs.first?.id }
        catch { self.error = "Saved PCs could not be read. Existing data has not been replaced." }
    }

    func start() {
        installLifecycle()
        Task {
            do { needsPIN = try await vault.needsSetup() }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    func unlock(pin: String, confirmation: String) {
        guard !loading else { return }
        if needsPIN && pin != confirmation { error = "The PINs do not match."; return }
        loading = true; error = nil
        let generation = authenticationGeneration
        let setup = needsPIN
        Task {
            do {
                try await vault.open(pin: pin, setup: setup)
                guard generation == authenticationGeneration else { await vault.lock(); return }
                unlocked = true; needsPIN = false
                for session in sessions { session.unlocked = true }
            } catch {
                guard generation == authenticationGeneration else { return }
                await vault.lock(); self.error = error.localizedDescription
            }
            loading = false
        }
    }
    func unlockWithMac() async {
        await authenticateWithMac(replacement: nil)
    }

    func resetPINWithMac(replacement: String, confirmation: String) async {
        guard replacement == confirmation else { error = "The new PINs do not match."; return }
        guard PINRecord.valid(replacement) else { error = "Use 4–12 digits for your new PIN."; return }
        await authenticateWithMac(replacement: replacement)
    }

    private func authenticateWithMac(replacement: String?) async {
        guard !loading, !didShutdown else { return }
        loading = true; error = nil
        suspendInput(reason: "Mac authentication")
        let generation = authenticationGeneration
        do {
            try await macAuthentication.authenticate(reason: replacement == nil
                ? "unlock your saved remote desktops" : "reset your app PIN and keep your saved remote desktops")
            guard generation == authenticationGeneration else { return }
            if let replacement { try await vault.resetPINAfterOwnerAuthentication(replacement) }
            else { try await vault.openAfterOwnerAuthentication() }
            guard generation == authenticationGeneration else { await vault.lock(); return }
            needsPIN = try await vault.needsSetup()
            guard generation == authenticationGeneration else { await vault.lock(); return }
            unlocked = true; pinReset = false
            for session in sessions { session.unlocked = true }
        } catch {
            guard generation == authenticationGeneration else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func cancelAuthentication() {
        authenticationGeneration = UUID()
        macAuthentication.cancel()
    }

    func lockApp() {
        if let workspace { workspace.lockApp(); return }
        for session in sessions { session.lockSession() }
        cancelAuthentication()
        cancelReconnect()
        pendingPaste = nil
        release(reason: "App locked · session stays connected")
        credentialGeneration = UUID()
        if isConnecting || microphoneSession { disconnect() }
        if certificateRequest != nil { decideCertificate(accept: false, remember: false) }
        pendingStart = nil
        credentialPrompt = nil; editor = nil
        unlocked = false; settings = false; keyboardSetup = false; pinChange = false; pinReset = false; hasPassword = false; error = nil
        loading = true
        Task { await vault.lock(); loading = false }
    }
    private func lockSession() {
        cancelReconnect()
        release(reason: "App locked · session stays connected")
        credentialGeneration = UUID()
        if isConnecting || microphoneSession { disconnect() }
        if certificateRequest != nil { decideCertificate(accept: false, remember: false) }
        pendingStart = nil; credentialPrompt = nil; unlocked = false
        settings = false; keyboardSetup = false; pinChange = false; pinReset = false
    }
    func select(_ id: UUID?) {
        suspendInput(reason: "Mac keyboard")
        selection = id
        if let id { showSession(for: id) }
    }
    func addPC() { showMainWindow?(); suspendInput(reason: "Add PC"); error = nil; editor = PCProfile() }
    func editPC(_ pc: PCProfile) { showMainWindow?(); suspendInput(reason: "Edit PC"); error = nil; editor = pc }
    func savePC(_ proposed: PCProfile, password: String) async -> Bool {
        if let workspace {
            let saved = await workspace.savePC(proposed, password: password)
            error = workspace.error
            return saved
        }
        guard unlocked else { return false }
        var next = proposed
        next.host = next.host.trimmingCharacters(in: .whitespacesAndNewlines)
        next.username = next.username.trimmingCharacters(in: .whitespacesAndNewlines)
        next.domain = next.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.name = next.host }
        if let problem = next.validationError { error = problem; return false }
        do {
            let old = pcs.first { $0.id == next.id }
            if next.rememberPassword && !password.isEmpty { try await vault.savePassword(password, id: next.id) }
            else if old?.credentialIdentity != next.credentialIdentity || !next.rememberPassword { try await vault.forgetPassword(next.id) }
            guard unlocked, !didShutdown else { return false }
            var updated = pcs
            if let index = updated.firstIndex(where: { $0.id == next.id }) { updated[index] = next } else { updated.append(next) }
            try store.save(updated)
            pcs = updated; selection = next.id; editor = nil; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func persistProfile(_ profile: PCProfile) {
        if let workspace { workspace.persistProfile(profile); return }
        guard let index = pcs.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = pcs; updated[index] = profile
        do { try store.save(updated); pcs = updated } catch { self.error = error.localizedDescription }
    }
    func toggleFavorite(_ pc: PCProfile) {
        var next = pc; next.favorite.toggle(); persistProfile(next)
        if activePC?.id == pc.id { activePC?.favorite = next.favorite }
    }
    func duplicatePC(_ pc: PCProfile) {
        var next = pc; next.id = UUID(); next.name += " copy"; next.lastConnected = nil; next.rememberPassword = false
        editor = next
    }
    func setDisplay(resolution: DesktopResolution? = nil, mode: DesktopViewMode? = nil) {
        guard var pc = activePC else { return }
        if let resolution { pc.resolution = resolution }
        if let mode { pc.viewMode = mode }
        activePC = pc; persistProfile(pc); surface?.displaySettingsChanged()
        if resolution != nil && !dynamicResize { sessionNotice = "This host has not enabled live resizing. Reconnect to apply the resolution." }
    }
    func sendText(_ text: String) {
        guard remoteInput, !capture, usesTextInput, surfaceOwnsFocus, phase == .connected else { return }
        if transport?.text(text) != true { sessionNotice = "Text could not be sent. Try a shorter selection or the clipboard Paste action." }
    }
    func pasteMacText() {
        guard unlocked, phase == .connected, activePC?.allowMacPaste != false,
              let text = readClipboard(), !text.isEmpty else { return }
        guard text.utf16.count <= 8 * 1024 * 1024 - 1 else { sessionNotice = "Clipboard text is too large (maximum 16 MB)."; return }
        pendingPaste = text; sessionNotice = nil
        sessionControlsOpen = false
        window?.makeFirstResponder(surface)
    }
    func cancelReconnect() {
        reconnectTask?.cancel(); reconnectTask = nil; reconnectMessage = nil
        if phase == .reconnecting { credentialGeneration = UUID(); phase = .failed; endVPN() }
    }
    private func scheduleReconnect(code: UInt32) {
        guard unlocked, !intentionalDisconnect, sessionEstablished,
              let pc = activePC, pc.reconnectAutomatically, pc.rememberPassword,
              let delay = ConnectionFailure.retryDelay(code: code, attempt: reconnectAttempt) else { return }
        reconnectAttempt += 1; phase = .reconnecting
        reconnectMessage = "Retry \(reconnectAttempt) of 5 in \(Int(delay)) seconds. Check your VPN or network."
        let generation = sessionGeneration
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled, self.unlocked, self.sessionGeneration == generation,
                  self.phase == .reconnecting else { return }
            self.connect(pc, retry: true)
        }
    }
    func deletePC(_ pc: PCProfile) async {
        guard unlocked else { return }
        if (activePC?.id == pc.id && sessionRunning) || session(for: pc.id)?.sessionRunning == true { error = "Disconnect this PC before deleting it."; return }
        do {
            try await vault.forgetPassword(pc.id)
            let updated = pcs.filter { $0.id != pc.id }
            try store.save(updated); pcs = updated
            if selection == pc.id { selection = updated.first?.id }
        } catch { self.error = error.localizedDescription }
    }
    func connect(_ pc: PCProfile, askCredentials: Bool = false, retry: Bool = false) {
        if workspace == nil, sessionCreated != nil {
            guard unlocked else { return }
            let child = makeSession(for: pc)
            if !child.sessionRunning { child.connect(pc, askCredentials: askCredentials, retry: retry) }
            child.showSession = true
            return
        }
        if workspace == nil, let existing = session(for: pc.id), existing.sessionRunning {
            existing.showSession = true; return
        }
        guard unlocked, (!sessionRunning || (retry && phase == .reconnecting)) else { return }
        if !retry { cancelReconnect(); reconnectAttempt = 0; sessionEstablished = false }
        intentionalDisconnect = false
        if let problem = pc.validationError { error = problem; return }
        release(reason: "Preparing connection")
        connectionError = nil; reconnectMessage = nil; error = nil
        let request = UUID(); credentialGeneration = request
        if askCredentials || pc.username.isEmpty { if workspace == nil { showMainWindow?() }; credentialPrompt = pc; return }
        Task {
            do {
                let password = pc.rememberPassword ? try await vault.password(pc.id) : nil
                guard unlocked, credentialGeneration == request,
                      !sessionRunning || (retry && phase == .reconnecting) else { return }
                if retry { phase = .failed }
                if let password {
                    beginConnection(pc, password: password, automatically: retry)
                } else { if unlocked { if workspace == nil { showMainWindow?() }; credentialPrompt = pc } }
            } catch {
                guard credentialGeneration == request else { return }
                if retry { phase = .failed }
                self.error = error.localizedDescription
            }
        }
    }
    func submitCredentials(_ pc: PCProfile, password: String) async -> Bool {
        guard !pc.username.isEmpty, !password.isEmpty else { error = "Enter your Windows username and password."; return false }
        guard await savePC(pc, password: password), unlocked else { return false }
        credentialPrompt = nil
        beginConnection(pc, password: password)
        return true
    }
    private func beginConnection(_ pc: PCProfile, password: String, automatically: Bool = false) {
        guard unlocked, !didShutdown, !sessionRunning else { return }
        if workspace == nil, sessionCreated != nil {
            let child = makeSession(for: pc)
            child.beginConnection(pc, password: password, automatically: automatically)
            return
        }
        if !automatically { cancelReconnect(); reconnectAttempt = 0; sessionEstablished = false }
        intentionalDisconnect = false
        transport?.cancel(); transport = nil
        surface?.clearDesktop()
        pendingPaste = nil; sessionNotice = nil
        sessionGeneration = UUID(); activePC = pc; selection = pc.id; phase = .connecting
        microphoneSession = pc.microphoneCapture
        dynamicResize = false; performanceDetail = "Waiting for display updates"; activeResolution = "Negotiating display…"
        ownership.select(.windows); inputMode = .windows; captureIssue = nil
        defaults.set(pc.id.uuidString, forKey: "lastPC")
        let generation = sessionGeneration
        vpnStatus = pc.useVPN ? "Waiting for VPN connection" : nil
        if !automatically || !showSession { showSession = true }
        vpnTask?.cancel()
        vpnTask = Task { [weak self] in
            guard let self else { return }
            do {
                if pc.microphoneCapture {
                    vpnStatus = "Waiting for Mac microphone permission"
                    let permitted = await microphoneAccess.authorize()
                    try Task.checkCancellation()
                    guard unlocked, !didShutdown, generation == sessionGeneration, phase == .connecting else { return }
                    guard permitted else {
                        vpnStatus = nil; phase = .failed; microphoneSession = false
                        connectionError = MicrophoneAccess.recoveryMessage
                        error = connectionError
                        return
                    }
                }
                vpnStatus = pc.useVPN ? "Waiting for VPN connection" : nil
                try await sessionVPN.waitUntilConnected(id: pc.useVPN ? pc.vpnServiceID : nil)
                try Task.checkCancellation()
                guard unlocked, !didShutdown, generation == sessionGeneration, phase == .connecting else { return }
                microphoneSession = pc.microphoneCapture
                vpnStatus = nil; pendingStart = (pc, password)
                surface?.reportGeometry()
            } catch {
                guard !Task.isCancelled, generation == sessionGeneration else { return }
                vpnStatus = nil; phase = .failed; connectionError = error.localizedDescription
                self.error = error.localizedDescription
            }
        }
    }
    func makeSession(for pc: PCProfile) -> AppModel {
        if let existing = session(for: pc.id) { return existing }
        let child = AppModel(defaults: defaults, keyboardAccess: keyboardAccess, sharedVault: vault, microphoneAccess: microphoneAccess)
        child.workspace = self; child.activePC = pc
        child.unlocked = unlocked; child.loading = false
        child.applyPreferences(from: self)
        sessions.append(child)
        sessionSubscriptions[ObjectIdentifier(child)] = child.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        sessionCreated?(child)
        child.installLifecycle()
        return child
    }
    private func shareReleaseVerification() {
        guard let workspace, shortcut == workspace.shortcut else { return }
        workspace.shortcutVerified = shortcutVerified
        workspace.buttonVerified = buttonVerified
        workspace.captureValidated = captureValidated
        for session in workspace.sessions where session !== self {
            session.shortcutVerified = shortcutVerified; session.buttonVerified = buttonVerified
            session.captureValidated = captureValidated
        }
    }
    @discardableResult
    func geometry(_ layout: DisplayLayout) -> Bool {
        guard unlocked, showSession, !fullScreenTransition, !didShutdown else { return false }
        if let pending = pendingStart {
            pendingStart = nil
            if pending.0.microphoneCapture && microphoneAccess.authorizationStatus() != .authorized {
                phase = .failed; microphoneSession = false
                connectionError = MicrophoneAccess.recoveryMessage; error = connectionError
                return false
            }
            let generation = sessionGeneration
            let session = RDPTransport { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.handle(event)
                }
            }
            transport = session
            microphoneSession = pending.0.microphoneCapture
            session.setModifierMapping(effectiveModifierMapping)
            session.setClipboardSharing(effectiveClipboardSharing, generation: clipboardGeneration)
            tap.setInputSink({ [weak session] keys in session?.keys(keys) ?? false }, release: { [weak session] in session?.input(enabled: false) })
            let pins = defaults.dictionary(forKey: "rdpCertificatePins") as? [String: String] ?? [:]
            session.start(profile: pending.0, password: pending.1, layout: layout, fingerprint: pins[pending.0.endpoint] ?? "")
            surface?.wakePresentation()
            return true
        }
        guard phase == .connecting || phase == .authenticating || phase == .connected else { return false }
        return transport?.resize(layout) ?? false
    }
    func handle(_ event: TransportEvent) {
        switch event {
        case .frameAvailable: surface?.wakePresentation()
        case .state(let value, let code):
            phase = value
            if value == .connected {
                sessionEstablished = true; reconnectAttempt = 0; reconnectMessage = nil
                if var pc = activePC { pc.lastConnected = Date(); activePC = pc; persistProfile(pc) }
                surface?.wakePresentation()
                guard unlocked else { release(reason: "App locked · session stays connected"); return }
                status = "Connected · Windows control"
                if window?.isKeyWindow == true { window?.makeFirstResponder(surface) }
                resumeWindowsInput()
                surface?.reportGeometry(force: true)
                if window?.isKeyWindow == true, activePC?.openFullScreen == true,
                   window?.styleMask.contains(.fullScreen) != true { window?.toggleFullScreen(nil) }
            } else if value == .failed || value == .disconnected {
                release(reason: value.rawValue)
                certificateRequest = nil
                tap.setInputSink(nil, release: nil)
                transport = nil; microphoneSession = false; surface?.clearDesktop(); presentedFPS = 0
                if value == .failed { connectionError = ConnectionFailure.message(code) }
                if intentionalDisconnect { closeSessionPresentation() }
                else {
                    if value == .disconnected { connectionError = "The remote PC ended the connection." }
                    if let connectionError { error = connectionError }
                    scheduleReconnect(code: code)
                }
                if phase != .reconnecting { endVPN() }
                updater.sessionEnded()
                workspace?.updater.sessionEnded()
            }
        case .certificate(let request):
            guard unlocked else { transport?.certificate(accept: false); return }
            suspendInput(reason: "Verify Windows PC certificate"); certificateRequest = request
        case .cursor(let cursor): surface?.updateCursor(cursor)
        case .displayControl(let supported):
            dynamicResize = supported
            if supported { surface?.reportGeometry(force: true) }
        case .clipboard(let text, let generation): receiveClipboard(text, generation: generation)
        }
    }
    func receiveClipboard(_ text: String, generation: UInt64) {
        guard effectiveClipboardSharing, generation == clipboardGeneration, unlocked, phase == .connected,
              workspace == nil || window?.isKeyWindow == true else { return }
        writeClipboard(text)
    }
    func disconnect() {
        intentionalDisconnect = true; cancelReconnect(); pendingPaste = nil
        endVPN()
        credentialGeneration = UUID()
        clipboardGeneration += 1
        transport?.setClipboardSharing(false, generation: clipboardGeneration)
        release(reason: "Disconnecting…")
        pendingStart = nil
        certificateRequest = nil
        closeSessionPresentation()
        if transport == nil {
            microphoneSession = false
            phase = .disconnected
            updater.sessionEnded()
            workspace?.updater.sessionEnded()
        } else { transport?.cancel() }
    }
    private func endVPN() {
        vpnTask?.cancel(); vpnTask = nil; vpnStatus = nil
        sessionVPN.cancelWait()
    }
    private func closeSessionPresentation() {
        guard showSession || window != nil else { return }
        showSession = false; sessionControlsOpen = false
        closeSessionWindow?()
    }
    func decideCertificate(accept: Bool, remember: Bool) {
        guard let request = certificateRequest else { return }
        if accept && remember, let pc = activePC {
            var pins = defaults.dictionary(forKey: "rdpCertificatePins") as? [String: String] ?? [:]
            pins[pc.endpoint] = request.fingerprint; defaults.set(pins, forKey: "rdpCertificatePins")
        }
        transport?.certificate(accept: accept)
        certificateRequest = nil
    }
    func forgetCertificate(_ pc: PCProfile) {
        var pins = defaults.dictionary(forKey: "rdpCertificatePins") as? [String: String] ?? [:]
        pins.removeValue(forKey: pc.endpoint); defaults.set(pins, forKey: "rdpCertificatePins")
    }
    func setSessionControlsOpen(_ open: Bool) {
        guard sessionControlsOpen != open else { return }
        sessionControlsOpen = open
        if open {
            suspendInput(reason: "Session controls open")
        } else {
            window?.makeFirstResponder(surface)
            resumeWindowsInput()
        }
    }
    func useWindowsInput() {
        guard unlocked, phase == .connected else { return }
        ownership.select(.windows); inputMode = .windows; captureIssue = nil
        refreshKeyboardPermission()
        if wantsExclusiveCapture && (!accessibilityGranted || !captureValidated) {
            openKeyboardSetup()
            return
        }
        showSession = true
        window?.makeFirstResponder(surface)
        resumeWindowsInput()
    }
    func resumeWindowsInput() {
        let eligible = phase == .connected && surfaceOwnsFocus && !fullScreenTransition && !menuOpen
        guard (ownership.shouldResume(eligible: eligible) || (inputMode == .mac && eligible)), !preparingCapture, !rehearsing,
              !keyboardToggle.pending, surface?.hasTouches != true,
              NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)) else { return }
        let shouldCapture = inputMode == .windows && wantsExclusiveCapture && releaseVerified && accessibilityGranted
            && (captureValidated || captureTestRequested)
        if shouldCapture {
            if !capture { beginCapture() }
            return
        }
        guard !remoteInput else { return }
        remoteInput = true
        surface?.synchronizeCapsLock()
        transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
        status = keyboardControlDetail
        surface?.refreshCursor()
    }
    func toggleInput() {
        if inputMode == .windows { releaseButton() } else { useWindowsInput() }
    }
    func nativeKey(_ key: KeyStroke) {
        guard remoteInput, !capture, phase == .connected, surfaceOwnsFocus else { return }
        if transport?.keys([key]) == false { release(reason: "Input queue unavailable") }
    }
    func pointer(flags: UInt16, x: UInt16, y: UInt16) {
        guard remoteInput, phase == .connected, surfaceOwnsFocus else { return }
        transport?.pointer(flags: flags, x: x, y: y)
    }
    func rehearse() {
        guard unlocked, !pinChange && !pinReset else { return }
        release(reason: "Release rehearsal started")
        settings = false
        showSession = true
        window?.makeFirstResponder(surface)
        rehearsing = true; began = Date(); remaining = 10
        status = "Press \(shortcut.displayName) now. Capture is off."
    }
    func releaseButton() {
        captureIssue = nil
        if unlocked { buttonVerified = true; shareReleaseVerification() }
        release(reason: "Mac keyboard · session stays open")
    }
    func beginCapture() {
        guard !usesTextInput, canCapture, surfaceOwnsFocus, captureValidated || captureTestRequested else { status = "Verify the toggle shortcut and Release button in Settings first."; return }
        keyboardToggle.cancel()
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { status = "Lift modifier keys first."; return }
        guard keyboardAccess.isTrusted() else {
            refreshKeyboardPermission()
            status = "Enable MacRDP in Accessibility to capture Windows shortcuts."
            return
        }
        guard tap.prepare() else {
            ownership.fail()
            let reason = "macOS could not start keyboard capture. Check Accessibility for this copy of MacRDP, then retry or restart."
            captureIssue = reason; finishRelease(reason: reason)
            return
        }
        guard tap.isReady else { preparingCapture = true; began = Date(); return }
        if remoteInput { transport?.input(enabled: false); remoteInput = false }
        sessionPresentation.beginCapture()
        transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
        if let failure = tap.start(eligible: surfaceOwnsFocus, releaseVerified: releaseVerified, modifiersHeld: false, shortcut: shortcut, validated: captureValidated) {
            restorePresentation(); transport?.input(enabled: false); ownership.fail(); captureIssue = failure; status = failure; return
        }
        capture = true; remoteInput = true; captureTestRequested = false; surface?.synchronizeCapsLock(); surface?.refreshCursor(); began = Date(); remaining = 10
        status = captureValidated ? "Windows shortcuts captured · \(shortcut.displayName) returns to Mac input" : "Press \(shortcut.displayName) within 10 seconds to verify captured release and enable continuous capture."
    }
    func release(reason: String) {
        pendingPaste = nil
        pendingDesktopAction = nil
        ownership.select(.mac); inputMode = .mac
        finishRelease(reason: reason)
    }
    func suspendInput(reason: String) {
        pendingPaste = nil
        let waitingForTest = captureTestRequested && !capture && !preparingCapture
        finishRelease(reason: reason)
        captureTestRequested = waitingForTest
    }
    private func finishRelease(reason: String) {
        tap.release(reason: reason, notify: false); transport?.input(enabled: false)
        capture = false; remoteInput = false; preparingCapture = false; rehearsing = false; captureTestRequested = false
        tap.cancelTimer(); keyboardToggle.cancel(); restorePresentation(); surface?.resetTouches(); surface?.refreshCursor(); status = reason
        gestureRecognizer.reset(); gestureTouchCount = 0
    }
    private func restorePresentation() {
        sessionPresentation.restore()
    }
    var surfaceOwnsFocus: Bool {
        guard let surface, let window else { return false }
        return NSApp.isActive && window.isKeyWindow && window.firstResponder === surface
            && window.isOnActiveSpace && window.occlusionState.contains(.visible)
            && !menuOpen && !sessionControlsOpen && !keyboardSetup && !restarting && !fullScreenTransition && window.attachedSheet == nil && NSApp.modalWindow == nil && unlocked && !settings && !pinChange && !pinReset
            && !updates && editor == nil && credentialPrompt == nil && certificateRequest == nil && !IsSecureEventInputEnabled()
    }
    func touches(_ points: [TouchPoint], ended: Bool, cancelled: Bool = false) {
        guard surfaceOwnsFocus else { gestureRecognizer.reset(); gestureTouchCount = 0; return }
        gestureTouchCount = max(gestureTouchCount, points.count)
        if let action = gestureRecognizer.update(points, ended: ended, isCancelled: cancelled,
            threeFinger: threeFinger, fourFinger: fourFinger) { gesture(action) }
        else if cancelled && gestureTouchCount == 3 {
            gestureFeedback = "macOS cancelled the swipe. Check Trackpad settings for a conflicting three-finger gesture."
        }
        if points.isEmpty { gestureTouchCount = 0 }
    }
    func gesture(_ action: TrackpadAction) {
        guard unlocked, surfaceOwnsFocus else { return }
        switch action {
        case .release:
            ownership.swipeToMac()
            suspendInput(reason: "Mac desktop navigation · Windows control resumes when you return")
        case .desktopLeft, .desktopRight, .taskView:
            guard remoteInput, inputMode == .windows, phase == .connected else { return }
            let command: WindowsAction = action == .taskView ? .taskView : action == .desktopLeft ? .desktopLeft : .desktopRight
            guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
                gestureFeedback = "Lift the keyboard modifier keys before swiping."
                return
            }
            sendDesktopAction(command)
        }
    }
    func switchWindowsDesktop(_ action: WindowsAction) {
        guard unlocked, phase == .connected else { return }
        pendingDesktopAction = action
        captureIssue = nil
        sessionControlsOpen = false
        ownership.select(.windows); inputMode = .windows
        showSession = true
        window?.makeFirstResponder(surface)
    }
    private func sendDesktopAction(_ action: WindowsAction) {
        guard let transport else { return }
        if !transport.keys(action.keys, remapModifiers: false) {
            release(reason: "Input queue unavailable")
        } else {
            lastAction = action.rawValue
            gestureFeedback = action == .desktopLeft ? "Sent Ctrl+Windows+Left to Windows." : action == .desktopRight ? "Sent Ctrl+Windows+Right to Windows." : "Sent Windows+Tab to Windows."
        }
    }
    var keyboardControlState: KeyboardControlState {
        if !unlocked { return .locked }
        if phase != .connected { return .disconnected }
        if let captureIssue { return .failed(captureIssue) }
        if inputMode == .mac { return .mac }
        if wantsExclusiveCapture && !accessibilityGranted { return .permissionRequired }
        if capture && tap.isCapturing && tap.isEnabled {
            return captureValidated ? .active : .testing
        }
        if preparingCapture || captureTestRequested { return .starting }
        if wantsExclusiveCapture && !captureValidated { return .setupRequired }
        if sessionControlsOpen || keyboardSetup || settings || menuOpen || !remoteInput { return .paused }
        return .typingOnly
    }
    var keyboardControlDetail: String {
        switch keyboardControlState {
        case .active: return effectiveModifierMapping.summary + " · \(shortcut.displayName) returns to Mac."
        case .testing: return "Press \(shortcut.displayName) within \(remaining) seconds to finish setup."
        case .permissionRequired: return "macOS still handles system shortcuts. Enable MacRDP in System Settings → Privacy & Security → Accessibility."
        case .setupRequired: return "Windows typing is available. Complete Keyboard setup to send system shortcuts to Windows."
        case .typingOnly: if usesTextInput { return "Mac text input and IME are active. System shortcuts stay on your Mac." }; return "System shortcut capture is off. macOS still handles Command+Tab and other Mac shortcuts."
        case .paused: return "Local controls or another window have focus. Return to the Windows desktop to resume."
        case .mac: return "Type, click and scroll in Windows. Mac system shortcuts stay local; Command+V pastes Mac text."
        case .starting: return "Return to the remote desktop and lift all shortcut keys."
        case .failed(let reason): return reason
        case .locked: return "Unlock MacRDP to use the session."
        case .disconnected: return "Connect to a Windows PC to test keyboard control."
        }
    }
    func verifySetupShortcut(key: UInt16, flags: CGEventFlags, window: NSWindow?, isRepeat: Bool) -> Bool {
        guard unlocked, keyboardSetup, !restarting, let setupWindow = keyboardSetupWindow,
              window === setupWindow, !isRepeat, !IsSecureEventInputEnabled(),
              shortcut.matches(keyCode: key, flags: flags) else { return false }
        shortcutVerified = true
        shareReleaseVerification()
        return true
    }
    func refreshKeyboardPermission() {
        permissionCheckTime = Date()
        let granted = keyboardAccess.isTrusted()
        guard accessibilityGranted != granted else { return }
        let wasCapturing = capture || preparingCapture || captureTestRequested
        accessibilityGranted = granted
        if !granted && wasCapturing {
            captureIssue = "Accessibility permission was removed. Enable it again and retry Windows control."
            ownership.fail()
            finishRelease(reason: "Accessibility permission removed")
        }
    }
    func openKeyboardPermissionSettings() {
        suspendInput(reason: "Accessibility settings")
        keyboardAccess.request()
        permissionMessage = keyboardAccess.openSettings() ? nil : "Open System Settings → Privacy & Security → Accessibility, then enable MacRDP."
        refreshKeyboardPermission()
    }
    func settingsDidClose() {
        if setupAfterSettings { setupAfterSettings = false; openKeyboardSetup() }
    }
    func openKeyboardSetup() {
        if settings { setupAfterSettings = true; settings = false; return }
        suspendInput(reason: "Keyboard setup")
        sessionControlsOpen = false
        settings = false
        if workspace == nil { showMainWindow?() }
        refreshKeyboardPermission()
        keyboardSetup = true
    }
    func testWindowsControl() {
        if workspace == nil, !sessions.isEmpty {
            let target = keyboardTestSession
            guard let target else { return }
            keyboardSetup = false
            target.applyPreferences(from: self)
            target.testWindowsControl()
            return
        }
        refreshKeyboardPermission()
        guard unlocked, phase == .connected, accessibilityGranted, releaseVerified else { return }
        suspendInput(reason: "Preparing keyboard test")
        captureIssue = nil
        captureSystemShortcuts = true
        workspace?.captureSystemShortcuts = true
        defaults.set(true, forKey: "captureSystemShortcuts")
        ownership.select(.windows); inputMode = .windows
        keyboardSetup = false; settings = false; sessionControlsOpen = false
        showSession = true
        window?.makeFirstResponder(surface)
        captureTestRequested = true; began = Date(); remaining = 10
        resumeWindowsInput()
    }
    func restartApp() async {
        if let workspace { await workspace.restartApp(); return }
        guard !restarting else { return }
        guard let restartApplication else {
            permissionMessage = "Restart is unavailable. Quit MacRDP and open it again."
            return
        }
        restarting = true
        suspendInput(reason: "Restarting MacRDP")
        do {
            try await restartApplication()
            prepareForTermination()
            terminateApplication?()
        } catch {
            permissionMessage = "Could not restart MacRDP. Quit and reopen this copy of the app."
            restarting = false
        }
    }
    func openSettings() {
        if let workspace { workspace.openSettings(); return }
        suspendAllInput(reason: "Local settings"); showMainWindow?(); error = nil; settings = true }
    func openUpdates() { settingsSection = .updates; openSettings() }
    func saveSettings(shortcut: KeyboardShortcut, three: GestureMapping, four: GestureMapping, exclusive: Bool, mapping: ModifierMapping? = nil, controlsPosition: SessionControlsPosition? = nil, reverseHorizontalScrolling: Bool? = nil, clipboardSharing: Bool? = nil, keepAwake: Bool? = nil, dismiss: Bool = true) {
        if let problem = shortcut.validationError { error = problem; return }
        updateShortcut(shortcut)
        if let mapping, mapping != modifierMapping {
            suspendInput(reason: "Keyboard mapping changed")
            modifierMapping = mapping
            transport?.setModifierMapping(effectiveModifierMapping)
            defaults.set(try? JSONEncoder().encode(mapping), forKey: "modifierMapping")
        }
        threeFinger = three; fourFinger = four; captureSystemShortcuts = exclusive
        if let keepAwake {
            self.keepAwake = keepAwake
            defaults.set(keepAwake, forKey: "keepAwake")
            updateSleepActivity()
        }
        if let clipboardSharing, clipboardSharing != self.clipboardSharing {
            self.clipboardSharing = clipboardSharing
            clipboardGeneration += 1
            transport?.setClipboardSharing(effectiveClipboardSharing, generation: clipboardGeneration)
            defaults.set(clipboardSharing, forKey: "clipboardSharing")
        }
        if let controlsPosition {
            sessionControlsPosition = controlsPosition
            defaults.set(controlsPosition.rawValue, forKey: "sessionControlsPosition")
        }
        if let reverseHorizontalScrolling, reverseHorizontalScrolling != self.reverseHorizontalScrolling {
            surface?.resetScrolling()
            self.reverseHorizontalScrolling = reverseHorizontalScrolling
            defaults.set(reverseHorizontalScrolling, forKey: "reverseHorizontalScrolling")
        }
        defaults.set(three.rawValue, forKey: "threeFingerAction"); defaults.set(four.rawValue, forKey: "fourFingerAction")
        defaults.set(exclusive, forKey: "captureSystemShortcuts"); if dismiss { settings = false }; error = nil
        for session in sessions { session.applyPreferences(from: self) }
    }
    private func applyPreferences(from owner: AppModel) {
        suspendInput(reason: "Preferences updated")
        shortcut = owner.shortcut; shortcutVerified = owner.shortcutVerified
        buttonVerified = owner.buttonVerified; captureValidated = owner.captureValidated
        modifierMapping = owner.modifierMapping; threeFinger = owner.threeFinger; fourFinger = owner.fourFinger
        captureSystemShortcuts = owner.captureSystemShortcuts; keepAwake = owner.keepAwake
        clipboardSharing = owner.clipboardSharing; sessionControlsPosition = owner.sessionControlsPosition
        reverseHorizontalScrolling = owner.reverseHorizontalScrolling
        clipboardGeneration += 1
        transport?.setClipboardSharing(effectiveClipboardSharing, generation: clipboardGeneration)
        transport?.setModifierMapping(effectiveModifierMapping)
        updateSleepActivity()
    }
    func updateShortcut(_ shortcut: KeyboardShortcut) {
        guard shortcut.validationError == nil, shortcut != self.shortcut else { return }
        release(reason: "Shortcut changed. Open Keyboard setup to verify \(shortcut.displayName).")
        self.shortcut = shortcut; shortcutVerified = false; captureValidated = false
        defaults.removeObject(forKey: "verifiedCaptureShortcut")
        if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: "keyboardToggleShortcut") }
    }
    func changePIN(current: String, replacement: String, confirmation: String) async -> Bool {
        guard unlocked else { return false }
        guard replacement == confirmation else { error = "The new PINs do not match."; return false }
        do { try await vault.changePIN(current: current, replacement: replacement); error = nil; pinChange = false; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func installLifecycle() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            guard (self.window != nil && event.window === self.window)
                || (self.keyboardSetup && self.keyboardSetupWindow != nil && event.window === self.keyboardSetupWindow) else { return event }
            if self.inputMode == .mac && self.surfaceOwnsFocus && event.modifierFlags.contains(.command) {
                self.transport?.input(enabled: false)
                self.transport?.input(enabled: true, capsLock: event.modifierFlags.contains(.capsLock))
                if event.type == .keyDown, RemoteKeyboardPolicy.pastesMacText(mode: self.inputMode, key: event.keyCode,
                    command: true, control: event.modifierFlags.contains(.control),
                    option: event.modifierFlags.contains(.option), shift: event.modifierFlags.contains(.shift)) {
                    if !event.isARepeat { self.pasteMacText() }
                    return nil
                }
            }
            if event.type == .keyDown, !event.isARepeat,
               self.shortcut.matches(keyCode: event.keyCode, flags: flags) {
                if self.verifySetupShortcut(key: event.keyCode, flags: flags, window: event.window, isRepeat: event.isARepeat) { return nil }
                if self.rehearsing {
                    self.shortcutVerified = true
                    self.shareReleaseVerification()
                    self.release(reason: self.buttonVerified ? "Both exits verified. Ready for the keyboard test." : "Shortcut verified. Click Release to verify the button too.")
                    return nil
                }
                if self.remoteInput && self.inputMode == .windows {
                    self.release(reason: "Mac keyboard · session stays open")
                    return nil
                }
                if self.surfaceOwnsFocus && self.phase == .connected && !self.preparingCapture {
                    self.keyboardToggle.request()
                    self.began = Date()
                    self.status = "Lift the shortcut keys to switch to Windows input."
                    return nil
                }
            }
            if self.keyboardToggle.pending {
                let keyHeld = event.type == .keyUp && event.keyCode == self.shortcut.keyCode ? false
                    : CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(self.shortcut.keyCode))
                if self.keyboardToggle.takeIfReleased(keyHeld: keyHeld,
                    modifiersHeld: flags.rawValue & KeyboardShortcut.modifierMask != 0,
                    eligible: self.surfaceOwnsFocus && self.phase == .connected && self.inputMode == .mac) {
                    self.useWindowsInput()
                }
            }
            if event.type == .keyUp, event.keyCode == self.shortcut.keyCode, self.keyboardToggle.pending {
                return nil
            }
            return event
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.remoteInput || self.keyboardToggle.pending, let surface = self.surface else { return event }
            let point = surface.convert(event.locationInWindow, from: nil)
            if event.window !== self.window || !surface.bounds.contains(point) {
                self.suspendInput(reason: "Local control selected")
            }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willCloseNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let changedWindowID = (notification.object as? NSWindow).map { ObjectIdentifier($0) }
                MainActor.assumeIsolated {
                    guard let self, self.remoteInput || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending else { return }
                    if let changedWindowID, changedWindowID != self.window.map({ ObjectIdentifier($0) }) { return }
                    self.suspendInput(reason: "Window or application focus changed")
                }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name != NSWorkspace.activeSpaceDidChangeNotification && self.microphoneSession {
                        self.disconnect()
                    }
                    self.suspendInput(reason: name == NSWorkspace.activeSpaceDidChangeNotification
                        ? "Mac desktop changed · session stays open" : "Mac session paused")
                }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let permissionInterval: TimeInterval = (self.remoteInput && self.wantsExclusiveCapture) || self.keyboardSetup || self.settings ? 1 : 10
                if Date().timeIntervalSince(self.permissionCheckTime) >= permissionInterval { self.refreshKeyboardPermission(); self.surface?.refreshIdleMetrics() }
                if self.remoteInput && !self.surfaceOwnsFocus { self.suspendInput(reason: "Mac input · session stays open") }
                self.resumeWindowsInput()
                if let action = self.pendingDesktopAction, self.remoteInput, self.surfaceOwnsFocus,
                   NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    self.pendingDesktopAction = nil
                    self.sendDesktopAction(action)
                }
                if let text = self.pendingPaste, self.remoteInput, self.surfaceOwnsFocus,
                   NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    self.pendingPaste = nil
                    if self.transport?.paste(text) != true { self.sessionNotice = "Clipboard is not ready. Wait a moment and try Paste again." }
                }
                if !self.sessionRunning && !self.keyboardSetup && !self.rehearsing { self.timer?.fireDate = Date().addingTimeInterval(1) }
                if self.capture {
                    self.tap.heartbeat(eligible: self.surfaceOwnsFocus && self.accessibilityGranted)
                }
                if self.remoteInput || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending || self.captureTestRequested {
                    let remaining = max(0, 10 - Int(Date().timeIntervalSince(self.began)))
                    if self.remaining != remaining { self.remaining = remaining }
                    if self.remaining == 0 && ((self.capture && !self.captureValidated) || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending || self.captureTestRequested) {
                        self.captureIssue = "Keyboard test timed out. Open Keyboard setup and try again."
                        self.release(reason: "Safety timeout · Mac input restored")
                    }
                }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }


    private func updateSleepActivity() {
        if keepAwake && phase == .connected && !didShutdown {
            guard sleepActivity == nil else { return }
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "MacRDP connected session")
        } else if let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }

    func dismissLocalDialogs() {
        for session in sessions { session.dismissLocalDialogs() }
        settings = false; keyboardSetup = false; updates = false; pinChange = false; pinReset = false
        editor = nil; credentialPrompt = nil; certificateRequest = nil
        suspendInput(reason: "Preparing to close MacRDP")
    }
    func prepareForTermination() {
        for session in sessions { session.prepareForTermination() }
        cancelReconnect()
        dismissLocalDialogs()
        shutdown()
    }
    private var didShutdown = false
    func shutdown() {
        for session in sessions { session.shutdown() }
        endVPN()
        cancelAuthentication()
        cancelReconnect()
        guard !didShutdown else { return }
        didShutdown = true
        credentialGeneration = UUID()
        updateSleepActivity()
        release(reason: "Application closed"); pendingStart = nil; transport?.cancel(); tap.shutdown()
        timer?.invalidate(); timer = nil
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
