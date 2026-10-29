import AppKit
import Combine
import Sparkle

@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = true
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    var menuTitle: String { availableVersion.map { "Update available — v\($0)…" } ?? "Update DocBrown…" }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.automaticChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.lastChecked = updater.lastUpdateCheckDate }
            }
        ]
        do { try updater.start() }
        catch { lastError = error.localizedDescription }
    }

    func checkForUpdates() {
        guard let controller else { return }
        lastError = nil
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    // Even launch-time checks must stay quiet. Only an explicit menu/settings action
    // is allowed to bring Sparkle's native update window to the foreground.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError?, error.code != SUError.noUpdateError.rawValue {
            lastError = error.localizedDescription
        } else {
            lastError = nil
            if error != nil { availableVersion = nil }
        }
    }
}
