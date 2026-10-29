// Invoked by test-updater.py against isolated fixture applications only.
import AppKit
import Sparkle

@MainActor final class Driver: NSObject, SPUUserDriver {
    let expectFailure: Bool
    let expectCurrent: Bool
    init(expectFailure: Bool, expectCurrent: Bool = false) { self.expectFailure = expectFailure; self.expectCurrent = expectCurrent }
    func finish(_ success: Bool, _ message: String) {
        print(message)
        fflush(stdout)
        exit(success ? 0 : 1)
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish(expectCurrent && (error as NSError).code == SUError.noUpdateError.rawValue, "No update: \(error)")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish(expectFailure, "Rejected update: \(error)")
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish(!expectFailure, "Installed signed update")
    }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() {}
}

@main struct UpdateTestMain {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let target = Bundle(path: CommandLine.arguments[1])!
        let driver = Driver(expectFailure: CommandLine.arguments.contains("--expect-failure"), expectCurrent: CommandLine.arguments.contains("--expect-current"))
        let updater = SPUUpdater(hostBundle: target, applicationBundle: target, userDriver: driver, delegate: nil)
        try updater.start()
        if CommandLine.arguments.contains("--validate-config") { print("Updater configuration valid"); return }
        updater.checkForUpdates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { driver.finish(false, "Updater timed out") }
        withExtendedLifetime((driver, updater)) { app.run() }
    }
}
