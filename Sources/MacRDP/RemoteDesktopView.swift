import AppKit
import SwiftUI
import QuartzCore

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

final class RemoteDesktopView: NSView, @MainActor NSTextInputClient {
    weak var model: AppModel?
    private var image: CGImage?
    private var remoteSize: CGSize = .zero
    private var renderer: DesktopRenderer?
    private var triedMetal = false
    private var pendingFrame: DesktopFrame?
    private var redraw = true
    private var layoutBounds: CGRect?
    private var layoutBacking: CGSize?
    private var presentationGeneration = 0
    private var visibilityObservers: [NSObjectProtocol] = []
    private var frameTimes: [Double] = []
    private var lastStats = MRStatistics()
    private var markedText = NSMutableAttributedString(string: "")
    private var markedSelection = NSRange(location: 0, length: 0)
    private var textEvent: NSEvent?
    private var lastPresentedAt = 0.0
    private var pan = CGPoint.zero
    private let compositionLabel = NSTextField(labelWithString: "")
    private var compositionPoint = CGPoint(x: 24, y: 24)
    private var clock: CADisplayLink?
    private var frameCount = 0
    private var frameNeedsCounting = false
    private var measuredAt = ProcessInfo.processInfo.systemUptime
    var hasTouches: Bool { !points.isEmpty }
    func synchronizeCapsLock() { capsLock = NSEvent.modifierFlags.contains(.capsLock) }
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
        RemoteGeometry(bounds: bounds, remote: remoteSize, mode: model?.activePC?.viewMode ?? .fit, backingScale: convertToBacking(bounds).width / max(1, bounds.width), pan: pan)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        allowedTouchTypes = [.indirect]; wantsRestingTouches = false
        setAccessibilityLabel("Windows remote desktop")
        setAccessibilityRole(.group)
        compositionLabel.wantsLayer = true
        compositionLabel.drawsBackground = true; compositionLabel.backgroundColor = .controlBackgroundColor
        compositionLabel.font = .systemFont(ofSize: 16); compositionLabel.isHidden = true
        addSubview(compositionLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clearDesktop() {
        presentationGeneration += 1; pendingFrame = nil; remoteSize = .zero; renderer?.clear(); redraw = true
        unmarkText(); pan = .zero
        image = nil; lastLayout = nil; remoteCursor = nil; resetTouches(); needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if visibilityObservers.isEmpty {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didDeminiaturizeNotification] {
                    visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.wakePresentation() }
                    })
                }
                visibilityObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.wakePresentation() }
                })
            }
            model?.transport?.requestFrame()
            remoteCursor = model?.transport?.latestCursor
            clock?.invalidate()
            let link = displayLink(target: self, selector: #selector(presentLatest))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            clock = link
            wakePresentation()
            reportGeometry()
        } else { stop() }
    }
    func stop() {
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        visibilityObservers.removeAll()
        model?.transport?.setPresentation(visible: false, incremental: renderer != nil)
        clock?.invalidate(); clock = nil; resizeWork?.cancel(); model?.suspendInput(reason: "Session view changed · connection stays open") }
    override func layout() { super.layout(); updateLayout() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateLayout() }
    private func updateLayout() {
        let backing = convertToBacking(bounds).size
        guard layoutBounds != bounds || layoutBacking != backing else { return }
        layoutBounds = bounds; layoutBacking = backing
        redraw = true; wakePresentation(); scheduleResize()
    }
    private func scheduleResize() {
        resizeWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reportGeometry() }
        resizeWork = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
    func reportGeometry() {
        guard bounds.width > 1, bounds.height > 1, window?.isMiniaturized != true, let pc = model?.activePC else { return }
        let layout = DisplayLayout(points: bounds.size, backing: convertToBacking(bounds).size,
                                   retina: pc.optimizeRetina, scale: pc.desktopScale, fixed: pc.resolution)
        if lastLayout != layout || model?.phase == .connecting {
            lastLayout = layout; model?.geometry(layout)
        }
        refreshCursor()
    }
    func wakePresentation() {
        let visible = window?.isOnActiveSpace == true && window?.occlusionState.contains(.visible) == true
            && window?.isMiniaturized == false && model?.unlocked == true
        if !triedMetal, let device = model?.transport?.device {
            triedMetal = true; renderer = DesktopRenderer(device: device) { [weak self] ready in
                guard let self else { return }
                if ready { self.wakePresentation() } else { self.fallbackToCoreGraphics(); self.wakePresentation() }
            }
            if let renderer { layer?.insertSublayer(renderer.layer, at: 0) }
        }
        model?.transport?.setPresentation(visible: visible, incremental: renderer != nil)
        clock?.isPaused = !visible
    }
    @objc private func presentLatest() {
        guard window?.isOnActiveSpace == true, window?.occlusionState.contains(.visible) == true,
              window?.isMiniaturized == false, model?.unlocked == true else { wakePresentation(); return }
        if pendingFrame == nil { pendingFrame = model?.transport?.takeFrame() }
        let frame = pendingFrame
        let nextSize = frame?.size ?? remoteSize
        let backing = convertToBacking(bounds).size
        let nextGeometry = RemoteGeometry(bounds: bounds, remote: nextSize, mode: model?.activePC?.viewMode ?? .fit,
            backingScale: backing.width / max(1, bounds.width), pan: pan)
        if remoteSize == .zero && frame == nil { redraw = false }
        if let renderer, nextSize != .zero, frame != nil || redraw {
            let generation = presentationGeneration
            let isNew = frame != nil
            switch renderer.render(frame, bounds: bounds, backing: backing, imageRect: nextGeometry.imageRect,
                completion: { [weak self] success, elapsed in
                    DispatchQueue.main.async {
                        guard let self, generation == self.presentationGeneration else { return }
                        if !success { self.fallbackToCoreGraphics(); return }
                        self.model?.transport?.prepareNextFrame()
                        if isNew { self.frameCount += 1; self.lastPresentedAt = ProcessInfo.processInfo.systemUptime; self.frameTimes.append(elapsed) }
                    }
                }) {
            case .presented: remoteSize = nextSize; pendingFrame = nil; redraw = false
            case .busy: return
            case .warming: clock?.isPaused = true; return
            case .needsFullFrame:
                pendingFrame = nil; model?.transport?.requestFrame()
                if remoteSize == .zero { redraw = false }
            case .failed: fallbackToCoreGraphics()
            }
        } else if let frame {
            guard frame.isComplete else { pendingFrame = nil; model?.transport?.requestFrame(); return }
            remoteSize = nextSize; image = frame.image(); pendingFrame = nil; frameNeedsCounting = true; needsDisplay = true; redraw = false
        }
        if renderer == nil && redraw { needsDisplay = true; redraw = false }
        if let frame, pendingFrame == nil, remoteSize == frame.size {
            let resolution = "\(frame.info.width) × \(frame.info.height)"
            if model?.activeResolution != resolution { model?.activeResolution = resolution; refreshCursor() }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - measuredAt >= 1 { updateStatistics(now: now) }
        if pendingFrame == nil && model?.transport?.hasPendingPresentation != true && !redraw {
            updateStatistics(now: now)
            clock?.isPaused = true
        }
    }
    private func fallbackToCoreGraphics() {
        renderer?.layer.removeFromSuperlayer(); renderer = nil; pendingFrame = nil
        model?.transport?.setPresentation(visible: true, incremental: false)
        model?.transport?.requestFrame(); redraw = true
    }
    private func updateStatistics(now: Double) {
        let interval = max(0.001, now - measuredAt)
        guard interval >= 1 else { return }
        let fps = Int((Double(frameCount) / interval).rounded())
        if model?.presentedFPS != fps { model?.presentedFPS = fps }
        let stats = model?.transport?.statistics() ?? MRStatistics()
        let bytes = stats.snapshot_bytes >= lastStats.snapshot_bytes ? stats.snapshot_bytes - lastStats.snapshot_bytes : 0
        let commands = stats.surface_commands >= lastStats.surface_commands ? stats.surface_commands - lastStats.surface_commands : 0
        let decode = stats.surface_nanoseconds >= lastStats.surface_nanoseconds ? stats.surface_nanoseconds - lastStats.surface_nanoseconds : 0
        let sorted = frameTimes.sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let codec: String
        switch stats.codec {
        case 0x000b: codec = "H.264 AVC420"
        case 0x000e: codec = "H.264 AVC444"
        case 0x000f: codec = "H.264 AVC444v2"
        case 0: codec = "GDI / uncompressed"
        default: codec = "RDP codec 0x" + String(stats.codec, radix: 16)
        }
        let decoder: String
        switch mr_decoder_backend() {
        case 2: decoder = "VideoToolbox decode"
        case 1: decoder = "Software decode"
        default: decoder = "Decoder awaiting H.264 frames"
        }
        let detail = String(format: "%@ · %@\nSnapshot %.1f MB/s · GPU completion p95 %.1f ms\nGraphics command average %.2f ms · %@", renderer == nil ? "CoreGraphics" : "Metal", codec,
            Double(bytes) / interval / 1_000_000, p95, commands == 0 ? 0 : Double(decode) / Double(commands) / 1_000_000, decoder)
        if model?.performanceDetail != detail { model?.performanceDetail = detail }
        lastStats = stats; measuredAt = now; frameCount = 0; frameTimes.removeAll(keepingCapacity: true)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard renderer == nil else { return }
        NSColor.black.setFill(); bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = geometry.imageRect
        context.saveGState()
        context.interpolationQuality = convertToBacking(rect).size == CGSize(width: image.width, height: image.height) ? .none : .high
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        if frameNeedsCounting { frameCount += 1; lastPresentedAt = ProcessInfo.processInfo.systemUptime; frameNeedsCounting = false }
        context.restoreGState()
    }
    func displaySettingsChanged() { pan = .zero; redraw = true; lastLayout = nil; reportGeometry(); wakePresentation() }
    func refreshIdleMetrics() {
        if ProcessInfo.processInfo.systemUptime - lastPresentedAt > 1.2 {
            if model?.presentedFPS != 0 { model?.presentedFPS = 0 }
            if model?.sessionControlsOpen == true { updateStatistics(now: ProcessInfo.processInfo.systemUptime) }
        }
    }
    override func keyDown(with event: NSEvent) {
        if model?.usesTextInput == true {
            guard model?.remoteInput == true, model?.capture == false else { return }
            if event.modifierFlags.intersection([.control, .command]).isEmpty {
                textEvent = event; interpretKeyEvents([event]); textEvent = nil
            } else { sendTextCommand(event) }
            return
        }
        model?.nativeKey(KeyStroke(key: event.keyCode, down: true, repeating: event.isARepeat))
    }
    override func keyUp(with event: NSEvent) {
        guard model?.usesTextInput != true else { return }
        model?.nativeKey(KeyStroke(key: event.keyCode, down: false))
    }
    override func flagsChanged(with event: NSEvent) {
        guard model?.usesTextInput != true else { return }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if event.keyCode == 57 {
            let enabled = flags.contains(.maskAlphaShift)
            if enabled != capsLock {
                capsLock = enabled
                model?.nativeKey(KeyStroke(key: 57, down: true)); model?.nativeKey(KeyStroke(key: 57, down: false))
            }
        } else { model?.nativeKey(KeyStroke(key: event.keyCode, down: KeyboardTap.modifierDown(key: event.keyCode, flags: flags))) }
    }
    private func sendTextCommand(_ event: NSEvent) {
        let modifiers: [(NSEvent.ModifierFlags, UInt16)] = [(.control, 59), (.command, 55), (.option, 58), (.shift, 56)]
        let keys = modifiers.filter { event.modifierFlags.contains($0.0) }.map(\.1) + [event.keyCode]
        for key in keys { model?.nativeKey(KeyStroke(key: key, down: true)) }
        for key in keys.reversed() { model?.nativeKey(KeyStroke(key: key, down: false)) }
    }
    override func resignFirstResponder() -> Bool {
        inputContext?.discardMarkedText(); unmarkText()
        model?.suspendInput(reason: "Mac input · remote session stays connected")
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
            compositionPoint = convert(event.locationInWindow, from: nil)
            guard geometry.point(convert(event.locationInWindow, from: nil)) != nil else { return }
            window?.makeFirstResponder(self)
            if model?.remoteInput != true { model?.resumeWindowsInput() }
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
        if model?.activePC?.viewMode == .actual && model?.inputMode == .mac {
            let rect = geometry.imageRect
            pan = CGPoint(x: rect.midX - bounds.midX + event.scrollingDeltaX,
                          y: rect.midY - bounds.midY + event.scrollingDeltaY)
            redraw = true; wakePresentation(); return
        }
        for flags in scrollWheelFlags(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) {
            send(event, flags: flags)
        }
    }
    func scrollWheelFlags(deltaX: Double, deltaY: Double, precise: Bool) -> [UInt16] {
        let multiplier = precise ? 3.0 : 120.0
        let horizontalDirection = model?.reverseHorizontalScrolling == true ? -1.0 : 1.0
        wheelY += deltaY * multiplier; wheelX += deltaX * multiplier * horizontalDirection
        var events: [UInt16] = []
        for horizontal in [false, true] {
            var delta = horizontal ? wheelX : wheelY
            while abs(delta) >= 1 {
                let step = Int(max(-255, min(255, delta)))
                let flags = UInt16(horizontal ? 0x0400 : 0x0200) | UInt16(bitPattern: Int16(step)) & 0x01ff
                events.append(flags); delta -= Double(step)
            }
            if horizontal { wheelX = delta } else { wheelY = delta }
        }
        return events
    }
    func hasMarkedText() -> Bool { markedText.length > 0 }
    func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { markedSelection }
    func setMarkedText(_ value: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard model?.remoteInput == true, model?.usesTextInput == true else { return }
        let attributed = value as? NSAttributedString ?? NSAttributedString(string: value as? String ?? "")
        markedText.setAttributedString(attributed); markedSelection = selectedRange
        compositionLabel.stringValue = attributed.string; compositionLabel.sizeToFit()
        compositionLabel.frame.origin = CGPoint(x: min(max(0, compositionPoint.x), max(0, bounds.width - compositionLabel.frame.width)),
            y: min(max(0, compositionPoint.y), max(0, bounds.height - compositionLabel.frame.height)))
        compositionLabel.isHidden = attributed.length == 0
    }
    func unmarkText() {
        markedText.setAttributedString(NSAttributedString(string: "")); markedSelection = NSRange(location: 0, length: 0)
        compositionLabel.isHidden = true; compositionLabel.stringValue = ""
    }
    func insertText(_ value: Any, replacementRange: NSRange) {
        let text = (value as? NSAttributedString)?.string ?? value as? String ?? ""
        unmarkText(); model?.sendText(text)
    }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle, .foregroundColor] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound, range.location <= markedText.length else { return nil }
        let valid = NSRange(location: range.location, length: min(range.length, markedText.length - range.location))
        actualRange?.pointee = valid; return markedText.attributedSubstring(from: valid)
    }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = hasMarkedText() ? markedRange() : selectedRange()
        return window?.convertToScreen(convert(NSRect(origin: compositionPoint, size: CGSize(width: 1, height: 22)), to: nil)) ?? .zero
    }
    override func doCommand(by selector: Selector) {
        guard let event = textEvent else { super.doCommand(by: selector); return }
        sendTextCommand(event)
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
            let fit = remoteSize.width > 0 ? geometry.imageRect.width / remoteSize.width : 1
            nativeCursor = NSCursor(image: NSImage(cgImage: image, size: NSSize(width: CGFloat(cursor.width) * fit, height: CGFloat(cursor.height) * fit)),
                hotSpot: NSPoint(x: CGFloat(cursor.x) * fit, y: CGFloat(cursor.y) * fit))
        } else { nativeCursor = .arrow }
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() { addCursorRect(geometry.imageRect, cursor: nativeCursor) }
    func resetScrolling() { wheelX = 0; wheelY = 0 }
    func resetTouches() { points.removeAll(keepingCapacity: true); touchIdentities.removeAllObjects(); mouseButtons.removeAll(); resetScrolling() }
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
