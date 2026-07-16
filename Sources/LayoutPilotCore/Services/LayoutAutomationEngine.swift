import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LayoutAutomationEngine {
    public private(set) var snapshot = AutomationSnapshot()
    public private(set) var recentApplications: [RecentApplicationContext] = []
    public private(set) var lastExternalApplication: RecentApplicationContext?
    public private(set) var isRunning = false
    public private(set) var lastErrorMessage: String?
    public private(set) var activeWebsiteDomain: String?

    nonisolated public static let layoutPilotBundleID = "com.velizard.LayoutPilot"
    nonisolated static let recentApplicationLimit = 4

    private let store: LayoutPilotStore
    private let inputSourceClient: InputSourceClient
    private let activeContextProvider: () -> RecentApplicationContext
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var defaultNotificationTokens: [NSObjectProtocol] = []
    private var websiteRefreshTimer: DispatchSourceTimer?
    private let websiteLookupQueue = DispatchQueue(
        label: "com.velizard.LayoutPilot.website-lookup",
        qos: .utility
    )
    private var websiteLookupGeneration = 0
    private var monitoredBrowserBundleID: String?
    private var previousBundleID: String?
    private var lastUsedInputSourceByBundleID: [String: String] = [:]

    public init(
        store: LayoutPilotStore,
        inputSourceClient: InputSourceClient = SystemInputSourceClient(),
        activeContextProvider: @escaping () -> RecentApplicationContext = {
            let application = NSWorkspace.shared.frontmostApplication
            return RecentApplicationContext(
                applicationName: application?.localizedName ?? "Unknown",
                bundleID: application?.bundleIdentifier ?? "Unknown"
            )
        }
    ) {
        self.store = store
        self.inputSourceClient = inputSourceClient
        self.activeContextProvider = activeContextProvider
    }

    public func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceNotificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshNow()
                }
            }
        )
        defaultNotificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshNow()
                }
            }
        )
        refreshNow()
    }

    public func stop() {
        stopWebsiteMonitor()
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceNotificationTokens {
            center.removeObserver(token)
        }
        workspaceNotificationTokens.removeAll()
        for token in defaultNotificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        defaultNotificationTokens.removeAll()
        isRunning = false
    }

    public func refreshNow(forceApplyRule: Bool = false) {
        refreshNow(forceApplyRule: forceApplyRule, requestsWebsiteDomain: true)
    }

    public func refreshWebsiteNow() {
        guard store.configuration.isModuleAdded(.layoutSwitching),
              let application = lastExternalApplication,
              BrowserURLService.isBrowser(bundleID: application.bundleID) else {
            return
        }
        requestWebsiteDomainRefresh(for: application)
    }

    private func refreshNow(forceApplyRule: Bool, requestsWebsiteDomain: Bool) {
        let activeContext = activeContextProvider()
        guard Self.isExternalApplication(activeContext) else {
            stopWebsiteMonitor()
            return
        }

        let currentSourceID = inputSourceClient.currentInputSourceID() ?? "Unknown"
        let bundleID = activeContext.bundleID
        let appName = activeContext.applicationName
        let enteredNewContext = previousBundleID == nil || previousBundleID != bundleID

        if enteredNewContext {
            activeWebsiteDomain = nil
            if let previousApplication = lastExternalApplication {
                rememberRecentApplication(
                    applicationName: previousApplication.applicationName,
                    bundleID: previousApplication.bundleID
                )
            }
        }

        lastExternalApplication = activeContext
        updateWebsiteMonitor(for: activeContext)
        if store.configuration.isModuleAdded(.layoutSwitching),
           requestsWebsiteDomain,
           BrowserURLService.isBrowser(bundleID: bundleID) {
            requestWebsiteDomainRefresh(for: activeContext)
        }

        let shouldRestoreLastUsedInputSource = rememberLastUsedInputSource(
            currentSourceID,
            forPreviousBundleBeforeActivating: bundleID
        )

        guard store.configuration.isLayoutSwitchingActive else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Automation disabled",
                lastAction: "Idle"
            ))
            return
        }

        if let domain = activeWebsiteDomain {
            if let matchedWebsiteRule = store.configuration.websiteRules.first(where: { rule in
                rule.isEnabled && (domain == rule.domain || domain.hasSuffix("." + rule.domain))
            }) {
                applyWebsiteRule(
                    matchedWebsiteRule,
                    host: domain,
                    appName: appName,
                    bundleID: bundleID,
                    currentSourceID: currentSourceID,
                    shouldApply: forceApplyRule || enteredNewContext
                )
                return
            }
        }

        guard let rule = store.effectiveRule(for: bundleID, applicationName: appName) else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "No rule matched",
                lastAction: "No change"
            ))
            return
        }

        switch rule.target {
        case .profile:
            applyProfileRule(
                rule,
                appName: appName,
                bundleID: bundleID,
                currentSourceID: currentSourceID,
                shouldApply: forceApplyRule || enteredNewContext
            )
        case .lastUsed:
            applyLastUsedRule(
                rule,
                appName: appName,
                bundleID: bundleID,
                currentSourceID: currentSourceID,
                shouldRestore: shouldRestoreLastUsedInputSource
            )
        }
    }

    nonisolated static func updatedRecentApplications(
        _ recentApplications: [RecentApplicationContext],
        with application: RecentApplicationContext,
        limit: Int = recentApplicationLimit
    ) -> [RecentApplicationContext] {
        guard isExternalApplication(application) else {
            return recentApplications
        }

        var updated = recentApplications.filter { $0.bundleID != application.bundleID }
        updated.insert(application, at: 0)
        return Array(updated.prefix(limit))
    }

    nonisolated public static func isExternalApplication(_ application: RecentApplicationContext) -> Bool {
        application.bundleID != "Unknown" &&
            application.bundleID != layoutPilotBundleID &&
            !application.bundleID.isEmpty
    }

    nonisolated public static func shouldMonitorWebsite(
        bundleID: String,
        hasEnabledWebsiteRules: Bool
    ) -> Bool {
        hasEnabledWebsiteRules && BrowserURLService.isBrowser(bundleID: bundleID)
    }

    @discardableResult
    private func rememberLastUsedInputSource(
        _ currentSourceID: String,
        forPreviousBundleBeforeActivating activeBundleID: String
    ) -> Bool {
        let didActivateNewBundle = previousBundleID != nil && previousBundleID != activeBundleID
        defer { previousBundleID = activeBundleID == "Unknown" ? previousBundleID : activeBundleID }

        guard currentSourceID != "Unknown",
              let previousBundleID,
              previousBundleID != activeBundleID else {
            return false
        }

        lastUsedInputSourceByBundleID[previousBundleID] = currentSourceID
        return didActivateNewBundle
    }

    private func rememberCurrentInputSource(_ currentSourceID: String, for bundleID: String) {
        guard currentSourceID != "Unknown", bundleID != "Unknown" else {
            return
        }

        lastUsedInputSourceByBundleID[bundleID] = currentSourceID
    }

    private func rememberRecentApplication(applicationName: String, bundleID: String) {
        let updated = Self.updatedRecentApplications(
            recentApplications,
            with: RecentApplicationContext(applicationName: applicationName, bundleID: bundleID)
        )
        if updated != recentApplications {
            recentApplications = updated
        }
    }

    private func publishSnapshot(_ updatedSnapshot: AutomationSnapshot) {
        guard snapshot != updatedSnapshot else { return }
        snapshot = updatedSnapshot
    }

    private func updateWebsiteMonitor(for application: RecentApplicationContext) {
        let hasEnabledRules = store.configuration.isModuleAdded(.layoutSwitching)
            && store.configuration.websiteRules.contains { $0.isEnabled }
        guard Self.shouldMonitorWebsite(
            bundleID: application.bundleID,
            hasEnabledWebsiteRules: hasEnabledRules
        ) else {
            stopWebsiteMonitor()
            return
        }

        guard monitoredBrowserBundleID != application.bundleID || websiteRefreshTimer == nil else {
            return
        }

        stopWebsiteMonitor()
        monitoredBrowserBundleID = application.bundleID
        let timer = DispatchSource.makeTimerSource(queue: websiteLookupQueue)
        timer.schedule(
            deadline: .now() + .seconds(2),
            repeating: .seconds(2),
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.monitoredBrowserBundleID == application.bundleID,
                      self.lastExternalApplication?.bundleID == application.bundleID else {
                    return
                }
                self.requestWebsiteDomainRefresh(for: application)
            }
        }
        timer.resume()
        websiteRefreshTimer = timer
    }

    private func stopWebsiteMonitor() {
        websiteRefreshTimer?.cancel()
        websiteRefreshTimer = nil
        monitoredBrowserBundleID = nil
    }

    private func requestWebsiteDomainRefresh(for application: RecentApplicationContext) {
        guard BrowserURLService.isBrowser(bundleID: application.bundleID),
              let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier == application.bundleID else {
            return
        }

        websiteLookupGeneration += 1
        let generation = websiteLookupGeneration
        let processIdentifier = frontmostApp.processIdentifier
        let bundleID = application.bundleID

        websiteLookupQueue.async { [weak self] in
            let domain: String?
            if let app = NSRunningApplication(processIdentifier: processIdentifier),
               let urlString = BrowserURLService.activeURL(for: app) {
                domain = BrowserURLService.domain(from: urlString)
            } else {
                domain = nil
            }

            Task { @MainActor in
                guard let self,
                      generation == self.websiteLookupGeneration,
                      self.lastExternalApplication?.bundleID == bundleID else {
                    return
                }

                let didChange = self.activeWebsiteDomain != domain
                if didChange {
                    self.activeWebsiteDomain = domain
                }

                guard didChange,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
                    return
                }
                self.refreshNow(forceApplyRule: true, requestsWebsiteDomain: false)
            }
        }
    }

    private func applyProfileRule(
        _ rule: ApplicationLayoutRule,
        appName: String,
        bundleID: String,
        currentSourceID: String,
        shouldApply: Bool
    ) {
        guard let profile = store.profile(for: rule.profileID) else {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Missing profile \(rule.profileID.uuidString)",
                lastAction: "No change"
            ))
            lastErrorMessage = "Rule found for \(bundleID) but the target profile no longer exists."
            return
        }

        guard shouldApply else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Remembered current layout"
            ))
            lastErrorMessage = nil
            return
        }

        if profile.inputSourceID == currentSourceID {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Already on \(profile.name)"
            ))
            return
        }

        do {
            try inputSourceClient.activateInputSource(withID: profile.inputSourceID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: profile.inputSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Switched to \(profile.name)"
            ))
            lastErrorMessage = nil
        } catch {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Switch failed"
            ))
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyLastUsedRule(
        _ rule: ApplicationLayoutRule,
        appName: String,
        bundleID: String,
        currentSourceID: String,
        shouldRestore: Bool
    ) {
        let description = "Matched \(rule.applicationName) -> Last Used"
        guard shouldRestore else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Remembered current layout"
            ))
            lastErrorMessage = nil
            return
        }

        guard let targetSourceID = lastUsedInputSourceByBundleID[bundleID] else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "No last used layout yet"
            ))
            lastErrorMessage = nil
            return
        }

        if targetSourceID == currentSourceID {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Already on last used layout"
            ))
            lastErrorMessage = nil
            return
        }

        do {
            try inputSourceClient.activateInputSource(withID: targetSourceID)
            rememberCurrentInputSource(targetSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: targetSourceID,
                matchedRuleDescription: description,
                lastAction: "Switched to last used layout"
            ))
            lastErrorMessage = nil
        } catch {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Switch failed"
            ))
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyWebsiteRule(
        _ rule: WebsiteLayoutRule,
        host: String,
        appName: String,
        bundleID: String,
        currentSourceID: String,
        shouldApply: Bool
    ) {
        guard let profile = store.profile(for: rule.profileID) else {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Missing profile \(rule.profileID.uuidString)",
                lastAction: "No change"
            ))
            lastErrorMessage = "Rule found for website \(host) but the target profile no longer exists."
            return
        }

        guard shouldApply else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched website \(host) -> \(profile.name)",
                lastAction: "Remembered current layout"
            ))
            lastErrorMessage = nil
            return
        }

        if profile.inputSourceID == currentSourceID {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched website \(host) -> \(profile.name)",
                lastAction: "Already on \(profile.name)"
            ))
            return
        }

        do {
            try inputSourceClient.activateInputSource(withID: profile.inputSourceID)
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: profile.inputSourceID,
                matchedRuleDescription: "Matched website \(host) -> \(profile.name)",
                lastAction: "Switched to \(profile.name)"
            ))
            lastErrorMessage = nil
        } catch {
            publishSnapshot(AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched website \(host) -> \(profile.name)",
                lastAction: "Switch failed"
            ))
            lastErrorMessage = error.localizedDescription
        }
    }
}
