import AppKit
import SwiftUI
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    @Published private(set) var canCheck = false
    @Published private(set) var message = "Updates are downloaded from GitHub and verified before installation."
    @Published var automaticChecks = true {
        didSet { if started { updater.automaticallyChecksForUpdates = automaticChecks } }
    }
    var sessionIsActive: () -> Bool = { false }
    var willShowUI: (() -> Void)?
    var willInstall: (() -> Void)?
    var willRelaunch: (() -> Void)?
    private var started = false
    private var pendingInstall: (() -> Void)?
    @Published private(set) var actionTitle: String?
    @Published private(set) var progress: Double?
    @Published private(set) var busy = false
    @Published private(set) var canCancel = false
    private var action: (() -> Void)?
    private var cancellation: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
    let releasesURL = URL(string: "https://github.com/aagzamov-dev/MacRDP/releases")!
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    func start() {
        guard !started else { return }
        do { try updater.start() } catch { message = error.localizedDescription; return }
        automaticChecks = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        started = true
    }
    func check() {
        guard !sessionIsActive() else { message = "Disconnect Windows before checking for updates."; return }
        willShowUI?()
        updater.checkForUpdates()
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
    func performAction() {
        guard !sessionIsActive() else { message = "Disconnect Windows before installing updates."; return }
        let callback = action
        action = nil; actionTitle = nil
        callback?()
    }
    func cancel() {
        let callback = cancellation
        clearActions()
        busy = false; message = "Update cancelled."
        callback?()
    }
    private func clearActions() {
        action = nil; actionTitle = nil; cancellation = nil; canCancel = false; progress = nil
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        clearActions(); busy = true; message = "Checking for updates…"
        self.cancellation = cancellation; canCancel = true
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearActions(); busy = false
        message = "MacRDP \(appcastItem.displayVersionString) is available."
        if !appcastItem.isInformationOnlyUpdate {
            actionTitle = state.stage == .installing ? "Install and restart" : "Download update"
            action = { [weak self] in
                if state.stage == .installing { self?.willInstall?() }
                reply(.install)
            }
        }
        cancellation = { reply(.dismiss) }; canCancel = true
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        clearActions(); busy = false; message = error.localizedDescription
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        clearActions(); busy = false; message = error.localizedDescription
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        clearActions(); busy = true; message = "Downloading update…"
        expectedBytes = 0; receivedBytes = 0
        self.cancellation = cancellation; canCancel = true
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expectedBytes = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        if expectedBytes > 0 { progress = min(1, Double(receivedBytes) / Double(expectedBytes)) }
    }
    func showDownloadDidStartExtractingUpdate() {
        clearActions(); busy = true; message = "Verifying and preparing update…"
    }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = min(1, max(0, progress)) }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearActions(); busy = false; message = "Update ready. Restart to install it."
        actionTitle = "Install and restart"
        action = { [weak self] in self?.willInstall?(); reply(.install) }
        cancellation = { reply(.dismiss) }; canCancel = true
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        clearActions(); busy = true; message = "Closing MacRDP and installing update…"
        if !applicationTerminated {
            actionTitle = "Retry closing MacRDP"; action = retryTerminatingApplication
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        clearActions(); busy = false; message = "Update installed."
        acknowledgement()
    }
    func dismissUpdateInstallation() { clearActions(); busy = false }
    func showUpdateInFocus() { willShowUI?() }

}

struct UpdatesView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Software updates", systemImage: "arrow.triangle.2.circlepath").font(.title2.weight(.semibold))
            Text("MacRDP \(updater.version)")
            Toggle("Automatically check for updates", isOn: $updater.automaticChecks)
            Text(updater.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Update checks wait while Windows is connected. New releases are signed with MacRDP’s update key; no Apple Developer account is required.")
                .font(.caption).foregroundStyle(.secondary)
            if updater.busy {
                if let progress = updater.progress { ProgressView(value: progress) }
                else { ProgressView().controlSize(.small) }
            }
            HStack {
                Link("Release notes", destination: updater.releasesURL)
                Spacer()
                if updater.canCancel { Button("Cancel update") { updater.cancel() } }
                if let title = updater.actionTitle {
                    Button(title) { updater.performAction() }.buttonStyle(.borderedProminent)
                }
                Button("Check for updates…") { updater.check() }.buttonStyle(.borderedProminent).disabled(!updater.canCheck || updater.busy || updater.actionTitle != nil)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
}
