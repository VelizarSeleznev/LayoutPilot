import LayoutPilotCore
import Observation

@MainActor
@Observable
final class LayoutPilotAppState {
    let store: LayoutPilotStore
    let engine: LayoutAutomationEngine
    var launchAtLoginState: LaunchAtLoginService.State

    init() {
        self.store = LayoutPilotStore()
        self.engine = LayoutAutomationEngine(store: store)
        self.launchAtLoginState = LaunchAtLoginService.currentState()
        store.changeHandler = { [weak self, weak engine, store] in
            engine?.refreshNow(forceApplyRule: true)
            SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
            SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
            
            SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
            SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
            SmartInputService.shared.smartBilingualUndoDelay = store.configuration.smartBilingualUndoDelay
            SmartInputService.shared.smartBilingualApplyToAll = store.configuration.smartBilingualApplyToAll
            SmartInputService.shared.danishApplyToAll = store.configuration.smartDanishApplyToAll

            // Sync launch at login
            self?.launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        }
        engine.start()
        SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
        SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
        
        SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
        SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
        SmartInputService.shared.smartBilingualUndoDelay = store.configuration.smartBilingualUndoDelay

        // Sync launch at login on launch
        launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        
        // Global Rewrite hotkey (⌥⇧R) → on-device LLM rewrite of the selection.
        SmartInputService.shared.onRewriteHotkey = {
            Task { @MainActor in RewriteService.shared.run() }
        }

        SmartInputService.shared.start()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginState = LaunchAtLoginService.sync(enabled: isEnabled)
        store.setLaunchAtLogin(isEnabled)
    }
}
