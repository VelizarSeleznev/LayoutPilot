import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LayoutAutomationEngine {
    public private(set) var snapshot = AutomationSnapshot()
    public private(set) var recentApplications: [RecentApplicationContext] = []
    public private(set) var isRunning = false
    public private(set) var lastErrorMessage: String?

    nonisolated static let recentApplicationLimit = 3

    private let store: LayoutPilotStore
    private let inputSourceClient: InputSourceClient
    private let activeContextProvider: () -> RecentApplicationContext
    private var notificationTokens: [NSObjectProtocol] = []
    private var refreshTimer: DispatchSourceTimer?
    private var previousBundleID: String?
    private var lastUsedInputSourceByBundleID: [String: String] = [:]

    public init(
        store: LayoutPilotStore,
        inputSourceClient: InputSourceClient = SystemInputSourceClient(),
        activeContextProvider: @escaping () -> RecentApplicationContext = {
            SystemApplicationContexts.activeContext(frontmostApplication: NSWorkspace.shared.frontmostApplication)
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
        notificationTokens.append(
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
        let refreshTimer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.velizard.LayoutPilot.layout-refresh")
        )
        refreshTimer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        refreshTimer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refreshNow()
                }
            }
        }
        refreshTimer.resume()
        self.refreshTimer = refreshTimer
        refreshNow()
    }

    public func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens {
            center.removeObserver(token)
        }
        notificationTokens.removeAll()
        isRunning = false
    }

    public func refreshNow(forceApplyRule: Bool = false) {
        let activeContext = activeContextProvider()
        let currentSourceID = inputSourceClient.currentInputSourceID() ?? "Unknown"
        let bundleID = activeContext.bundleID
        let appName = activeContext.applicationName
        let enteredNewContext = previousBundleID == nil || previousBundleID != bundleID
        let shouldRestoreLastUsedInputSource = rememberLastUsedInputSource(
            currentSourceID,
            forPreviousBundleBeforeActivating: bundleID
        )
        rememberRecentApplication(applicationName: appName, bundleID: bundleID)

        guard store.configuration.automationEnabled else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Automation disabled",
                lastAction: "Idle"
            )
            return
        }

        guard let rule = store.effectiveRule(for: bundleID, applicationName: appName) else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "No rule matched",
                lastAction: "No change"
            )
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
        guard application.bundleID != "Unknown" else {
            return recentApplications
        }

        var updated = recentApplications.filter { $0.bundleID != application.bundleID }
        updated.insert(application, at: 0)
        return Array(updated.prefix(limit))
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
        recentApplications = Self.updatedRecentApplications(
            recentApplications,
            with: RecentApplicationContext(applicationName: applicationName, bundleID: bundleID)
        )
    }

    private func applyProfileRule(
        _ rule: ApplicationLayoutRule,
        appName: String,
        bundleID: String,
        currentSourceID: String,
        shouldApply: Bool
    ) {
        guard let profile = store.profile(for: rule.profileID) else {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Missing profile \(rule.profileID.uuidString)",
                lastAction: "No change"
            )
            lastErrorMessage = "Rule found for \(bundleID) but the target profile no longer exists."
            return
        }

        guard shouldApply else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Remembered current layout"
            )
            lastErrorMessage = nil
            return
        }

        if profile.inputSourceID == currentSourceID {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Already on \(profile.name)"
            )
            return
        }

        do {
            try inputSourceClient.activateInputSource(withID: profile.inputSourceID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: profile.inputSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Switched to \(profile.name)"
            )
            lastErrorMessage = nil
        } catch {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Matched \(rule.applicationName) -> \(profile.name)",
                lastAction: "Switch failed"
            )
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
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Remembered current layout"
            )
            lastErrorMessage = nil
            return
        }

        guard let targetSourceID = lastUsedInputSourceByBundleID[bundleID] else {
            rememberCurrentInputSource(currentSourceID, for: bundleID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "No last used layout yet"
            )
            lastErrorMessage = nil
            return
        }

        if targetSourceID == currentSourceID {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Already on last used layout"
            )
            lastErrorMessage = nil
            return
        }

        do {
            try inputSourceClient.activateInputSource(withID: targetSourceID)
            rememberCurrentInputSource(targetSourceID, for: bundleID)
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: targetSourceID,
                matchedRuleDescription: description,
                lastAction: "Switched to last used layout"
            )
            lastErrorMessage = nil
        } catch {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: description,
                lastAction: "Switch failed"
            )
            lastErrorMessage = error.localizedDescription
        }
    }
}
