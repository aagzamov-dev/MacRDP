import AppKit
import ApplicationServices
import IOKit.hidsystem

enum CaptureNotice: Sendable {
    case ready
    case released(String, UInt64)
    case action(WindowsAction)
}

final class KeyboardTap: @unchecked Sendable {
    private let mutex = NSLock()
    private var machine = CaptureMachine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var worker: Thread?
    private var watchdog: DispatchSourceTimer?
    private var deadline: TimeInterval = 0
    private var lastHeartbeat: TimeInterval = 0
    private var eligible = false
    private var stopping = false
    private var ready = false
    private var shortcut = KeyboardShortcut.default
    private var inputSink: (@Sendable ([KeyStroke]) -> Bool)?
    private var releaseSink: (@Sendable () -> Void)?
    private let notify: @Sendable (CaptureNotice) -> Void

    init(notify: @escaping @Sendable (CaptureNotice) -> Void) { self.notify = notify }

    var isCapturing: Bool { mutex.withLock { machine.state == .captured } }
    var isReady: Bool { mutex.withLock { ready } }
    var generation: UInt64 { mutex.withLock { machine.generation } }

    func setInputSink(_ sink: (@Sendable ([KeyStroke]) -> Bool)?, release: (@Sendable () -> Void)?) {
        mutex.withLock { inputSink = sink; releaseSink = release }
    }

    func heartbeat(eligible: Bool) {
        let shouldRelease = mutex.withLock {
            self.eligible = eligible
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            return !eligible && machine.state != .local
        }
        if shouldRelease { release(reason: "Session focus changed") }
    }

    func prepare() -> Bool {
        if mutex.withLock({ tap != nil }) { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let driver = Unmanaged<KeyboardTap>.fromOpaque(info).takeUnretainedValue()
                return driver.receive(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        CGEvent.tapEnable(tap: port, enable: false)
        mutex.withLock { tap = port; self.source = source }
        let thread = Thread { [self] in
            guard let source = mutex.withLock({ self.source }) else { return }
            let current = CFRunLoopGetCurrent()!
            let shouldRun = mutex.withLock { () -> Bool in
                if stopping { return false }
                loop = current
                return true
            }
            if shouldRun {
                CFRunLoopAddSource(current, source, .commonModes)
                CFRunLoopPerformBlock(current, CFRunLoopMode.commonModes.rawValue) { [self] in
                    mutex.withLock { ready = true }
                    notify(.ready)
                }
                CFRunLoopRun()
                CFRunLoopRemoveSource(current, source, .commonModes)
            }
            mutex.withLock { loop = nil; ready = false }
        }
        thread.name = "MacRDP keyboard release"
        thread.qualityOfService = .userInteractive
        worker = thread
        thread.start()
        return true
    }

    func start(eligible isEligible: Bool, releaseVerified: Bool, modifiersHeld: Bool,
               shortcut: KeyboardShortcut = .default, validated: Bool = false) -> String? {
        let failure = mutex.withLock { () -> String? in
            guard tap != nil, ready, !stopping else { return "The keyboard tap is not ready. Restart MacRDP and try again." }
            guard isEligible else { return "Click the remote desktop, lift all modifiers, and try Windows input again." }
            eligible = isEligible
            guard shortcut.validationError == nil else { return "Choose a valid keyboard toggle shortcut in Settings." }
            self.shortcut = shortcut
            if releaseVerified { machine.verifyRelease() }
            guard machine.arm(eligible: eligible, modifiersHeld: modifiersHeld),
                  machine.activate(generation: machine.generation, eligible: eligible) else {
                return "Release checks or capture state changed. Rehearse the shortcut and try again."
            }
            deadline = validated ? .infinity : ProcessInfo.processInfo.systemUptime + 10
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            return nil
        }
        if let failure { return failure }
        guard let port = mutex.withLock({ tap }) else { return "The keyboard tap is unavailable." }
        CGEvent.tapEnable(tap: port, enable: true)
        guard isCapturing else {
            CGEvent.tapEnable(tap: port, enable: false)
            return "macOS disabled the input tap during startup. Your keyboard remains local."
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        watchdog = timer
        timer.resume()
        return nil
    }

    func release(reason: String, notify shouldNotify: Bool = true) {
        let (changed, port, generation) = mutex.withLock { () -> (Bool, CFMachPort?, UInt64) in
            let wasActive = machine.state != .local
            _ = machine.release()
            eligible = false
            return (wasActive, tap, machine.generation)
        }
        if changed, let port { CGEvent.tapEnable(tap: port, enable: false) }
        if changed { mutex.withLock { releaseSink }?() }
        if changed && shouldNotify { notify(.released(reason, generation)) }
    }

    func cancelTimer() { watchdog?.cancel(); watchdog = nil }

    func shutdown() {
        release(reason: "Application closed")
        cancelTimer()
        let (port, runLoop) = mutex.withLock { () -> (CFMachPort?, CFRunLoop?) in
            stopping = true
            return (tap, loop)
        }
        if let port { CFMachPortInvalidate(port) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func checkHealth() {
        let (reason, port) = mutex.withLock { () -> (String?, CFMachPort?) in
            guard machine.state == .captured else { return (nil, nil) }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= deadline { return ("10-second safety release", tap) }
            if now - lastHeartbeat > 0.75 { return ("Interface stopped responding", tap) }
            return (nil, tap)
        }
        if let reason { release(reason: reason) }
        else if let port, !CGEvent.tapIsEnabled(tap: port) { release(reason: "Input permission or event tap changed") }
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            release(reason: type == .tapDisabledByTimeout ? "Keyboard tap timed out; input released" : "macOS disabled the keyboard tap; input released")
            return Unmanaged.passUnretained(event)
        }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let binding = mutex.withLock { shortcut }
        let escape = binding.matches(keyCode: key, flags: flags)
        let forceQuit = key == 53 && flags.contains([.maskAlternate, .maskCommand])
        let down = type == .flagsChanged
            ? Self.modifierDown(key: key, flags: flags) : type == .keyDown
        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let (result, generation): (InputResult, UInt64) = mutex.withLock {
            guard eligible, ProcessInfo.processInfo.systemUptime < deadline,
                  ProcessInfo.processInfo.systemUptime - lastHeartbeat < 0.75 else {
                let active = machine.state == .captured
                _ = machine.release()
                return (InputResult(released: active), machine.generation)
            }
            let result = machine.handle(KeyStroke(key: key, down: down, repeating: repeating),
                                        generation: machine.generation, escape: escape && down, forceQuit: forceQuit && down,
                                        toggle: type == .flagsChanged && key == 57)
            return (result, machine.generation)
        }
        if result.released {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            mutex.withLock { releaseSink }?()
            notify(.released(forceQuit ? "Force Quit preserved" : escape ? "Shortcut released to Mac" : "Safety release", generation))
        } else if result.consume && down && !repeating {
            if let action = Self.action(key: key, flags: flags) { notify(.action(action)) }
        }
        if result.consume && !result.released && !result.keys.isEmpty {
            if let sink = mutex.withLock({ inputSink }), !sink(result.keys) {
                release(reason: "Remote input queue unavailable; Mac input restored")
            }
        }
        return result.consume ? nil : Unmanaged.passUnretained(event)
    }

    static func action(key: UInt16, flags: CGEventFlags) -> WindowsAction? {
        if key == 48 {
            if flags.contains(.maskCommand) { return .taskView }
            if flags.contains(.maskAlternate) { return .appSwitcher }
            if flags.contains(.maskControl) { return flags.contains(.maskShift) ? .previousTab : .nextTab }
        }
        if flags.contains([.maskCommand, .maskControl]) {
            if key == 123 { return .desktopLeft }
            if key == 124 { return .desktopRight }
        }
        return nil
    }

    static func modifierDown(key: UInt16, flags: CGEventFlags) -> Bool {
        let mask: UInt64
        switch key {
        case 54: mask = UInt64(NX_DEVICERCMDKEYMASK)
        case 55: mask = UInt64(NX_DEVICELCMDKEYMASK)
        case 56: mask = UInt64(NX_DEVICELSHIFTKEYMASK)
        case 60: mask = UInt64(NX_DEVICERSHIFTKEYMASK)
        case 58: mask = UInt64(NX_DEVICELALTKEYMASK)
        case 61: mask = UInt64(NX_DEVICERALTKEYMASK)
        case 59: mask = UInt64(NX_DEVICELCTLKEYMASK)
        case 62: mask = UInt64(NX_DEVICERCTLKEYMASK)
        case 57: return flags.contains(.maskAlphaShift)
        default: return false
        }
        return flags.rawValue & mask != 0
    }
}
