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
            engine?.refreshNow()
            SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
            SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
            
            SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
            SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
            SmartInputService.shared.smartBilingualUndoDelay = store.configuration.smartBilingualUndoDelay
            
            // Sync translation settings
            SmartInputService.shared.translationEnabled = store.configuration.llm.translationEnabled ?? true
            SmartInputService.shared.translationEndpointURL = store.configuration.llm.endpointURL
            SmartInputService.shared.translationModel = store.configuration.llm.model
            SmartInputService.shared.translationLanguages = store.configuration.llm.translationLanguages ?? []
            
            // Sync launch at login
            self?.launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        }
        engine.start()
        SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
        SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
        
        SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
        SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
        SmartInputService.shared.smartBilingualUndoDelay = store.configuration.smartBilingualUndoDelay
        
        // Sync translation settings on launch
        SmartInputService.shared.translationEnabled = store.configuration.llm.translationEnabled ?? true
        SmartInputService.shared.translationEndpointURL = store.configuration.llm.endpointURL
        SmartInputService.shared.translationModel = store.configuration.llm.model
        SmartInputService.shared.translationLanguages = store.configuration.llm.translationLanguages ?? []
        
        // Sync launch at login on launch
        launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        
        SmartInputService.shared.start()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginState = LaunchAtLoginService.sync(enabled: isEnabled)
        store.setLaunchAtLogin(isEnabled)
    }
}
