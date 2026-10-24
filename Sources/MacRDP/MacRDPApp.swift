import AppKit
import SwiftUI

@main
struct MacRDPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    private let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "MacRDP"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        let toolbar = NSToolbar(identifier: "MacRDPToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
        window.center()
        self.window = window
        model.window = window
        model.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("add"), .flexibleSpace, .init("release"), .init("pc"), .init("lock")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let title: String
        let symbol: String
        let action: Selector
        switch id.rawValue {
        case "add": title = "Add PC"; symbol = "plus"; action = #selector(addPC)
        case "release": title = "Release \(model.shortcut.displayName)"; symbol = "escape"; action = #selector(releaseInput)
        case "pc": title = "Settings"; symbol = "slider.horizontal.3"; action = #selector(editPC)
        case "lock": title = "Lock"; symbol = "lock"; action = #selector(lockApp)
        default: return nil
        }
        item.label = title
        item.paletteLabel = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self
        item.action = action
        item.toolTip = id.rawValue == "release" ? "Use Mac keyboard · keep session open" : title
        return item
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier.rawValue == "release" {
            item.label = "Release \(model.shortcut.displayName)"
            item.toolTip = "Use Mac keyboard · toggle with \(model.shortcut.displayName) · keep session open"
        }
        return model.unlocked
    }
    @objc private func releaseInput() { if model.unlocked { model.releaseButton() } }
    @objc private func editPC() { if model.unlocked { model.openSettings() } }
    @objc private func addPC() { if model.unlocked { model.addPC() } }
    @objc private func lockApp() { if model.unlocked { model.lockApp() } }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.subtracting([.disableProcessSwitching, .disableForceQuit, .disableSessionTermination])
    }
}
