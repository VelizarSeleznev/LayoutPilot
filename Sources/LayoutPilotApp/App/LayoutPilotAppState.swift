import AppKit
import Foundation
import LayoutPilotCore
import Observation

@MainActor
@Observable
final class LayoutPilotAppState {
    let store: LayoutPilotStore
    let engine: LayoutAutomationEngine
    var launchAtLoginState: LaunchAtLoginService.State
    var selectedSidebarSection: SidebarSection?

    init() {
        self.store = LayoutPilotStore()
        self.engine = LayoutAutomationEngine(store: store)
        self.launchAtLoginState = LaunchAtLoginService.currentState()
        store.changeHandler = { [weak self, weak engine, store] in
            engine?.refreshNow(forceApplyRule: true)
            Self.syncSmartInputService(with: store.configuration)

            // Sync launch at login
            self?.launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        }
        engine.start()
        Self.syncSmartInputService(with: store.configuration)

        // Sync launch at login on launch
        launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        
        // Global Rewrite hotkey (⌥⇧R) → on-device LLM rewrite of the selection.
        SmartInputService.shared.onRewriteHotkey = {
            Task { @MainActor in RewriteService.shared.run() }
        }

        // Suggestions panel callbacks
        SmartInputService.shared.onShowSuggestions = { @Sendable context in
            Task { @MainActor in
                SuggestionsPanel.shared.show(context: context)
            }
        }
        SmartInputService.shared.onHideSuggestions = { @Sendable in
            Task { @MainActor in
                SuggestionsPanel.shared.hide()
            }
        }

        // Run log spelling bootstrap on a background thread
        DispatchQueue.global(qos: .background).async {
            SmartInputLearningStore.shared.bootstrapSpellingVocabularyFromLogs(checker: NSSpellChecker.shared)
        }

        SmartInputService.shared.start()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginState = LaunchAtLoginService.sync(enabled: isEnabled)
        store.setLaunchAtLogin(isEnabled)
    }

    private static func syncSmartInputService(with configuration: LayoutPilotConfiguration) {
        SmartInputService.shared.isEnabled = configuration.isSmartDanishActive
        SmartInputService.shared.allowedBundleIDs = Set(configuration.smartDanishInputAllowedBundleIDs)
        SmartInputService.shared.smartBilingualEnabled = configuration.isSmartBilingualActive
        SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(configuration.smartBilingualAllowedBundleIDs)
        SmartInputService.shared.smartBilingualUndoDelay = configuration.smartBilingualUndoDelay
        SmartInputService.shared.smartBilingualApplyToAll = configuration.smartBilingualApplyToAll
        SmartInputService.shared.danishApplyToAll = configuration.smartDanishApplyToAll
        SmartInputService.shared.textSnippetsEnabled = configuration.areTextSnippetsActive
        SmartInputService.shared.textSnippetExpansionMode = configuration.textSnippetExpansionMode
        SmartInputService.shared.textSnippets = configuration.textSnippets
        SmartInputService.shared.textSnippetGroups = configuration.textSnippetGroups
        SmartInputService.shared.spellingAutocorrectEnabled = configuration.spellingAutocorrectEnabled
    }
}
