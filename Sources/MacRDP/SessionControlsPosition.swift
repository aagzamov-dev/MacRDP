import SwiftUI

extension SessionControlsPosition {
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
