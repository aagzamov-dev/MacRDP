import AppKit
import SwiftUI

@MainActor
func render(_ view: NSView, name: String) throws {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fatalError("No native bitmap available")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode native preview")
    }
    try png.write(to: URL(fileURLWithPath: "build/\(name).png"))
}

if CommandLine.arguments.contains("--termination-fixture") {
    await MainActor.run {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let model = AppModel(secretStore: TestSecrets())
        let delegate = AppDelegate(model: model)
        app.delegate = delegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        sheet.contentView = NSHostingView(rootView: Text("Test sheet").permitsAppTermination())
        sheet.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(!sheet.preventsApplicationTerminationWhenModal)
        window.beginSheet(sheet)
        model.settings = true
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }
    exit(99)
}
if CommandLine.arguments.contains("--restart-wait-fixture") {
    try await MainActor.run {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let parent = Process(); parent.executableURL = URL(fileURLWithPath: "/bin/sleep"); parent.arguments = ["1"]
        try parent.run()
        let waiter = Process(); waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", AppRestart.waitForExitScript, "restart-test", String(parent.processIdentifier), "/usr/bin/touch", marker.path]
        try waiter.run()
        Thread.sleep(forTimeInterval: 0.2)
        precondition(!FileManager.default.fileExists(atPath: marker.path))
        parent.waitUntilExit(); waiter.waitUntilExit()
        precondition(waiter.terminationStatus == 0 && FileManager.default.fileExists(atPath: marker.path))
    }
    exit(0)
}

await MainActor.run {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let suite = "uz.macrdp.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var pc = PCProfile(); pc.name = "Office Windows"; pc.host = "office.example"; pc.username = "Test account"
    try! PCStore(defaults: defaults).save([pc])
    let model = AppModel(defaults: defaults)
    let unavailableTap = KeyboardTap { _ in }
    precondition(unavailableTap.start(eligible: true, releaseVerified: true, modifiersHeld: false) != nil)
    precondition(!unavailableTap.isCapturing)
    unavailableTap.shutdown()
    let rightCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
    precondition(KeyboardTap.modifierDown(key: 54, flags: rightCommand))
    precondition(!KeyboardTap.modifierDown(key: 55, flags: rightCommand))
    precondition(KeyboardTap.action(key: 48, flags: .maskCommand) == .taskView)
    precondition(KeyboardTap.action(key: 48, flags: .maskAlternate) == .appSwitcher)
    precondition(KeyboardTap.action(key: 48, flags: [.maskControl, .maskShift]) == .previousTab)
    precondition(!model.unlocked && !model.canCapture)
    model.loading = false
    model.needsPIN = true
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    model.window = window
    let hosting = NSHostingView(rootView: ContentView(model: model))
    window.contentView = hosting
    do {
        try render(hosting, name: "client-lock-preview")
        model.unlocked = true
        try render(hosting, name: "client-workspace-preview")
        precondition(!model.canCapture)
        model.rehearse()
        precondition(model.rehearsing && !model.capture)
        model.releaseButton()
        precondition(model.buttonVerified && !model.canCapture)
        model.shortcutVerified = true
        model.phase = .connected
        precondition(model.canCapture)
        model.capture = true
        model.release(reason: "Native smoke cleanup")
        precondition(!model.capture && !model.rehearsing)
        precondition(model.window === window && !app.isHidden)
        let custom = KeyboardShortcut(keyCode: 4, modifiers: CGEventFlags.maskControl.rawValue, keyName: "H")
        model.updateShortcut(custom)
        precondition(!model.shortcutVerified && !model.canCapture)
        let relaunched = AppModel(defaults: defaults)
        precondition(relaunched.shortcut == custom && !relaunched.unlocked)
        model.openSettings()
        precondition(!model.canCapture)
        model.phase = .connected
        model.lockApp()
        precondition(model.phase == .connected)
        precondition(!model.unlocked && !model.settings && !model.capture)
        model.shutdown()
        relaunched.shutdown()
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740),
            styleMask: [.titled], backing: .buffered, defer: false)
        let settingsView = NSHostingView(rootView: AppSettings(model: model))
        settingsWindow.contentView = settingsView
        try render(settingsView, name: "client-settings-preview")
        for section in SettingsSection.allCases {
            model.settingsSection = section
            try render(settingsView, name: "client-settings-" + section.rawValue.lowercased())
        }
        model.settingsSection = .accessibility
        let editorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740), styleMask: [.titled], backing: .buffered, defer: false)
        let editorView = NSHostingView(rootView: PCEditor(model: model, pc: pc, connecting: false))
        editorWindow.contentView = editorView
        try render(editorView, name: "client-pc-editor-preview")
        let sessionModel = AppModel(defaults: defaults, secretStore: TestSecrets())
        sessionModel.unlocked = true; sessionModel.activePC = pc; sessionModel.phase = .connected
        sessionModel.isFullScreen = true; sessionModel.captureValidated = true; sessionModel.buttonVerified = true
        let sessionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        sessionModel.window = sessionWindow
        sessionWindow.isReleasedWhenClosed = false
        let sessionView = NSHostingView(rootView: SessionWindowView(model: sessionModel))
        sessionWindow.contentView = sessionView
        try render(sessionView, name: "client-fullscreen-preview")
        precondition(sessionModel.inputMode == .windows && !sessionModel.sessionControlsOpen)
        sessionModel.remoteInput = true
        sessionModel.capture = true
        sessionModel.setSessionControlsOpen(true)
        precondition(sessionModel.sessionControlsOpen && !sessionModel.remoteInput && !sessionModel.capture)
        precondition(!sessionModel.canCapture && sessionModel.inputMode == .windows)
        sessionModel.resumeWindowsInput()
        precondition(!sessionModel.remoteInput)
        sessionModel.activeResolution = "3024 × 1898"
        sessionModel.presentedFPS = 30
        sessionModel.captureValidated = false
        try render(sessionView, name: "client-session-controls-preview")
        sessionWindow.setContentSize(NSSize(width: 640, height: 400))
        try render(sessionView, name: "client-session-controls-compact-preview")
        sessionWindow.appearance = NSAppearance(named: .darkAqua)
        sessionModel.activePC?.name = "Office Windows PC with a longer connection name"
        try render(sessionView, name: "client-session-controls-dark-preview")
        sessionModel.setSessionControlsOpen(false)
        precondition(!sessionModel.sessionControlsOpen && sessionModel.inputMode == .windows)
        sessionModel.suspendInput(reason: "Space changed")
        precondition(sessionModel.inputMode == .windows && !sessionModel.remoteInput)
        sessionModel.releaseButton()
        precondition(sessionModel.inputMode == .mac)
        sessionModel.setSessionControlsOpen(true)
        sessionModel.setSessionControlsOpen(false)
        precondition(sessionModel.inputMode == .mac && !sessionModel.remoteInput)
        sessionModel.suspendInput(reason: "Dialog closed")
        precondition(sessionModel.inputMode == .mac)
        defaults.set(try JSONEncoder().encode(custom), forKey: "verifiedCaptureShortcut")
        let verified = AppModel(defaults: defaults, secretStore: TestSecrets())
        precondition(verified.releaseVerified && verified.captureValidated)
        verified.updateShortcut(.default)
        precondition(!verified.captureValidated && defaults.data(forKey: "verifiedCaptureShortcut") == nil)
        let updateWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
        let updateView = NSHostingView(rootView: UpdatesView(updater: sessionModel.updater))
        updateWindow.contentView = updateView
        try render(updateView, name: "client-updates-preview")
        let delegate = AppDelegate(model: sessionModel)
        let menu = NSMenu()
        delegate.menuWillOpen(menu)
        precondition(sessionModel.menuOpen && !sessionModel.remoteInput)
        precondition(menu.items.contains { $0.title == "Show Windows" })
        precondition(menu.items.contains { $0.title == "Disconnect" })
        precondition(menu.items.contains { $0.title == "Windows control" && $0.state == .off })
        precondition(menu.items.contains { $0.title == "Quit MacRDP" })
        delegate.menuDidClose(menu)
        precondition(!sessionModel.menuOpen)
        sessionModel.closeSessionWindow = { delegate.closeSession() }
        sessionModel.window = sessionWindow
        sessionModel.showSession = true
        sessionModel.isFullScreen = true
        sessionModel.fullScreenTransition = true
        var installations = 0
        sessionModel.updater.sessionIsActive = { sessionModel.sessionRunning }
        precondition(sessionModel.updater.postponeInstallation { installations += 1 })
        sessionModel.updater.sessionEnded()
        precondition(installations == 0)
        precondition(!delegate.windowShouldClose(sessionWindow))
        precondition(sessionModel.phase == .disconnected)
        precondition(!sessionModel.showSession && sessionModel.window == nil && !sessionWindow.isVisible)
        precondition(!sessionModel.isFullScreen && !sessionModel.fullScreenTransition)
        precondition(installations == 1)
        sessionModel.disconnect()
        sessionModel.updater.sessionEnded()
        precondition(installations == 1)
        var relaunchPrepared = false
        sessionModel.updater.willRelaunch = { relaunchPrepared = true }
        sessionModel.updater.prepareForRelaunch()
        precondition(relaunchPrepared)
        delegate.showSettings()
        precondition(sessionModel.settings)
        sessionModel.settings = false
        print("PASS disconnect and session close dismiss the window, reset fullscreen state, resume a deferred update once, and route Settings to the real view.")
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        sessionModel.phase = .disconnected
        sessionModel.pcs = [pc]
        delegate.menuWillOpen(menu)
        precondition(menu.items.contains { $0.title == "Connect to Office Windows" })
        delegate.menuDidClose(menu)
        sessionModel.updater.sessionIsActive = { true }
        sessionModel.updater.check()
        precondition(sessionModel.updater.message.contains("Disconnect"))
        sessionModel.updater.sessionIsActive = { false }
        let inline = sessionModel.updater
        var cancelled = false
        inline.showDownloadInitiated { cancelled = true }
        inline.showDownloadDidReceiveExpectedContentLength(100)
        inline.showDownloadDidReceiveData(ofLength: 25)
        precondition(inline.busy && inline.progress == 0.25 && inline.canCancel)
        inline.cancel(); precondition(cancelled && !inline.busy)
        var installs = 0
        inline.showReady(toInstallAndRelaunch: { _ in installs += 1 })
        inline.performAction(); inline.performAction()
        precondition(installs == 1)
        var acknowledgements = 0
        inline.showUpdaterError(CocoaError(.fileReadUnknown), acknowledgement: { acknowledgements += 1 })
        precondition(acknowledgements == 1 && !inline.busy && inline.actionTitle == nil)
        sessionModel.openUpdates()
        precondition(sessionModel.settings && sessionModel.settingsSection == .updates && !sessionModel.updates)
        print("PASS inline update progress, cancellation, one-shot installation, error acknowledgement and Settings routing.")
        sessionModel.shutdown(); verified.shutdown()
        print("Native input intent, persisted release verification and active-session update guard passed.")
        print("Native view rendering and release/lock gates passed. No Keychain writes, event tap, permissions, or network connection attempted.")
    } catch { fatalError(error.localizedDescription) }
}

final class TestSecrets: SecretStore, @unchecked Sendable {
    private let mutex = NSLock()
    private var items: [String: Data] = [:]
    var rejectWrites = false
    func read(_ account: String) throws -> Data? { mutex.withLock { items[account] } }
    func write(_ data: Data, account: String) throws {
        try mutex.withLock {
            if rejectWrites { throw SecretError.keychain(-1) }
            items[account] = data
        }
    }
    func delete(_ account: String) throws { mutex.withLock { _ = items.removeValue(forKey: account) } }
}
@MainActor
func verifyPCManagement() async throws {
    let suite = "MacRDP.native-profiles.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = TestSecrets()
    let model = AppModel(defaults: defaults, secretStore: secrets)
    model.start()
    while model.loading { try await Task.sleep(for: .milliseconds(10)) }
    precondition(model.needsPIN && !model.unlocked)
    model.unlock(pin: "4972", confirmation: "4972")
    while model.loading { try await Task.sleep(for: .milliseconds(10)) }
    precondition(model.unlocked)
    let activeWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
    let unrelatedWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
    model.window = activeWindow
    model.rehearse()
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: unrelatedWindow)
    precondition(model.rehearsing)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: activeWindow)
    precondition(!model.rehearsing && !model.remoteInput)
    model.saveSettings(shortcut: model.shortcut, three: model.threeFinger, four: model.fourFinger, exclusive: true, mapping: .macCopyPaste)
    precondition(model.modifierMapping == .macCopyPaste && !model.remoteInput)
    var pc = PCProfile(); pc.host = "fixture.invalid"; pc.username = "fixture"
    let added = await model.savePC(pc, password: "synthetic-fixture-password"); precondition(added)
    let account = "pc-\(pc.id.uuidString)"
    precondition(try! secrets.read(account) == Data("synthetic-fixture-password".utf8))
    pc.name = "Renamed PC"
    let renamed = await model.savePC(pc, password: ""); precondition(renamed && model.pcs.count == 1)
    precondition(try! secrets.read(account) != nil)
    secrets.rejectWrites = true
    let rejected = await model.savePC(pc, password: "replacement"); precondition(!rejected)
    precondition(try! secrets.read(account) == Data("synthetic-fixture-password".utf8))
    secrets.rejectWrites = false
    pc.host = "changed.invalid"
    let changed = await model.savePC(pc, password: ""); precondition(changed)
    precondition(try! secrets.read(account) == nil)
    let saved = await model.savePC(pc, password: "synthetic-fixture-password"); precondition(saved)
    pc.rememberPassword = false
    let forgotten = await model.savePC(pc, password: ""); precondition(forgotten)
    precondition(try! secrets.read(account) == nil)
    pc.rememberPassword = true
    let resaved = await model.savePC(pc, password: "synthetic-fixture-password"); precondition(resaved)
    let reopened = AppModel(defaults: defaults, secretStore: secrets)
    precondition(!reopened.unlocked && reopened.pcs == [pc] && reopened.modifierMapping == .macCopyPaste)
    precondition(try! secrets.read(account) == Data("synthetic-fixture-password".utf8))
    await model.deletePC(pc)
    precondition(model.pcs.isEmpty && (try! secrets.read(account)) == nil)
    model.phase = .connected; model.lockApp()
    while model.loading { try await Task.sleep(for: .milliseconds(10)) }
    precondition(!model.unlocked && model.phase == .connected && !model.remoteInput)
    model.shutdown(); reopened.shutdown()
    print("PASS native PC add/edit/delete, PIN lifecycle, credential preservation, account changes, failed writes and forgetting passwords. Uses isolated memory secrets only.")
}
try await verifyPCManagement()

@MainActor
func verifyKeyboardSetup() async throws {
    let suite = "MacRDP.native-keyboard.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var permission = false
    var requests = 0
    var settingsOpens = 0
    var canOpenSettings = true
    let access = KeyboardAccess(isTrusted: { permission }, request: { requests += 1 }, openSettings: {
        settingsOpens += 1
        return canOpenSettings
    })
    let model = AppModel(defaults: defaults, secretStore: TestSecrets(), keyboardAccess: access)
    model.unlocked = true; model.phase = .connected
    precondition(model.keyboardControlState == .permissionRequired)
    model.refreshKeyboardPermission()
    precondition(requests == 0 && settingsOpens == 0)
    model.settings = true
    model.openKeyboardSetup()
    precondition(!model.settings && !model.keyboardSetup)
    model.settingsDidClose()
    precondition(model.keyboardSetup)
    model.keyboardSetup = false
    model.useWindowsInput()
    precondition(model.keyboardSetup && !model.capture && requests == 0)
    model.openKeyboardPermissionSettings()
    precondition(requests == 1 && settingsOpens == 1 && !model.accessibilityGranted)
    model.testWindowsControl()
    precondition(!model.captureTestRequested && !model.capture)
    canOpenSettings = false
    model.openKeyboardPermissionSettings()
    precondition(model.permissionMessage != nil)
    permission = true
    model.refreshKeyboardPermission()
    precondition(model.accessibilityGranted && model.keyboardControlState == .setupRequired)
    model.testWindowsControl()
    precondition(!model.captureTestRequested)
    model.shortcutVerified = true
    model.testWindowsControl()
    precondition(!model.captureTestRequested)
    model.releaseButton()
    precondition(model.releaseVerified && model.keyboardControlState == .mac)
    model.testWindowsControl()
    precondition(model.captureTestRequested && !model.keyboardSetup && !model.capture)
    model.suspendInput(reason: "Moving to the full-screen Space")
    precondition(model.captureTestRequested && !model.remoteInput)
    permission = false
    model.refreshKeyboardPermission()
    precondition(!model.captureTestRequested && !model.capture)
    permission = true
    model.refreshKeyboardPermission()
    model.testWindowsControl()
    precondition(model.captureTestRequested)
    model.releaseButton()
    precondition(!model.captureTestRequested && !model.capture)
    model.capture = true; model.remoteInput = true
    permission = false
    model.refreshKeyboardPermission()
    precondition(!model.capture && !model.remoteInput && !model.accessibilityGranted && model.captureIssue != nil)
    permission = true
    model.refreshKeyboardPermission()
    model.useWindowsInput()
    precondition(model.captureIssue == nil && model.keyboardSetup)
    model.captureValidated = true; model.capture = true
    precondition(model.keyboardControlState != .active)
    model.suspendInput(reason: "Preview")
    model.captureValidated = false
    model.shortcutVerified = false; model.buttonVerified = false
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
    let view = NSHostingView(rootView: KeyboardSetupView(model: model))
    window.contentView = view
    try render(view, name: "client-keyboard-setup-preview")
    precondition(model.keyboardSetupWindow === window)
    let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
    let shortcutFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    precondition(!model.verifySetupShortcut(key: 5, flags: shortcutFlags, window: otherWindow, isRepeat: false))
    precondition(!model.verifySetupShortcut(key: 5, flags: shortcutFlags, window: nil, isRepeat: false))
    precondition(!model.verifySetupShortcut(key: 5, flags: [], window: window, isRepeat: false))
    precondition(!model.verifySetupShortcut(key: 5, flags: shortcutFlags, window: window, isRepeat: true))
    precondition(!model.shortcutVerified)
    precondition(model.verifySetupShortcut(key: 5, flags: shortcutFlags, window: window, isRepeat: false) && model.shortcutVerified)
    model.keyboardSetup = false
    precondition(!model.verifySetupShortcut(key: 5, flags: shortcutFlags, window: window, isRepeat: false))
    model.keyboardSetup = true
    window.appearance = NSAppearance(named: .darkAqua)
    permission = false; model.refreshKeyboardPermission()
    try render(view, name: "client-keyboard-permission-preview")
    var launches = 0
    var terminated = false
    model.restartApplication = { launches += 1; throw CocoaError(.executableLoad) }
    model.terminateApplication = { terminated = true }
    await model.restartApp()
    precondition(launches == 1 && !terminated && !model.restarting && model.permissionMessage != nil)
    precondition(model.phase == .connected)
    model.restartApplication = { launches += 1 }
    await model.restartApp()
    precondition(launches == 2 && terminated && !model.capture && !model.remoteInput)
    model.shutdown()
    print("PASS keyboard permission denial/grant/revocation, explicit permission requests, setup gates, focus transition, truthful capture status, and restart success/failure. No real permissions or restart attempted.")
}
try await verifyKeyboardSetup()
