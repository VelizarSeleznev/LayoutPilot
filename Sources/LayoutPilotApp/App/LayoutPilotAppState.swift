import LayoutPilotCore
import Observation

@MainActor
@Observable
final class LayoutPilotAppState {
    let store: LayoutPilotStore
    let engine: LayoutAutomationEngine

    init() {
        self.store = LayoutPilotStore()
        self.engine = LayoutAutomationEngine(store: store)
        store.changeHandler = { [weak engine, store] in
            engine?.refreshNow()
            SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
            SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
            
            SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
            SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
            
            // Sync translation settings
            SmartInputService.shared.translationEnabled = store.configuration.llm.translationEnabled ?? true
            SmartInputService.shared.translationEndpointURL = store.configuration.llm.endpointURL
            SmartInputService.shared.translationModel = store.configuration.llm.model
            SmartInputService.shared.translationLanguages = store.configuration.llm.translationLanguages ?? []
        }
        engine.start()
        SmartInputService.shared.isEnabled = store.configuration.smartDanishInputEnabled
        SmartInputService.shared.allowedBundleIDs = Set(store.configuration.smartDanishInputAllowedBundleIDs)
        
        SmartInputService.shared.smartBilingualEnabled = store.configuration.smartBilingualEnabled
        SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(store.configuration.smartBilingualAllowedBundleIDs)
        
        // Sync translation settings on launch
        SmartInputService.shared.translationEnabled = store.configuration.llm.translationEnabled ?? true
        SmartInputService.shared.translationEndpointURL = store.configuration.llm.endpointURL
        SmartInputService.shared.translationModel = store.configuration.llm.model
        SmartInputService.shared.translationLanguages = store.configuration.llm.translationLanguages ?? []
        
        SmartInputService.shared.start()
    }
}

