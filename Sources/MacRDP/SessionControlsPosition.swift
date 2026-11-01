import SwiftUI

enum SessionControlsPosition: String, CaseIterable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }

    var isBottom: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: true
        default: false
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .topLeft, .bottomLeft: .leading
        case .topCenter, .bottomCenter: .center
        case .topRight, .bottomRight: .trailing
        }
    }

    var alignment: Alignment {
        Alignment(horizontal: horizontalAlignment, vertical: isBottom ? .bottom : .top)
    }
}
