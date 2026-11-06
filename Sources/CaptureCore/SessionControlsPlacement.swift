public enum SessionControlsPosition: String, CaseIterable, Codable, Sendable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight

    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }

    public var isBottom: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: true
        default: false
        }
    }

}
