import Foundation
import CoreGraphics

enum SessionPhase: String, Sendable {
    case disconnected = "Disconnected", connecting = "Connecting…", authenticating = "Signing in…", connected = "Connected", failed = "Connection failed"
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
    case state(SessionPhase, UInt32)
    case certificate(CertificateRequest)
    case cursor(RemoteCursor)
    case displayControl(Bool)
}

private final class DisplayBuffer: @unchecked Sendable {
    let bytes: UnsafeMutableRawPointer
    let capacity: Int
    private let mutex = NSLock()
    private var used = false
    init(capacity: Int) {
        self.capacity = capacity
        bytes = .allocate(byteCount: capacity, alignment: 64)
    }
    deinit { bytes.deallocate() }
    func lease() -> Bool { mutex.withLock { if used { return false }; used = true; return true } }
    func release() { mutex.withLock { used = false } }
    var available: Bool { mutex.withLock { !used } }
}

final class RDPTransport: @unchecked Sendable {
    private let mutex = NSLock()
    private let worker = DispatchQueue(label: "MacRDP FreeRDP session", qos: .userInitiated)
    private var handle: OpaquePointer?
    private var cancelled = false
    private var dirty = false
    private var cursor: RemoteCursor?
    private var buffers: [DisplayBuffer] = []
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
                owner.mutex.withLock { owner.dirty = true }
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
            })
            let port = profile.host.withCString { host in username.withCString { username in domain.withCString { domain in
                password.withCString { password in fingerprint.withCString { fingerprint in
                    var config = MRConfiguration(host: host, username: username, domain: domain, password: password,
                        fingerprint: fingerprint, port: UInt16(profile.port) ?? 3389,
                        width: UInt32(layout.width), height: UInt32(layout.height), desktop_scale: UInt32(layout.desktopScale))
                    return mr_session_new(&config, callbacks, Unmanaged.passUnretained(self).toOpaque())
                }}
            }}}
            guard let port else { notify(.state(.failed, 0)); return }
            let shouldCancel = mutex.withLock { handle = port; return cancelled }
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

    func input(enabled: Bool, capsLock: Bool = false) {
        mutex.withLock {
            if let handle {
                mr_input_enable(handle, enabled)
                if enabled { mr_synchronize(handle, capsLock ? 4 : 0) }
            }
        }
    }
    func keys(_ keys: [KeyStroke]) -> Bool {
        mutex.withLock {
            guard let handle else { return false }
            for key in keys {
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
    func requestFrame() { mutex.withLock { dirty = true } }
    var latestCursor: RemoteCursor? { mutex.withLock { cursor } }

    @MainActor
    func takeFrame() -> CGImage? {
        let port: OpaquePointer? = mutex.withLock {
            guard dirty, let handle else { return nil }
            dirty = false
            return handle
        }
        guard let port else { return nil }
        var width: UInt32 = 0, height: UInt32 = 0, stride: UInt32 = 0
        let count = mr_copy_frame(port, nil, 0, &width, &height, &stride)
        guard count > 0, count <= 512 * 1024 * 1024 else { return nil }
        var storage = buffers.first { $0.capacity >= count && $0.available }
        if storage == nil {
            if let index = buffers.firstIndex(where: \.available) { buffers.remove(at: index) }
            guard buffers.count < 3 else { mutex.withLock { dirty = true }; return nil }
            let buffer = DisplayBuffer(capacity: count)
            buffers.append(buffer); storage = buffer
        }
        guard let storage, storage.lease() else { return nil }
        let actual = mr_copy_frame(port, storage.bytes.assumingMemoryBound(to: UInt8.self), storage.capacity, &width, &height, &stride)
        guard actual > 0, actual <= storage.capacity else { storage.release(); mutex.withLock { dirty = true }; return nil }
        let info = Unmanaged.passRetained(storage).toOpaque()
        guard let provider = CGDataProvider(dataInfo: info, data: storage.bytes, size: actual, releaseData: { info, _, _ in
            if let info { Unmanaged<DisplayBuffer>.fromOpaque(info).takeRetainedValue().release() }
        }) else { Unmanaged<DisplayBuffer>.fromOpaque(info).takeRetainedValue().release(); return nil }
        return CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Int(stride), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
