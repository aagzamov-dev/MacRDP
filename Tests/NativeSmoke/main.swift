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
        let editorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740), styleMask: [.titled], backing: .buffered, defer: false)
        let editorView = NSHostingView(rootView: PCEditor(model: model, pc: pc, connecting: false))
        editorWindow.contentView = editorView
        try render(editorView, name: "client-pc-editor-preview")
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
    precondition(!reopened.unlocked && reopened.pcs == [pc])
    await model.deletePC(pc)
    precondition(model.pcs.isEmpty && (try! secrets.read(account)) == nil)
    model.phase = .connected; model.lockApp()
    while model.loading { try await Task.sleep(for: .milliseconds(10)) }
    precondition(!model.unlocked && model.phase == .connected && !model.remoteInput)
    model.shutdown(); reopened.shutdown()
    print("PASS native PC add/edit/delete, PIN lifecycle, credential preservation, account changes, failed writes and forgetting passwords. Uses isolated memory secrets only.")
}
try await verifyPCManagement()
