import AppKit
import SwiftUI

struct SessionSurface: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> RemoteDesktopView {
        let view = RemoteDesktopView()
        view.model = model; model.surface = view
        return view
    }
    func updateNSView(_ view: RemoteDesktopView, context: Context) { view.model = model }
    static func dismantleNSView(_ view: RemoteDesktopView, coordinator: ()) { view.stop() }
}

final class RemoteDesktopView: NSView {
    weak var model: AppModel?
    private var image: CGImage?
    private var timer: Timer?
    private var resizeWork: DispatchWorkItem?
    private var lastLayout: DisplayLayout?
    private var points: [Int: TouchPoint] = [:]
    private let touchIdentities = NSMapTable<AnyObject, NSNumber>(keyOptions: .strongMemory, valueOptions: .strongMemory)
    private var nextTouchID = 0
    private var remoteCursor: RemoteCursor?
    private var nativeCursor = NSCursor.arrow
    private var wheelX: Double = 0
    private var wheelY: Double = 0
    private var mouseButtons: Set<Int> = []
    private var capsLock = false
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    private var geometry: RemoteGeometry {
        RemoteGeometry(bounds: bounds, remote: CGSize(width: image?.width ?? 0, height: image?.height ?? 0))
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]; wantsRestingTouches = false
        setAccessibilityLabel("Windows remote desktop")
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clearDesktop() {
        image = nil; lastLayout = nil; remoteCursor = nil; resetTouches(); needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            model?.transport?.requestFrame()
            remoteCursor = model?.transport?.latestCursor
            let clock = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.presentLatest() }
            }
            timer?.invalidate(); timer = clock
            RunLoop.main.add(clock, forMode: .common)
            reportGeometry()
        } else { stop() }
    }
    func stop() { timer?.invalidate(); timer = nil; resizeWork?.cancel(); model?.release(reason: "Session view changed · connection stays open") }
    override func layout() { super.layout(); scheduleResize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); scheduleResize() }
    private func scheduleResize() {
        resizeWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reportGeometry() }
        resizeWork = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
    func reportGeometry() {
        guard bounds.width > 1, bounds.height > 1, window?.isMiniaturized != true, let pc = model?.activePC else { return }
        let layout = DisplayLayout(points: bounds.size, backing: convertToBacking(bounds).size,
                                   retina: pc.optimizeRetina, scale: pc.desktopScale)
        if lastLayout != layout || model?.phase == .connecting {
            lastLayout = layout; model?.geometry(layout)
        }
        refreshCursor()
    }
    private func presentLatest() {
        guard let frame = model?.transport?.takeFrame() else { return }
        let resized = image?.width != frame.width || image?.height != frame.height
        image = frame
        if resized { model?.activeResolution = "\(frame.width) × \(frame.height)"; refreshCursor() }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = geometry.imageRect
        context.saveGState()
        context.interpolationQuality = rect.size == CGSize(width: image.width, height: image.height) ? .none : .high
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
    override func keyDown(with event: NSEvent) {
        model?.nativeKey(KeyStroke(key: event.keyCode, down: true, repeating: event.isARepeat))
    }
    override func keyUp(with event: NSEvent) { model?.nativeKey(KeyStroke(key: event.keyCode, down: false)) }
    override func flagsChanged(with event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if event.keyCode == 57 {
            let enabled = flags.contains(.maskAlphaShift)
            if enabled != capsLock {
                capsLock = enabled
                model?.nativeKey(KeyStroke(key: 57, down: true)); model?.nativeKey(KeyStroke(key: 57, down: false))
            }
        } else { model?.nativeKey(KeyStroke(key: event.keyCode, down: KeyboardTap.modifierDown(key: event.keyCode, flags: flags))) }
    }
    override func resignFirstResponder() -> Bool {
        model?.release(reason: "Mac input · remote session stays connected")
        return super.resignFirstResponder()
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    private func send(_ event: NSEvent, flags: UInt16, dragging: Bool = false) {
        guard let point = geometry.point(convert(event.locationInWindow, from: nil), clamp: dragging) else { return }
        model?.pointer(flags: flags, x: UInt16(point.x), y: UInt16(point.y))
    }
    override func mouseMoved(with event: NSEvent) { send(event, flags: 0x0800) }
    override func mouseDragged(with event: NSEvent) { send(event, flags: 0x0800, dragging: true) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    private func mouse(_ event: NSEvent, button: UInt16, down: Bool) {
        if down {
            guard geometry.point(convert(event.locationInWindow, from: nil)) != nil else { return }
            window?.makeFirstResponder(self)
            if model?.remoteInput != true { model?.useWindowsInput() }
            mouseButtons.insert(event.buttonNumber)
        } else { mouseButtons.remove(event.buttonNumber) }
        send(event, flags: button | (down ? 0x8000 : 0), dragging: !down)
    }
    override func mouseDown(with event: NSEvent) { mouse(event, button: 0x1000, down: true) }
    override func mouseUp(with event: NSEvent) { mouse(event, button: 0x1000, down: false) }
    override func rightMouseDown(with event: NSEvent) { mouse(event, button: 0x2000, down: true) }
    override func rightMouseUp(with event: NSEvent) { mouse(event, button: 0x2000, down: false) }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { mouse(event, button: 0x4000, down: true) } }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { mouse(event, button: 0x4000, down: false) } }
    override func scrollWheel(with event: NSEvent) {
        let multiplier = event.hasPreciseScrollingDeltas ? 3.0 : 120.0
        wheelY += event.scrollingDeltaY * multiplier; wheelX += event.scrollingDeltaX * multiplier
        for horizontal in [false, true] {
            var delta = horizontal ? wheelX : wheelY
            while abs(delta) >= 1 {
                let step = Int(max(-255, min(255, delta)))
                let flags = UInt16(horizontal ? 0x0400 : 0x0200) | UInt16(bitPattern: Int16(step)) & 0x01ff
                send(event, flags: flags); delta -= Double(step)
            }
            if horizontal { wheelX = delta } else { wheelY = delta }
        }
    }
    func updateCursor(_ cursor: RemoteCursor) { remoteCursor = cursor; refreshCursor() }
    func refreshCursor() {
        guard model?.remoteInput == true, let cursor = remoteCursor else { nativeCursor = .arrow; window?.invalidateCursorRects(for: self); return }
        if cursor.kind == 0 {
            nativeCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
        } else if cursor.kind == 1, cursor.width > 0, cursor.height > 0,
            let provider = CGDataProvider(data: cursor.data as CFData),
            let image = CGImage(width: cursor.width, height: cursor.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: cursor.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            let fit = self.image.map { geometry.imageRect.width / CGFloat($0.width) } ?? 1
            nativeCursor = NSCursor(image: NSImage(cgImage: image, size: NSSize(width: CGFloat(cursor.width) * fit, height: CGFloat(cursor.height) * fit)),
                hotSpot: NSPoint(x: CGFloat(cursor.x) * fit, y: CGFloat(cursor.y) * fit))
        } else { nativeCursor = .arrow }
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() { addCursorRect(geometry.imageRect, cursor: nativeCursor) }
    func resetTouches() { points.removeAll(keepingCapacity: true); touchIdentities.removeAllObjects(); mouseButtons.removeAll(); wheelX = 0; wheelY = 0 }
    override func touchesBegan(with event: NSEvent) { updateTouches(event, ended: false) }
    override func touchesMoved(with event: NSEvent) { updateTouches(event, ended: false) }
    override func touchesEnded(with event: NSEvent) { updateTouches(event, ended: true) }
    override func touchesCancelled(with event: NSEvent) { model?.touches([], ended: true, cancelled: true); resetTouches() }
    private func touchID(_ touch: NSTouch) -> Int {
        let identity = touch.identity as AnyObject
        if let existing = touchIdentities.object(forKey: identity) { return existing.intValue }
        nextTouchID += 1
        touchIdentities.setObject(NSNumber(value: nextTouchID), forKey: identity)
        return nextTouchID
    }
    private func updateTouches(_ event: NSEvent, ended: Bool) {
        let all = event.touches(matching: .any, in: self).filter { !$0.isResting }
        for touch in all { let id = touchID(touch); points[id] = TouchPoint(id: id, x: touch.normalizedPosition.x, y: touch.normalizedPosition.y) }
        model?.touches(Array(points.values), ended: ended)
        for touch in all where touch.phase == .ended || touch.phase == .cancelled { if let id = touchIdentities.object(forKey: touch.identity as AnyObject) { points.removeValue(forKey: id.intValue) }; touchIdentities.removeObject(forKey: touch.identity as AnyObject) }
        if points.isEmpty { model?.touches([], ended: true) }
    }
}
