import Foundation
import CoreGraphics
import Metal

enum SessionPhase: String, Sendable {
    case reconnecting = "Reconnecting…", disconnected = "Disconnected", connecting = "Connecting…", authenticating = "Signing in…", connected = "Connected", failed = "Connection failed"
}

struct CertificateRequest: Identifiable, Sendable {
    let id = UUID()
    let host: String
    let subject: String
    let issuer: String
    let fingerprint: String
    let changed: Bool
}

struct RemoteCursor: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let x: Int
    let y: Int
    let kind: Int
}

enum TransportEvent: Sendable {
    case frameAvailable
    case state(SessionPhase, UInt32)
    case certificate(CertificateRequest)
    case cursor(RemoteCursor)
    case displayControl(Bool)
    case clipboard(String, UInt64)
}

final class DisplayBuffer: @unchecked Sendable {
    let bytes: UnsafeMutableRawPointer
    let capacity: Int
    let metal: (any MTLBuffer)?
    private let mutex = NSLock()
    private var used = false
    init(capacity: Int, device: (any MTLDevice)?) {
        self.capacity = capacity
        metal = device?.makeBuffer(length: capacity, options: .storageModeShared)
        bytes = metal?.contents() ?? .allocate(byteCount: capacity, alignment: 256)
    }
    deinit { if metal == nil { bytes.deallocate() } }
    func lease() -> Bool { mutex.withLock { if used { return false }; used = true; return true } }
    func release() { mutex.withLock { used = false } }
    var available: Bool { mutex.withLock { !used } }
}

final class DesktopFrame: @unchecked Sendable {
    let storage: DisplayBuffer
    let info: MRFrameInfo
    init(storage: DisplayBuffer, info: MRFrameInfo) { self.storage = storage; self.info = info }
    deinit { storage.release() }
    var isComplete: Bool { info.x == 0 && info.y == 0 && info.dirty_width == info.width && info.dirty_height == info.height }
    var size: CGSize { CGSize(width: Int(info.width), height: Int(info.height)) }
    func image() -> CGImage? {
        let retained = Unmanaged.passRetained(self).toOpaque()
        guard let provider = CGDataProvider(dataInfo: retained, data: storage.bytes,
            size: Int(info.stride * info.height), releaseData: { info, _, _ in
                if let info { Unmanaged<DesktopFrame>.fromOpaque(info).release() }
            }) else { Unmanaged<DesktopFrame>.fromOpaque(retained).release(); return nil }
        return CGImage(width: Int(info.width), height: Int(info.height), bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Int(info.stride), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

final class RDPTransport: @unchecked Sendable {
    private let mutex = NSLock()
    private let worker = DispatchQueue(label: "MacRDP FreeRDP session", qos: .userInitiated)
    private var handle: OpaquePointer?
    private var cancelled = false
    private var clipboardSharing = true
    private var clipboardGeneration: UInt64 = 1
    private var modifierTranslator = ModifierTranslator()
    private var dirty = false
    private var fullFrame = true
    private var incremental = false
    private var visible = false
    private var wakePending = false
    let device = MTLCreateSystemDefaultDevice()
    private var cursor: RemoteCursor?
    private var buffers: [DisplayBuffer] = []
    private let frameWorker = DispatchQueue(label: "MacRDP frame preparation", qos: .userInitiated)
    private var preparingFrame = false
    private var preparedFrame: DesktopFrame?
    private let notify: @Sendable (TransportEvent) -> Void

    init(notify: @escaping @Sendable (TransportEvent) -> Void) { self.notify = notify }
    deinit { if let handle { mr_session_free(handle) } }

    func start(profile: PCProfile, password: String, layout: DisplayLayout, fingerprint: String) {
        worker.async { [self] in
            var username = profile.username
            var domain = profile.domain
            if domain.isEmpty, let split = username.firstIndex(of: "\\") {
                domain = String(username[..<split]); username = String(username[username.index(after: split)...])
            }
            let callbacks = MRCallbacks(state: { user, phase, code in
                guard let user else { return }
                let owner = Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue()
                let value: SessionPhase = phase == 1 ? .connecting : phase == 2 ? .connected : phase == 3 ? .failed : phase == 4 ? .authenticating : .disconnected
                owner.notify(.state(value, code))
            }, frame: { user in
                guard let user else { return }
                let owner = Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue()
                owner.frameChanged()
            }, certificate: { user, host, subject, issuer, fingerprint, changed in
                guard let user else { return }
                let owner = Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue()
                owner.notify(.certificate(CertificateRequest(host: host.map(String.init(cString:)) ?? "",
                    subject: subject.map(String.init(cString:)) ?? "", issuer: issuer.map(String.init(cString:)) ?? "",
                    fingerprint: fingerprint.map(String.init(cString:)) ?? "", changed: changed)))
            }, cursor: { user, bytes, width, height, x, y, kind in
                guard let user else { return }
                let owner = Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue()
                let data = bytes.map { Data(bytes: $0, count: Int(width * height * 4)) } ?? Data()
                let cursor = RemoteCursor(data: data, width: Int(width), height: Int(height), x: Int(x), y: Int(y), kind: Int(kind))
                owner.mutex.withLock { owner.cursor = cursor }
                owner.notify(.cursor(cursor))
            }, display: { user, supported in
                guard let user else { return }
                Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue().notify(.displayControl(supported))
            }, clipboard: { user, bytes, length, generation in
                guard let user, let bytes,
                      let text = WindowsClipboardText.decode(Data(bytes: bytes, count: length)) else { return }
                Unmanaged<RDPTransport>.fromOpaque(user).takeUnretainedValue().notify(.clipboard(text, generation))
            })
            let port = profile.host.withCString { host in username.withCString { username in domain.withCString { domain in
                password.withCString { password in fingerprint.withCString { fingerprint in
                    var config = MRConfiguration(host: host, username: username, domain: domain, password: password,
                        fingerprint: fingerprint, port: UInt16(profile.port) ?? 3389,
                        width: UInt32(layout.width), height: UInt32(layout.height), desktop_scale: UInt32(layout.desktopScale), audio: profile.audioPlayback)
                    return mr_session_new(&config, callbacks, Unmanaged.passUnretained(self).toOpaque())
                }}
            }}}
            guard let port else { notify(.state(.failed, 0)); return }
            let shouldCancel = mutex.withLock {
                handle = port
                mr_clipboard_enable(port, clipboardSharing, clipboardGeneration)
                return cancelled
            }
            if shouldCancel { mr_session_cancel(port); notify(.state(.disconnected, 0)); return }
            mr_session_run(port)
        }
    }

    func cancel() {
        mutex.withLock {
            cancelled = true
            if let handle { mr_session_cancel(handle) }
        }
    }

    func setModifierMapping(_ mapping: ModifierMapping) {
        mutex.withLock {
            if let handle { mr_input_enable(handle, false) }
            modifierTranslator = ModifierTranslator(mapping: mapping)
        }
    }
    func setClipboardSharing(_ enabled: Bool, generation: UInt64) {
        mutex.withLock {
            clipboardSharing = enabled; clipboardGeneration = generation
            if let handle { mr_clipboard_enable(handle, enabled, generation) }
        }
    }
    func input(enabled: Bool, capsLock: Bool = false) {
        mutex.withLock {
            if !enabled { modifierTranslator.reset() }
            if let handle {
                mr_input_enable(handle, enabled)
                if enabled { mr_synchronize(handle, capsLock ? 4 : 0) }
            }
        }
    }
    func keys(_ keys: [KeyStroke], remapModifiers: Bool = true) -> Bool {
        mutex.withLock {
            guard let handle else { return false }
            for physical in keys {
                guard let key = remapModifiers ? modifierTranslator.translate(physical) : physical else { continue }
                guard let code = MacScanCode.code(key.key) else { continue }
                if !mr_key(handle, code, key.down, key.repeating) { return false }
            }
            return true
        }
    }
    func pointer(flags: UInt16, x: UInt16, y: UInt16) {
        mutex.withLock { if let handle { _ = mr_pointer(handle, flags, x, y) } }
    }
    func resize(_ layout: DisplayLayout) {
        mutex.withLock { if let handle { mr_resize(handle, UInt32(layout.width), UInt32(layout.height), UInt32(layout.desktopScale)) } }
    }
    func certificate(accept: Bool) { mutex.withLock { if let handle { mr_certificate_reply(handle, accept) } } }
    func requestFrame() { mutex.withLock { fullFrame = true }; frameChanged() }
    func setPresentation(visible: Bool, incremental: Bool) {
        mutex.withLock {
            if self.incremental != incremental { fullFrame = true; dirty = true }
            self.incremental = incremental; self.visible = visible
            if !visible { wakePending = false }
        }
        announceFrame(); prepareNextFrame()
    }
    private func frameChanged() {
        mutex.withLock { dirty = true }
        prepareNextFrame()
    }
    private func announceFrame() {
        let wake = mutex.withLock {
            guard visible && preparedFrame != nil && !wakePending && !cancelled else { return false }
            wakePending = true; return true
        }
        if wake { notify(.frameAvailable) }
    }
    var hasPendingPresentation: Bool { mutex.withLock { preparedFrame != nil || preparingFrame } }
    func prepareNextFrame() {
        let full: Bool? = mutex.withLock {
            guard visible && dirty && preparedFrame == nil && !preparingFrame && handle != nil && !cancelled else { return nil }
            dirty = false; preparingFrame = true
            let full = fullFrame || !incremental; fullFrame = false
            return full
        }
        guard let full else { return }
        frameWorker.async { [self] in
            let (frame, retry) = makeFrame(full: full)
            mutex.withLock { preparedFrame = frame; preparingFrame = false }
            announceFrame()
            if retry { prepareNextFrame() }
        }
    }
    func text(_ text: String) -> Bool {
        let units = Array(text.utf16)
        return mutex.withLock { guard let handle else { return false }; return units.withUnsafeBufferPointer { mr_text(handle, $0.baseAddress, $0.count) } }
    }
    func paste(_ text: String) -> Bool {
        guard let bytes = (text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") + "\0").data(using: .utf16LittleEndian) else { return false }
        return mutex.withLock { guard let handle else { return false }; return bytes.withUnsafeBytes { mr_paste(handle, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) } }
    }
    func statistics() -> MRStatistics {
        mutex.withLock { var stats = MRStatistics(); if let handle { mr_statistics(handle, &stats) }; return stats }
    }
    var latestCursor: RemoteCursor? { mutex.withLock { cursor } }

    @MainActor
    func takeFrame() -> DesktopFrame? {
        let frame = mutex.withLock {
            let frame = preparedFrame; preparedFrame = nil; wakePending = false
            return frame
        }
        prepareNextFrame()
        return frame
    }

    private func makeFrame(full: Bool) -> (DesktopFrame?, Bool) {
        guard let port = mutex.withLock({ handle }) else { return (nil, false) }
        var info = MRFrameInfo()
        let count = mr_copy_frame_update(port, nil, 0, full, &info)
        guard count > 0, count <= 512 * 1024 * 1024 else { return (nil, false) }
        var storage = buffers.first { $0.capacity >= count && $0.capacity <= count * 2 && $0.available }
        if storage == nil {
            buffers.removeAll { $0.available }
            guard buffers.count < 3 else { mutex.withLock { dirty = true; fullFrame = fullFrame || full }; return (nil, false) }
            let buffer = DisplayBuffer(capacity: count, device: device)
            buffers.append(buffer); storage = buffer
        }
        guard let storage, storage.lease() else { return (nil, false) }
        let actual = mr_copy_frame_update(port, storage.bytes.assumingMemoryBound(to: UInt8.self), storage.capacity, full, &info)
        guard actual > 0, actual <= storage.capacity else {
            storage.release()
            if actual > storage.capacity {
                mutex.withLock { dirty = true; fullFrame = true }
                return (nil, true)
            }
            return (nil, false)
        }
        return (DesktopFrame(storage: storage, info: info), false)
    }
}
