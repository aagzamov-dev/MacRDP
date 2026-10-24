import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model: AppModel
    override init() { model = AppModel(); super.init() }
    init(model: AppModel) { self.model = model; super.init() }
    private var mainWindow: NSWindow?
    private var sessionWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        model.restartApplication = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.allowsRunningApplicationSubstitution = false
            let application = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                throw CocoaError(.executableLoad)
            }
        }
        model.terminateApplication = { NSApp.terminate(nil) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacRDP"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
        window.center(); mainWindow = window
        model.showMainWindow = { [weak self] in self?.showMain() }
        model.showSessionWindow = { [weak self] in self?.showSession() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "MacRDP")
        item.button?.toolTip = "MacRDP · connect and switch input"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu; statusItem = item
        model.$unlocked.dropFirst().sink { [weak self] unlocked in
            guard !unlocked else { return }
            DispatchQueue.main.async { self?.sessionWindow?.orderOut(nil); self?.showMain() }
        }.store(in: &subscriptions)
        model.updater.sessionIsActive = { [weak model] in model?.sessionRunning == true }
        model.updater.willShowUI = { [weak model] in model?.suspendInput(reason: "Software update") }
        model.updater.start()
        model.start(); showMain()
    }

    private func showMain() {
        model.suspendInput(reason: "MacRDP workspace")
        mainWindow?.deminiaturize(nil); mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showSession() {
        guard model.unlocked, model.activePC != nil else { showMain(); return }
        if sessionWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.fullScreenPrimary]
            window.acceptsMouseMovedEvents = true
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SessionWindowView(model: model))
            window.center(); sessionWindow = window
        }
        model.window = sessionWindow
        sessionWindow?.title = model.activePC?.name ?? "Windows"
        sessionWindow?.deminiaturize(nil); sessionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionWindow?.makeFirstResponder(model.surface)
        model.surface?.reportGeometry()
        if model.isFullScreen { mainWindow?.orderOut(nil) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === sessionWindow, model.unlocked,
              sessionWindow?.attachedSheet == nil, !model.settings, !model.updates, !model.pinChange else { return }
        sessionWindow?.makeFirstResponder(model.surface)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.suspendInput(reason: "Hidden to menu bar · session stays connected")
        sender.orderOut(nil)
        return false
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === sessionWindow else { return }
        model.fullScreenTransition = true
        model.suspendInput(reason: "Entering full screen")
        mainWindow?.orderOut(nil)
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === sessionWindow else { return }
        model.isFullScreen = true; model.fullScreenTransition = false
        sessionWindow?.makeFirstResponder(model.surface); model.surface?.reportGeometry()
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === sessionWindow else { return }
        model.fullScreenTransition = true; model.suspendInput(reason: "Leaving full screen")
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === sessionWindow else { return }
        model.isFullScreen = false; model.fullScreenTransition = false
        sessionWindow?.makeFirstResponder(model.surface); model.surface?.reportGeometry()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { model.fullScreenTransition = false }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { model.fullScreenTransition = false }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.subtracting([.disableProcessSwitching, .disableForceQuit, .disableSessionTermination])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    func menuWillOpen(_ menu: NSMenu) {
        model.menuOpen = true; model.suspendInput(reason: "Menu bar controls")
        menu.removeAllItems()
        add(model.sessionRunning ? "\(model.activePC?.name ?? "Windows") · \(model.phase.rawValue)" : "MacRDP", to: menu)
        menu.addItem(.separator())
        add(model.unlocked ? "Open MacRDP" : "Unlock MacRDP…", action: #selector(openMain), to: menu)
        if model.unlocked {
            if model.sessionRunning {
                add("Show Windows", action: #selector(openSession), to: menu)
                let toggle = add("Windows control", action: #selector(toggleControl), to: menu)
                toggle.state = model.inputMode == .windows ? .on : .off
                toggle.isEnabled = model.phase == .connected
                add(model.isConnecting ? "Cancel connection" : "Disconnect", action: #selector(disconnect), to: menu)
            } else {
                for pc in model.pcs {
                    let item = add("Connect to \(pc.name)", action: #selector(connectPC(_:)), to: menu)
                    item.representedObject = pc.id.uuidString
                }
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
    func menuDidClose(_ menu: NSMenu) { model.menuOpen = false }
    @discardableResult
    private func add(_ title: String, action: Selector? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = action != nil
        menu.addItem(item); return item
    }
    @objc private func openMain() { showMain() }
    @objc private func openSession() { model.showSession = true }
    @objc private func connectPC(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let pc = model.pcs.first(where: { $0.id.uuidString == id }) else { return }
        model.connect(pc)
    }
    @objc private func toggleControl() { model.toggleInput() }
    @objc private func disconnect() { model.disconnect() }
    @objc private func keyboardSetup() { model.openKeyboardSetup() }
    @objc private func settings() { model.openSettings() }
    @objc private func updates() { model.openUpdates() }
    @objc private func lock() { model.lockApp() }
    @objc private func quit() { NSApp.terminate(nil) }
}
