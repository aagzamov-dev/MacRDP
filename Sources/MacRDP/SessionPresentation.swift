import AppKit

@MainActor
final class SessionPresentation {
    private let read: () -> NSApplication.PresentationOptions
    private let write: (NSApplication.PresentationOptions) -> Void
    private var original: NSApplication.PresentationOptions?

    init(read: (() -> NSApplication.PresentationOptions)? = nil,
         write: ((NSApplication.PresentationOptions) -> Void)? = nil) {
        self.read = read ?? { NSApp.presentationOptions }
        self.write = write ?? { NSApp.presentationOptions = $0 }
    }

    func beginCapture() {
        guard original == nil else { return }
        let baseline = read()
        original = baseline
        var options = baseline
        options.remove([.hideDock, .hideMenuBar])
        options.formUnion([.autoHideDock, .autoHideMenuBar, .disableProcessSwitching])
        write(options)
    }

    func restore() {
        guard let original else { return }
        write(original)
        self.original = nil
    }
}
