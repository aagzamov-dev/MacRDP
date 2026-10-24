import Foundation

public struct TouchPoint: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public init(id: Int, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
}

public enum TrackpadAction: Equatable, Sendable {
    case release, desktopLeft, desktopRight, taskView
}

public struct TrackpadGesture: Sendable {
    private var origins: [Int: TouchPoint] = [:]
    private var fired = false
    private var cancelled = false
    private var maximumCount = 0
    public init() {}

    public mutating func reset() {
        origins.removeAll(keepingCapacity: true)
        fired = false
        cancelled = false
        maximumCount = 0
    }

    public mutating func update(_ touches: [TouchPoint], ended: Bool = false,
                                isCancelled: Bool = false,
                                threeFinger: GestureMapping = .windowsDesktops,
                                fourFinger: GestureMapping = .macDesktops) -> TrackpadAction? {
        if isCancelled { cancelled = true }
        if touches.isEmpty {
            reset()
            return nil
        }
        guard !fired, !cancelled else { return nil }
        maximumCount = max(maximumCount, touches.count)
        if touches.count > 4 { cancelled = true; return nil }
        if touches.count < 3 { return nil }
        let ids = Set(touches.map(\.id))
        if Set(origins.keys) != ids {
            if !origins.isEmpty, touches.count <= origins.count { cancelled = true; return nil }
            origins = Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0) })
            return nil
        }
        let dx = touches.map { $0.x - origins[$0.id]!.x }.reduce(0, +) / Double(touches.count)
        let dy = touches.map { $0.y - origins[$0.id]!.y }.reduce(0, +) / Double(touches.count)
        let mapping = maximumCount == 4 ? fourFinger : threeFinger
        if maximumCount == 4, mapping == .macDesktops, max(abs(dx), abs(dy)) >= 0.12 {
            fired = true
            return .release
        }
        // A three-finger action commits on lift, allowing a fourth finger to take priority.
        guard ended else { return nil }
        switch mapping {
        case .disabled: return nil
        case .macDesktops:
            guard max(abs(dx), abs(dy)) >= 0.12 else { return nil }
            fired = true; return .release
        case .taskView:
            guard max(abs(dx), abs(dy)) >= 0.14 else { return nil }
            fired = true; return .taskView
        case .windowsDesktops:
            guard abs(dx) >= 0.14, abs(dx) > abs(dy) * 1.5 else { return nil }
            fired = true; return dx < 0 ? .desktopLeft : .desktopRight
        }
    }
}
