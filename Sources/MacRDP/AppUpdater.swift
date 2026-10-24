import AppKit
import SwiftUI
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var message = "Updates are downloaded from GitHub and verified before installation."
    @Published var automaticChecks = true {
        didSet { if started { controller.updater.automaticallyChecksForUpdates = automaticChecks } }
    }
    var sessionIsActive: () -> Bool = { false }
    var willShowUI: (() -> Void)?
    var willRelaunch: (() -> Void)?
    private var started = false
    private var pendingInstall: (() -> Void)?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    let releasesURL = URL(string: "https://github.com/aagzamov-dev/MacRDP/releases")!
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    func start() {
        guard !started else { return }
        controller.startUpdater()
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        started = true
    }
    func check() {
        guard !sessionIsActive() else { message = "Disconnect Windows before checking for updates."; return }
        willShowUI?()
        controller.checkForUpdates(nil)
    }
    func sessionEnded() {
        guard !sessionIsActive(), let install = pendingInstall else { return }
        pendingInstall = nil
        install()
    }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        prepareForRelaunch()
    }
    func prepareForRelaunch() {
        pendingInstall = nil
        willRelaunch?()
    }
    func postponeInstallation(_ install: @escaping () -> Void) -> Bool {
        guard sessionIsActive() else { return false }
        pendingInstall = install
        message = "Update ready. Installation will continue after you disconnect Windows."
        return true
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if sessionIsActive() {
            throw NSError(domain: "MacRDP.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Updates wait until your Windows session is disconnected."])
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        willShowUI?()
        message = "MacRDP \(item.displayVersionString) is available."
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { message = "You’re up to date." }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { message = error.localizedDescription }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation(installHandler)
    }
}

struct UpdatesView: View {
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Software updates", systemImage: "arrow.triangle.2.circlepath").font(.title2.weight(.semibold))
            Text("MacRDP \(updater.version)")
            Toggle("Automatically check for updates", isOn: $updater.automaticChecks)
            Text(updater.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Update checks wait while Windows is connected. New releases are signed with MacRDP’s update key; no Apple Developer account is required.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Release notes", destination: updater.releasesURL)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Check for updates…") { updater.check() }.buttonStyle(.borderedProminent).disabled(!updater.canCheck)
            }
        }.padding(28).frame(width: 500).background(Color(nsColor: .windowBackgroundColor))
    }
}
