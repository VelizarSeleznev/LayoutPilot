import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LayoutAutomationEngine {
    public private(set) var snapshot = AutomationSnapshot()
    public private(set) var isRunning = false
    public private(set) var lastErrorMessage: String?

    private let store: LayoutPilotStore
    private let inputSourceClient: InputSourceClient
    private var notificationTokens: [NSObjectProtocol] = []

    public init(
        store: LayoutPilotStore,
        inputSourceClient: InputSourceClient = SystemInputSourceClient()
    ) {
        self.store = store
        self.inputSourceClient = inputSourceClient
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
        refreshNow()
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens {
            center.removeObserver(token)
        }
        notificationTokens.removeAll()
        isRunning = false
    }

    public func refreshNow() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let currentSourceID = inputSourceClient.currentInputSourceID() ?? "Unknown"
        let bundleID = frontmostApp?.bundleIdentifier ?? "Unknown"
        let appName = frontmostApp?.localizedName ?? "Unknown"

        guard store.configuration.automationEnabled else {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "Automation disabled",
                lastAction: "Idle"
            )
            return
        }

        guard let rule = store.rule(for: bundleID) else {
            snapshot = AutomationSnapshot(
                frontmostApplicationName: appName,
                frontmostBundleID: bundleID,
                currentInputSourceID: currentSourceID,
                matchedRuleDescription: "No rule matched",
                lastAction: "No change"
            )
            return
        }

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
}
