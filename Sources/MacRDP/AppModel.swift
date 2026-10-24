import AppKit
import SwiftUI
import ApplicationServices
import Carbon

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
    @Published var remaining = 10
    @Published var pcs: [PCProfile] = []
    @Published var selection: UUID?
    @Published var editor: PCProfile?
    @Published var credentialPrompt: PCProfile?
    @Published var certificateRequest: CertificateRequest?
    @Published var showSession = false
    @Published var activePC: PCProfile?
    @Published var phase: SessionPhase = .disconnected
    @Published var connectionError: String?
    @Published var activeResolution = "Waiting for desktop"
    @Published var dynamicResize = false
    @Published var hasPassword = false
    @Published var settings = false
    @Published var pinChange = false
    @Published private(set) var shortcut = KeyboardShortcut.default
    @Published var threeFinger: GestureMapping = .windowsDesktops
    @Published var fourFinger: GestureMapping = .macDesktops
    @Published var captureSystemShortcuts = false
    weak var window: NSWindow?
    weak var surface: RemoteDesktopView?
    private let vault: VaultService
    private let defaults: UserDefaults
    private let store: PCStore
    private var presentation: NSApplication.PresentationOptions?
    private var timer: Timer?
    private var began = Date()
    private var keyboardMonitor: Any?
    private var pointerMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var keyboardToggle = KeyboardToggle()
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
                if self.capture && reason == "Shortcut released to Mac" { self.captureValidated = true }
                self.finishRelease(reason: reason)
            case .action(let action): self.lastAction = action.rawValue
            }
        }
    }

    var profile: PCProfile { pcs.first { $0.id == selection } ?? PCProfile() }
    var releaseVerified: Bool { shortcutVerified && buttonVerified }
    var isConnecting: Bool { phase == .connecting || phase == .authenticating }
    var sessionRunning: Bool { isConnecting || phase == .connected }
    var canCapture: Bool { unlocked && phase == .connected && releaseVerified && !capture && !preparingCapture && !rehearsing && !settings && !pinChange && certificateRequest == nil && credentialPrompt == nil }

    init(defaults: UserDefaults = .standard, secretStore: any SecretStore = KeychainStore()) {
        vault = VaultService(store: secretStore)
        self.defaults = defaults
        store = PCStore(defaults: defaults)
        if let data = defaults.data(forKey: "keyboardToggleShortcut"),
           let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), saved.validationError == nil { shortcut = saved }
        threeFinger = GestureMapping(rawValue: defaults.string(forKey: "threeFingerAction") ?? "") ?? .windowsDesktops
        fourFinger = GestureMapping(rawValue: defaults.string(forKey: "fourFingerAction") ?? "") ?? .macDesktops
        captureSystemShortcuts = defaults.bool(forKey: "captureSystemShortcuts")
        do { pcs = try store.load(); selection = pcs.first?.id }
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
        Task {
            do {
                try await vault.open(pin: pin, setup: needsPIN)
                unlocked = true; needsPIN = false
            } catch { await vault.lock(); self.error = error.localizedDescription }
            loading = false
        }
    }
    func lockApp() {
        release(reason: "App locked · session stays connected")
        credentialGeneration = UUID()
        if isConnecting { disconnect() }
        if certificateRequest != nil { decideCertificate(accept: false, remember: false) }
        pendingStart = nil
        credentialPrompt = nil; editor = nil
        unlocked = false; settings = false; pinChange = false; hasPassword = false; error = nil
        loading = true
        Task { await vault.lock(); loading = false }
    }
    func select(_ id: UUID?) {
        release(reason: "Mac keyboard")
        selection = id
        showSession = activePC?.id == id && sessionRunning
    }
    func addPC() { release(reason: "Add PC"); error = nil; editor = PCProfile() }
    func editPC(_ pc: PCProfile) { release(reason: "Edit PC"); error = nil; editor = pc }
    func savePC(_ proposed: PCProfile, password: String) async -> Bool {
        guard unlocked else { return false }
        var next = proposed
        next.host = next.host.trimmingCharacters(in: .whitespacesAndNewlines)
        next.username = next.username.trimmingCharacters(in: .whitespacesAndNewlines)
        next.domain = next.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.name = next.host }
        if let problem = next.validationError { error = problem; return false }
        do {
            var updated = pcs
            let old = pcs.first { $0.id == next.id }
            if let index = updated.firstIndex(where: { $0.id == next.id }) { updated[index] = next } else { updated.append(next) }
            if next.rememberPassword && !password.isEmpty { try await vault.savePassword(password, id: next.id) }
            else if old?.credentialIdentity != next.credentialIdentity || !next.rememberPassword { try await vault.forgetPassword(next.id) }
            guard unlocked else { return false }
            try store.save(updated)
            pcs = updated; selection = next.id; editor = nil; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func deletePC(_ pc: PCProfile) async {
        guard unlocked else { return }
        if activePC?.id == pc.id && sessionRunning { error = "Disconnect this PC before deleting it."; return }
        do {
            try await vault.forgetPassword(pc.id)
            let updated = pcs.filter { $0.id != pc.id }
            try store.save(updated); pcs = updated
            if selection == pc.id { selection = updated.first?.id }
        } catch { self.error = error.localizedDescription }
    }
    func connect(_ pc: PCProfile, askCredentials: Bool = false) {
        guard unlocked, !sessionRunning else { return }
        if let problem = pc.validationError { error = problem; return }
        release(reason: "Preparing connection")
        connectionError = nil
        let request = UUID(); credentialGeneration = request
        if askCredentials || pc.username.isEmpty { credentialPrompt = pc; return }
        Task {
            do {
                let password = pc.rememberPassword ? try await vault.password(pc.id) : nil
                guard unlocked, credentialGeneration == request, !sessionRunning else { return }
                if let password {
                    beginConnection(pc, password: password)
                } else { if unlocked { credentialPrompt = pc } }
            } catch { self.error = error.localizedDescription }
        }
    }
    func submitCredentials(_ pc: PCProfile, password: String) async -> Bool {
        guard !pc.username.isEmpty, !password.isEmpty else { error = "Enter your Windows username and password."; return false }
        guard await savePC(pc, password: password), unlocked else { return false }
        credentialPrompt = nil
        beginConnection(pc, password: password)
        return true
    }
    private func beginConnection(_ pc: PCProfile, password: String) {
        guard unlocked, !sessionRunning else { return }
        transport?.cancel(); transport = nil
        surface?.clearDesktop()
        sessionGeneration = UUID(); activePC = pc; selection = pc.id; phase = .connecting
        dynamicResize = false; showSession = true; activeResolution = "Negotiating display…"
        pendingStart = (pc, password)
        surface?.reportGeometry()
    }
    func geometry(_ layout: DisplayLayout) {
        guard unlocked, showSession else { return }
        if let pending = pendingStart {
            pendingStart = nil
            let generation = sessionGeneration
            let session = RDPTransport { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.handle(event)
                }
            }
            transport = session
            tap.setInputSink({ [weak session] keys in session?.keys(keys) ?? false }, release: { [weak session] in session?.input(enabled: false) })
            let pins = defaults.dictionary(forKey: "rdpCertificatePins") as? [String: String] ?? [:]
            session.start(profile: pending.0, password: pending.1, layout: layout, fingerprint: pins[pending.0.endpoint] ?? "")
        } else if phase == .connected { transport?.resize(layout) }
    }
    private func handle(_ event: TransportEvent) {
        switch event {
        case .state(let value, let code):
            phase = value
            if value == .connected {
                guard unlocked else { release(reason: "App locked · session stays connected"); return }
                status = "Connected · click the desktop to use Windows input"
                window?.makeFirstResponder(surface)
                remoteInput = true; transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
                if activePC?.openFullScreen == true, window?.styleMask.contains(.fullScreen) != true { window?.toggleFullScreen(nil) }
            } else if value == .failed || value == .disconnected {
                release(reason: value.rawValue)
                certificateRequest = nil
                if value == .failed {
                    connectionError = ConnectionFailure.message(code)
                }
            }
        case .certificate(let request):
            guard unlocked else { transport?.certificate(accept: false); return }
            release(reason: "Verify Windows PC certificate"); certificateRequest = request
        case .cursor(let cursor): surface?.updateCursor(cursor)
        case .displayControl(let supported): dynamicResize = supported
        }
    }
    func disconnect() {
        release(reason: "Disconnecting…")
        pendingStart = nil
        if transport == nil { phase = .disconnected; certificateRequest = nil }
        else { transport?.cancel() }
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
    func useWindowsInput() {
        guard unlocked, phase == .connected, showSession else { return }
        window?.makeFirstResponder(surface)
        guard surfaceOwnsFocus else { return }
        if captureSystemShortcuts && releaseVerified { beginCapture(); return }
        remoteInput = true; transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
        status = "Windows input · \(shortcut.displayName) switches to Mac input"
        surface?.refreshCursor()
    }
    func toggleInput() { if remoteInput { release(reason: "Mac keyboard · session stays open") } else { useWindowsInput() } }
    func nativeKey(_ key: KeyStroke) {
        guard remoteInput, !capture, phase == .connected, surfaceOwnsFocus else { return }
        if transport?.keys([key]) == false { release(reason: "Input queue unavailable") }
    }
    func pointer(flags: UInt16, x: UInt16, y: UInt16) {
        guard remoteInput, phase == .connected, surfaceOwnsFocus else { return }
        transport?.pointer(flags: flags, x: x, y: y)
    }
    func rehearse() {
        guard unlocked, !pinChange else { return }
        release(reason: "Release rehearsal started")
        rehearsing = true; settings = false
        status = "Press \(shortcut.displayName) now. Capture is off."
        window?.makeFirstResponder(surface); began = Date(); remaining = 10
    }
    func releaseButton() {
        if unlocked { buttonVerified = true }
        release(reason: "Mac keyboard · session stays open")
    }
    func beginCapture() {
        guard canCapture, surfaceOwnsFocus else { status = "Verify the toggle shortcut and Release button in Settings first."; return }
        keyboardToggle.cancel()
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { status = "Lift modifier keys first."; return }
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            status = "Allow MacRDP in System Settings → Privacy & Security → Accessibility. Ordinary RDP input is still available."
            remoteInput = true; transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
            return
        }
        guard tap.prepare() else { status = "Keyboard capture unavailable. Use ordinary RDP input or check MacRDP permissions."; return }
        guard tap.isReady else { preparingCapture = true; began = Date(); return }
        presentation = NSApp.presentationOptions
        var options = NSApp.presentationOptions
        options.remove([.hideDock, .hideMenuBar]); options.formUnion([.autoHideDock, .autoHideMenuBar, .disableProcessSwitching])
        NSApp.presentationOptions = options
        transport?.input(enabled: true, capsLock: NSEvent.modifierFlags.contains(.capsLock))
        if let failure = tap.start(eligible: surfaceOwnsFocus, releaseVerified: releaseVerified, modifiersHeld: false, shortcut: shortcut, validated: captureValidated) {
            restorePresentation(); status = failure; return
        }
        capture = true; remoteInput = true; began = Date(); remaining = 10
        status = captureValidated ? "Windows shortcuts captured · \(shortcut.displayName) returns to Mac input" : "Press \(shortcut.displayName) within 10 seconds to verify captured release and enable continuous capture."
    }
    func release(reason: String) { tap.release(reason: reason, notify: false); finishRelease(reason: reason) }
    private func finishRelease(reason: String) {
        tap.release(reason: reason, notify: false); transport?.input(enabled: false)
        capture = false; remoteInput = false; preparingCapture = false; rehearsing = false
        tap.cancelTimer(); keyboardToggle.cancel(); restorePresentation(); surface?.resetTouches(); surface?.refreshCursor(); status = reason
        gestureRecognizer.reset()
    }
    private func restorePresentation() {
        if let presentation { NSApp.presentationOptions = presentation; self.presentation = nil }
    }
    var surfaceOwnsFocus: Bool {
        guard let surface, let window else { return false }
        return NSApp.isActive && window.isKeyWindow && window.firstResponder === surface
            && window.isOnActiveSpace && window.occlusionState.contains(.visible)
            && window.attachedSheet == nil && NSApp.modalWindow == nil && unlocked && !settings && !pinChange
            && editor == nil && credentialPrompt == nil && certificateRequest == nil && !IsSecureEventInputEnabled()
    }
    func touches(_ points: [TouchPoint], ended: Bool, cancelled: Bool = false) {
        guard surfaceOwnsFocus else { gestureRecognizer.reset(); return }
        if let action = gestureRecognizer.update(points, ended: ended, isCancelled: cancelled,
            threeFinger: threeFinger, fourFinger: fourFinger) { gesture(action) }
    }
    func gesture(_ action: TrackpadAction) {
        guard unlocked, surfaceOwnsFocus else { return }
        switch action {
        case .release: release(reason: "Mac desktop navigation · session stays open")
        case .desktopLeft, .desktopRight, .taskView:
            guard remoteInput, phase == .connected else { return }
            let command: WindowsAction = action == .taskView ? .taskView : action == .desktopLeft ? .desktopLeft : .desktopRight
            if transport?.keys(command.keys) == false { release(reason: "Input queue unavailable") }
        }
    }
    func openSettings() { release(reason: "Local settings"); error = nil; settings = true }
    func saveSettings(shortcut: KeyboardShortcut, three: GestureMapping, four: GestureMapping, exclusive: Bool) {
        if let problem = shortcut.validationError { error = problem; return }
        updateShortcut(shortcut)
        threeFinger = three; fourFinger = four; captureSystemShortcuts = exclusive
        defaults.set(three.rawValue, forKey: "threeFingerAction"); defaults.set(four.rawValue, forKey: "fourFingerAction")
        defaults.set(exclusive, forKey: "captureSystemShortcuts"); settings = false; error = nil
    }
    func updateShortcut(_ shortcut: KeyboardShortcut) {
        guard shortcut.validationError == nil, shortcut != self.shortcut else { return }
        release(reason: "Shortcut changed. Rehearse \(shortcut.displayName) before exclusive capture.")
        self.shortcut = shortcut; shortcutVerified = false; captureValidated = false
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
            if event.type == .keyDown, !event.isARepeat,
               self.shortcut.matches(keyCode: event.keyCode, flags: flags) {
                if self.rehearsing {
                    self.shortcutVerified = true
                    self.release(reason: self.buttonVerified ? "Both exits verified. Ready for the keyboard test." : "Shortcut verified. Click Release to verify the button too.")
                    return nil
                }
                if self.remoteInput {
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
                    eligible: self.surfaceOwnsFocus && self.phase == .connected && !self.remoteInput) {
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
                self.release(reason: "Local control selected")
            }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willCloseNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.remoteInput || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending else { return }
                    self.release(reason: "Window or application focus changed")
                }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.release(reason: name == NSWorkspace.activeSpaceDidChangeNotification
                        ? "Mac desktop changed · session stays open" : "Mac session paused")
                }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.remoteInput && !self.surfaceOwnsFocus { self.release(reason: "Mac input · session stays open") }
                if self.capture {
                    self.tap.heartbeat(eligible: self.surfaceOwnsFocus && AXIsProcessTrusted())
                }
                if self.remoteInput || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending {
                    self.remaining = max(0, 10 - Int(Date().timeIntervalSince(self.began)))
                    if self.remaining == 0 && ((self.capture && !self.captureValidated) || self.rehearsing || self.preparingCapture || self.keyboardToggle.pending) { self.release(reason: "Safety timeout · Mac input restored") }
                }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }


    func shutdown() {
        release(reason: "Application closed"); pendingStart = nil; transport?.cancel(); tap.shutdown()
        timer?.invalidate()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
