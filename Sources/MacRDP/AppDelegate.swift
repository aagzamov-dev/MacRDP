import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model: AppModel
    override init() { model = AppModel(); super.init() }
    init(model: AppModel) { self.model = model; super.init() }
    private var mainWindow: NSWindow?
    private var sessionWindows: [ObjectIdentifier: NSWindow] = [:]
    private var focusedSession: AppModel { model.sessions.first { $0.window?.isKeyWindow == true } ?? model.sessions.last { $0.sessionRunning } ?? model }
    private func sessionModel(for window: NSWindow?) -> AppModel? {
        ([model] + model.sessions).first { $0.window === window && window != nil }
    }
    private var statusItem: NSStatusItem?
    private var terminating = false
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        model.restartApplication = { try AppRestart.schedule(bundleURL: Bundle.main.bundleURL) }
        model.terminateApplication = { NSApp.terminate(nil) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacRDP"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
        window.center(); window.setFrameAutosaveName("MacRDP Workspace"); mainWindow = window
        model.showMainWindow = { [weak self] in self?.showMain() }
        configureSession(model)
        model.sessionCreated = { [weak self] session in self?.configureSession(session) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "MacRDP")
        item.button?.toolTip = "MacRDP · connect and switch input"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu; statusItem = item
        model.$unlocked.dropFirst().sink { [weak self] unlocked in
            guard !unlocked else { return }
            DispatchQueue.main.async { self?.sessionWindows.values.forEach { $0.orderOut(nil) }; self?.showMain() }
        }.store(in: &subscriptions)
        model.updater.sessionIsActive = { [weak model] in model?.hasRunningSessions == true }
        model.updater.willShowUI = { [weak model] in model?.suspendAllInput(reason: "Software update") }
        model.updater.willInstall = { [weak model] in model?.dismissLocalDialogs() }
        model.updater.willRelaunch = { [weak self] in
            self?.model.prepareForTermination()
            self?.closeSession(returnToMain: false)
        }
        model.updater.start()
        model.start(); showMain()
    }

    private func showMain() {
        guard !terminating else { return }
        model.suspendAllInput(reason: "MacRDP workspace")
        mainWindow?.deminiaturize(nil); mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func configureSession(_ session: AppModel) {
        session.showMainWindow = { [weak self] in self?.showMain() }
        session.closeSessionWindow = { [weak self, weak session] in
            guard let session else { return }; self?.closeSession(session)
        }
        session.showSessionWindow = { [weak self, weak session] in
            guard let session else { return }; self?.showSession(session)
        }
    }
    private func showSession(_ session: AppModel) {
        guard session.unlocked, session.activePC != nil else { showMain(); return }
        for other in model.sessions where other !== session { other.suspendInput(reason: "Another session selected") }
        let key = ObjectIdentifier(session)
        if sessionWindows[key] == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.fullScreenPrimary]
            window.acceptsMouseMovedEvents = true
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SessionWindowView(model: session))
            window.center(); window.setFrameAutosaveName("MacRDP Session " + (session.activePC?.id.uuidString ?? "default"))
            sessionWindows[key] = window
        }
        let window = sessionWindows[key]
        session.window = window
        window?.title = session.activePC?.name ?? "Windows"
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(session.surface)
        session.surface?.reportGeometry()
        if session.isFullScreen { mainWindow?.orderOut(nil) }
    }
    func closeSession(returnToMain: Bool = true) {
        for session in [model] + model.sessions { closeSession(session, returnToMain: false) }
        if returnToMain { showMain() }
    }
    private func closeSession(_ session: AppModel, returnToMain: Bool = true) {
        let window = sessionWindows.removeValue(forKey: ObjectIdentifier(session)) ?? session.window
        session.window = nil
        session.isFullScreen = false; session.fullScreenTransition = false
        window?.delegate = nil
        if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
        window?.close()
        if returnToMain { showMain() }
    }
    func showSettings() { model.openSettings() }
    func windowDidBecomeKey(_ notification: Notification) {
        guard let session = sessionModel(for: notification.object as? NSWindow), session.unlocked,
              session.window?.attachedSheet == nil, !session.settings, !session.keyboardSetup else { return }
        for other in model.sessions where other !== session { other.suspendInput(reason: "Another session selected") }
        session.window?.makeFirstResponder(session.surface)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if terminating { return true }
        if let session = sessionModel(for: sender) { session.disconnect(); return false }
        model.suspendAllInput(reason: "Hidden to menu bar")
        sender.orderOut(nil)
        return false
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let session = sessionModel(for: notification.object as? NSWindow) else { return }
        session.fullScreenTransition = true; session.suspendInput(reason: "Entering full screen")
        mainWindow?.orderOut(nil)
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let session = sessionModel(for: notification.object as? NSWindow) else { return }
        session.fullScreenTransition = false
        session.isFullScreen = true
        session.window?.makeFirstResponder(session.surface)
        finishFullScreenGeometry(session)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        guard let session = sessionModel(for: notification.object as? NSWindow) else { return }
        session.fullScreenTransition = true; session.suspendInput(reason: "Leaving full screen")
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard let session = sessionModel(for: notification.object as? NSWindow) else { return }
        session.fullScreenTransition = false
        session.isFullScreen = false
        session.window?.makeFirstResponder(session.surface)
        finishFullScreenGeometry(session)
    }
    private func finishFullScreenGeometry(_ session: AppModel) {
        session.fullScreenTransition = false
        session.window?.contentView?.layoutSubtreeIfNeeded()
        session.surface?.reportGeometry(force: true)
        session.resumeWindowsInput()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard let session = sessionModel(for: window) else { return }
        finishFullScreenGeometry(session)
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        guard let session = sessionModel(for: window) else { return }
        finishFullScreenGeometry(session)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        model.prepareForTermination()
        for window in sender.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        closeSession(returnToMain: false)
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    func menuWillOpen(_ menu: NSMenu) {
        for session in [model] + model.sessions { session.menuOpen = true }; model.suspendAllInput(reason: "Menu bar controls")
        menu.removeAllItems()
        add(model.sessionRunning ? "\(model.activePC?.name ?? "Windows") · \(model.phase.rawValue)" : "MacRDP", to: menu)
        menu.addItem(.separator())
        add(model.unlocked ? "Open MacRDP" : "Unlock MacRDP…", action: #selector(openMain), to: menu)
        if model.unlocked {
            for pc in model.pcs {
                let session = model.session(for: pc.id) ?? (model.activePC?.id == pc.id ? model : nil)
                let item = add(session.map { $0.sessionRunning ? "Show \(pc.name) · \($0.phase.rawValue)" : "Connect to \(pc.name)" } ?? "Connect to \(pc.name)", action: #selector(connectPC(_:)), to: menu)
                item.representedObject = pc.id.uuidString
            }
            if model.hasRunningSessions {
                let toggle = add("Windows control · \(focusedSession.activePC?.name ?? "Windows")", action: #selector(toggleControl), to: menu)
                toggle.state = focusedSession.inputMode == .windows ? .on : .off
                toggle.isEnabled = focusedSession.phase == .connected
                add("Disconnect \(focusedSession.activePC?.name ?? "Windows")", action: #selector(disconnect), to: menu)
            }
            menu.addItem(.separator())
            add("Keyboard setup & permissions…", action: #selector(keyboardSetup), to: menu)
            add("Settings…", action: #selector(settings), to: menu)
            add("Lock MacRDP", action: #selector(lock), to: menu)
        }
        add("Updates…", action: #selector(updates), to: menu)
        menu.addItem(.separator())
        add("Quit MacRDP", action: #selector(quit), to: menu)
    }
    func menuDidClose(_ menu: NSMenu) { for session in [model] + model.sessions { session.menuOpen = false } }
    @discardableResult
    private func add(_ title: String, action: Selector? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = action != nil
        menu.addItem(item); return item
    }
    @objc private func openMain() { showMain() }
    @objc private func openSession() { focusedSession.showSession = true }
    @objc private func connectPC(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let pc = model.pcs.first(where: { $0.id.uuidString == id }) else { return }
        model.connect(pc)
    }
    @objc private func toggleControl() { focusedSession.toggleInput() }
    @objc private func disconnect() { focusedSession.disconnect() }
    @objc private func keyboardSetup() { model.openKeyboardSetup() }
    @objc private func settings() { model.openSettings() }
    @objc private func updates() { model.openUpdates() }
    @objc private func lock() { model.lockApp() }
    @objc private func quit() { NSApp.terminate(nil) }
}
