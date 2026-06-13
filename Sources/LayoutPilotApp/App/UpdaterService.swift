import Foundation
import Sparkle

final class UpdaterService: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterService()
    
    private var updaterController: SPUStandardUpdaterController?
    
    private override init() {
        super.init()
    }
    
    func start() {
        // SPUStandardUpdaterController starts checking for updates automatically
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
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
