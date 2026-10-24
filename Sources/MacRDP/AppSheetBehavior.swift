import AppKit
import SwiftUI

struct AppSheetBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> SheetView { SheetView() }
    func updateNSView(_ view: SheetView, context: Context) {}

    final class SheetView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.preventsApplicationTerminationWhenModal = false
        }
    }
}

extension View {
    func permitsAppTermination() -> some View {
        background(AppSheetBehavior().frame(width: 0, height: 0))
    }
}
