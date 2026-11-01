import Foundation
import AppKit

await MainActor.run {
    let suite = "uz.macrdp.clipboard-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "keepAwake")
    let access = KeyboardAccess(isTrusted: { false }, request: {}, openSettings: { false })
    let model = AppModel(defaults: defaults, keyboardAccess: access)
    var writes: [String] = []
    model.writeClipboard = { writes.append($0) }
    precondition(model.clipboardSharing)
    model.receiveClipboard("locked", generation: 1)
    model.unlocked = true
    model.receiveClipboard("disconnected", generation: 1)
    precondition(writes.isEmpty)
    model.phase = .connected
    model.receiveClipboard("Windows text", generation: 1)
    precondition(writes == ["Windows text"])
    model.saveSettings(shortcut: model.shortcut, three: model.threeFinger, four: model.fourFinger,
                       exclusive: false, clipboardSharing: false, dismiss: false)
    precondition(!model.clipboardSharing && defaults.object(forKey: "clipboardSharing") as? Bool == false)
    model.receiveClipboard("late response", generation: 1)
    precondition(writes.count == 1)
    let restored = AppModel(defaults: defaults, keyboardAccess: access)
    precondition(!restored.clipboardSharing)
    model.saveSettings(shortcut: model.shortcut, three: model.threeFinger, four: model.fourFinger,
                       exclusive: false, clipboardSharing: true, dismiss: false)
    model.receiveClipboard("stale after re-enable", generation: 1)
    precondition(writes.count == 1)
    model.receiveClipboard("fresh after re-enable", generation: 3)
    precondition(writes == ["Windows text", "fresh after re-enable"])
    precondition(AppModel(defaults: defaults, keyboardAccess: access).clipboardSharing)
    model.unlocked = false
    model.receiveClipboard("locked again", generation: 3)
    precondition(writes.count == 2)
    var pc = PCProfile(); pc.host = "test.invalid"; pc.clipboardSharing = false
    pc.modifierMapping = .macCopyPaste; pc.textInputMode = .text
    try! PCStore(defaults: defaults).save([pc])
    let session = AppModel(defaults: defaults, keyboardAccess: access)
    session.unlocked = true; session.activePC = pc
    session.writeClipboard = { writes.append($0) }
    session.phase = .connected
    precondition(session.effectiveModifierMapping == .macCopyPaste && !session.effectiveClipboardSharing)
    precondition(session.usesTextInput && !session.wantsExclusiveCapture)
    session.receiveClipboard("blocked by host policy", generation: 1)
    precondition(writes.count == 2)
    session.setDisplay(resolution: .qhd, mode: .actual)
    let stored = try! PCStore(defaults: defaults).load()[0]
    precondition(stored.resolution == .qhd && stored.viewMode == .actual)
    precondition(stored.modifierMapping == .macCopyPaste && stored.clipboardSharing == false)
    session.toggleFavorite(stored)
    precondition(session.pcs[0].favorite)
    session.duplicatePC(session.pcs[0])
    precondition(session.editor?.id != stored.id && session.editor?.rememberPassword == false)
    precondition(session.editor?.resolution == .qhd)
    session.editor = nil
    var closes = 0
    session.closeSessionWindow = { closes += 1 }
    session.showSession = true
    session.handle(.state(.connected, 0))
    session.handle(.state(.failed, 0x2000d))
    precondition(session.phase == .reconnecting && closes == 0 && session.showSession)
    precondition(session.connectionError != nil && session.reconnectMessage != nil)
    session.cancelReconnect()
    precondition(session.phase == .failed && session.reconnectMessage == nil)
    session.handle(.state(.failed, 0x20009))
    precondition(session.phase == .failed && session.reconnectMessage == nil && closes == 0)
    session.disconnect()
    precondition(closes == 1 && !session.showSession && session.phase == .disconnected)
    precondition(session.sleepActivity == nil)
    print("PASS host overrides, display persistence, duplicate isolation, failure visibility, retry cancellation and explicit disconnect; no app/window/network started")
    print("PASS clipboard default, saved toggle, locked/disconnected gating and stale delivery; injected writer only")
}

final class AuthenticationMemoryStore: SecretStore, @unchecked Sendable {
    private let mutex = NSLock()
    private var items: [String: Data] = [:]
    func read(_ account: String) throws -> Data? { mutex.withLock { items[account] } }
    func write(_ data: Data, account: String) throws { mutex.withLock { items[account] = data } }
    func delete(_ account: String) throws { _ = mutex.withLock { items.removeValue(forKey: account) } }
}

@MainActor
final class FakeMacAuthentication: MacAuthenticating {
    var reject = false
    var onAuthenticate: (() -> Void)?
    func authenticate(reason: String) async throws {
        onAuthenticate?()
        if reject { throw CancellationError() }
    }
    func cancel() {}
}

@MainActor
func testMacAuthentication() async throws {
    let suite = "uz.macrdp.authentication-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "keepAwake")
    let store = AuthenticationMemoryStore()
    let seed = try AppVault(store: store)
    try seed.setup(pin: "1234")
    let id = UUID()
    try seed.savePassword("fixture-password", profile: id)
    let auth = FakeMacAuthentication()
    let model = AppModel(defaults: defaults, secretStore: store,
        keyboardAccess: KeyboardAccess(isTrusted: { false }, request: {}, openSettings: { false }),
        macAuthentication: auth)
    model.loading = false
    auth.reject = true
    await model.unlockWithMac()
    precondition(!model.unlocked)
    await model.resetPINWithMac(replacement: "5678", confirmation: "5678")
    let unchanged = try AppVault(store: store)
    try unchanged.unlock(pin: "1234")
    auth.reject = false
    await model.resetPINWithMac(replacement: "5678", confirmation: "5678")
    precondition(model.unlocked)
    let recovered = try AppVault(store: store)
    try recovered.unlock(pin: "5678")
    let password = try recovered.password(profile: id)
    precondition(password == "fixture-password")
    model.unlocked = false
    await model.unlockWithMac()
    precondition(model.unlocked)
    model.unlocked = false
    auth.onAuthenticate = { model.lockApp() }
    await model.unlockWithMac()
    precondition(!model.unlocked)
    model.shutdown()
    print("Mac authentication success, cancellation, PIN reset and late completion checks passed")
}
try await testMacAuthentication()

await MainActor.run {
    let baseline: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
    var options = baseline
    var writes = 0
    let presentation = SessionPresentation(read: { options }, write: { options = $0; writes += 1 })
    let suite = "uz.macrdp.capture-presentation-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "keepAwake")
    defaults.set(true, forKey: "hideDockWhileControlling")
    let access = KeyboardAccess(isTrusted: { false }, request: {}, openSettings: { false })
    let model = AppModel(defaults: defaults, keyboardAccess: access, sessionPresentation: presentation)
    model.saveSettings(shortcut: model.shortcut, three: model.threeFinger, four: model.fourFinger,
                       exclusive: false, dismiss: false)
    model.releaseButton()
    precondition(writes == 0 && options == baseline)
    for reason in ["App switched", "Session released"] {
        presentation.beginCapture()
        precondition(options.contains(.disableProcessSwitching) && options.contains(.autoHideDock))
        precondition(!options.contains(.hideDock) && !options.contains(.disableForceQuit))
        let before = writes
        presentation.beginCapture()
        precondition(writes == before)
        model.suspendInput(reason: reason)
        precondition(options == baseline)
    }
    presentation.beginCapture()
    model.shutdown()
    precondition(options == baseline)
    let before = writes
    presentation.restore()
    precondition(writes == before)
    print("PASS obsolete Dock setting ignored; exclusive capture restores presentation on release/focus loss/shutdown")
}

@MainActor
final class FakeVPNStatus: VPNConnecting {
    var status = VPNStatus.disconnected
}

@MainActor
func testVPNWaitOnly() async throws {
    let status = FakeVPNStatus()
    var polls = 0
    let waiter = SessionVPN(makeConnection: { _ in status }, pause: {
        polls += 1
        if polls == 150 { status.status = .connected }
    })
    try await waiter.waitUntilConnected(id: "fixture")
    precondition(polls == 150)
    precondition(status.status == .connected)
    waiter.cancelWait()
    precondition(status.status == .connected)
    try await waiter.waitUntilConnected(id: "fixture")
    precondition(polls == 150)
    let cancelled = SessionVPN(makeConnection: { _ in FakeVPNStatus() }, pause: { throw CancellationError() })
    do { try await cancelled.waitUntilConnected(id: "fixture"); preconditionFailure() } catch is CancellationError {}
    let missing = SessionVPN(makeConnection: { _ in nil }, pause: {})
    do { try await missing.waitUntilConnected(id: "fixture"); preconditionFailure() } catch VPNError.unavailable {}
    try await missing.waitUntilConnected(id: nil)
    print("PASS passive VPN wait exceeds old timeout, resumes when connected, cancels without touching VPN, and handles missing/disabled selection")
}
try await testVPNWaitOnly()

@MainActor
func testModelWaitsForManualVPN() async throws {
    let suite = "uz.macrdp.passive-vpn-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "keepAwake")
    let vpn = FakeVPNStatus()
    let waiter = SessionVPN(makeConnection: { _ in vpn }, pause: { await Task.yield() })
    let model = AppModel(defaults: defaults, secretStore: AuthenticationMemoryStore(),
        keyboardAccess: KeyboardAccess(isTrusted: { false }, request: {}, openSettings: { false }),
        macAuthentication: FakeMacAuthentication(), sessionVPN: waiter)
    model.loading = false
    await model.unlockWithMac()
    var pc = PCProfile(); pc.host = "test.invalid"; pc.username = "fixture"
    pc.useVPN = true; pc.vpnServiceID = "fixture"
    let accepted = await model.submitCredentials(pc, password: "fixture-password")
    precondition(accepted)
    for _ in 0..<10 { await Task.yield() }
    precondition(model.vpnStatus == "Waiting for VPN connection" && model.transport == nil)
    model.disconnect()
    vpn.status = .connected
    for _ in 0..<10 { await Task.yield() }
    precondition(model.phase == .disconnected && model.transport == nil && vpn.status == .connected)
    model.shutdown()
    print("PASS waiting message and cancellation block late RDP creation without altering manually connected VPN")
}
try await testModelWaitsForManualVPN()


