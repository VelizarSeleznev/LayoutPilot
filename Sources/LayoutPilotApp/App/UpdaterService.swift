import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterService()

    @Published private(set) var isReady = false
    @Published private(set) var automaticUpdatesEnabled = true
    @Published private(set) var lastUpdateCheckDate: Date?

    private var updaterController: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard updaterController == nil else {
            refreshState()
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        isReady = true
        refreshState()
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }

        // Sparkle persists both values in the application's user defaults.
        // Setting them only in response to this user-facing toggle preserves
        // the default configuration without overwriting later user choices.
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        refreshState()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
        refreshState()
    }

    func refreshState() {
        guard let updater = updaterController?.updater else {
            isReady = false
            return
        }

        isReady = true
        automaticUpdatesEnabled =
            updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    // MARK: - SPUUpdaterDelegate

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Return true to take responsibility for installing the update immediately
        // and trigger the silent background installation/relaunch.
        immediateInstallHandler()
        return true
    }
}
