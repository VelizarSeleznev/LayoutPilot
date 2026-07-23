import AppKit
import Foundation
import LayoutPilotCore
import Observation

@MainActor
@Observable
final class LayoutPilotAppState {
    let store: LayoutPilotStore
    let engine: LayoutAutomationEngine
    private let remotePrankPackService: RemotePrankPackService
    var launchAtLoginState: LaunchAtLoginService.State
    var selectedSidebarSection: SidebarSection?

    init() {
        self.store = LayoutPilotStore()
        self.engine = LayoutAutomationEngine(store: store)
        self.remotePrankPackService = RemotePrankPackService(store: store)
        self.launchAtLoginState = LaunchAtLoginService.currentState()
        store.changeHandler = { [weak self, weak engine] in
            guard let self else { return }
            engine?.refreshNow(forceApplyRule: true)
            Self.syncSmartInputService(with: self.store.configuration)
            Self.configureRemoteUsageReporting(with: self.store.configuration)
            self.remotePrankPackService.syncWithCurrentConfiguration()

            // Sync launch at login
            self.launchAtLoginState = LaunchAtLoginService.sync(enabled: self.store.configuration.launchAtLogin)
        }
        engine.start()
        Self.syncSmartInputService(with: store.configuration)
        Self.configureRemoteUsageReporting(with: store.configuration)
        remotePrankPackService.syncWithCurrentConfiguration()

        // Sync launch at login on launch
        launchAtLoginState = LaunchAtLoginService.sync(enabled: store.configuration.launchAtLogin)
        
        // Global Rewrite hotkey (⌥⇧R) → on-device LLM rewrite of the selection.
        SmartInputService.shared.onRewriteHotkey = {
            Task { @MainActor in RewriteService.shared.run() }
        }

        SmartInputService.shared.onInstantGlobeSwitch = { source in
            Task { @MainActor in
                GlobeSwitchIndicator.shared.show(source: source)
            }
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

    func disableAndRemoveRemotePrankPack() {
        store.disableAndRemoveRemotePrankPack()
        remotePrankPackService.syncWithCurrentConfiguration()
    }

    func setRemotePrankPackActive(_ isActive: Bool) {
        store.setRemotePrankPackActive(isActive)
    }

    func syncAnonymousUsageReporting() {
        Self.configureRemoteUsageReporting(with: store.configuration)
    }

    private static func syncSmartInputService(with configuration: LayoutPilotConfiguration) {
        SmartInputService.shared.isEnabled = configuration.isSmartDanishActive
        SmartInputService.shared.allowedBundleIDs = Set(configuration.smartDanishInputAllowedBundleIDs)
        SmartInputService.shared.smartBilingualEnabled = configuration.isSmartBilingualActive
        SmartInputService.shared.smartBilingualAllowedBundleIDs = Set(configuration.smartBilingualAllowedBundleIDs)
        SmartInputService.shared.smartBilingualUndoDelay = configuration.smartBilingualUndoDelay
        SmartInputService.shared.smartInputLearningScope = configuration.smartInputLearningScope
        SmartInputService.shared.smartBilingualApplyToAll = configuration.smartBilingualApplyToAll
        SmartInputService.shared.danishApplyToAll = configuration.smartDanishApplyToAll
        SmartInputService.shared.textSnippetsEnabled = configuration.areTextSnippetsActive
        SmartInputService.shared.textSnippetExpansionMode = configuration.textSnippetExpansionMode
        SmartInputService.shared.textSnippets = configuration.textSnippets
        SmartInputService.shared.textSnippetGroups = configuration.textSnippetGroups
        SmartInputService.shared.spellingAutocorrectEnabled = configuration.spellingAutocorrectEnabled
        let instantGlobeSwitchingEnabled =
            configuration.isModuleAdded(.layoutSwitching) && configuration.instantGlobeSwitchingEnabled
        _ = SystemGlobeKeyActionService.shared.setLayoutPilotControlEnabled(instantGlobeSwitchingEnabled)
        SmartInputService.shared.instantGlobeSwitchingEnabled = instantGlobeSwitchingEnabled
    }

    private static func configureRemoteUsageReporting(with configuration: LayoutPilotConfiguration) {
        if configuration.anonymousUsageStatisticsEnabled {
            SmartInputEventLog.shared.setRemoteEventHandler { event in
                Task {
                    await AnonymousUsageReporter.shared.submit(event)
                }
            }
        } else {
            SmartInputEventLog.shared.setRemoteEventHandler(nil)
        }
    }
}
