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
    private var pendingThreeFingerAction: TrackpadAction?
    public init() {}

    public mutating func reset() {
        origins.removeAll(keepingCapacity: true)
        fired = false
        cancelled = false
        maximumCount = 0
        pendingThreeFingerAction = nil
    }

    public mutating func update(_ touches: [TouchPoint], ended: Bool = false,
                                isCancelled: Bool = false,
                                threeFinger: GestureMapping = .windowsDesktops,
                                fourFinger: GestureMapping = .macDesktops) -> TrackpadAction? {
        if isCancelled { cancelled = true }
        if touches.isEmpty {
            let action = ended && !cancelled && !fired && maximumCount == 3 ? pendingThreeFingerAction : nil
            reset()
            return action
        }
        guard !fired, !cancelled else { return nil }
        maximumCount = max(maximumCount, touches.count)
        if touches.count > 4 { cancelled = true; return nil }
        if maximumCount == 4 { pendingThreeFingerAction = nil }
        if touches.count < 3 {
            if ended, maximumCount == 3, let action = pendingThreeFingerAction {
                fired = true
                return action
            }
            return nil
        }
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
        let action: TrackpadAction?
        switch mapping {
        case .disabled: action = nil
        case .macDesktops: action = max(abs(dx), abs(dy)) >= 0.12 ? .release : nil
        case .taskView: action = max(abs(dx), abs(dy)) >= 0.14 ? .taskView : nil
        case .windowsDesktops:
            action = abs(dx) >= 0.10 && abs(dx) > abs(dy) * 1.5 ? (dx < 0 ? .desktopLeft : .desktopRight) : nil
        }
        if maximumCount == 3 { pendingThreeFingerAction = action }
        guard ended, let action else { return nil }
        fired = true
        return action
    }
}
