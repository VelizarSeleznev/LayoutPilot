import AppKit
import SwiftUI
import LayoutPilotCore

struct MenuBarView: View {
    @Bindable var appState: LayoutPilotAppState
    @Bindable private var inspector = FocusInspectorController.shared
    @Bindable private var selectionInspector = SelectionInspectorController.shared
    @Environment(\.openWindow) private var openWindow

    private var activeApplication: RecentApplicationContext {
        RecentApplicationContext(
            applicationName: appState.engine.snapshot.frontmostApplicationName,
            bundleID: appState.engine.snapshot.frontmostBundleID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            activeApplicationHeader
            activeApplicationControls

            if let domain = appState.engine.activeWebsiteDomain {
                Divider()
                activeWebsiteHeader(domain: domain)
                activeWebsiteControls(domain: domain)
            }

            Divider()

            Toggle("Auto-switching", isOn: Binding(
                get: { appState.store.configuration.automationEnabled },
                set: { appState.store.setAutomationEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("AX Inspector", isOn: Binding(
                get: { inspector.isVisible },
                set: { _ in inspector.toggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("Selection Inspector", isOn: Binding(
                get: { selectionInspector.isVisible },
                set: { _ in selectionInspector.toggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            footerActions
        }
        .padding(12)
        .frame(width: 280)
    }

    private var activeApplicationHeader: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: activeApplication.bundleID, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(for: activeApplication.applicationName))
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText(for: activeApplication))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var activeApplicationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Layout", selection: Binding(
                get: { autoSwitchSelection(for: activeApplication) },
                set: { setAutoSwitchSelection($0, for: activeApplication) }
            )) {
                Text("None").tag("none")
                Text("Last Used").tag("lastUsed")
                ForEach(appState.store.configuration.profiles) { profile in
                    Text(profile.name).tag("profile:\(profile.id.uuidString)")
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            HStack(spacing: 16) {
                Toggle("RU/EN", isOn: Binding(
                    get: { isSmartBilingualEnabled(for: activeApplication) },
                    set: { setSmartBilingualEnabled($0, for: activeApplication) }
                ))

                Toggle("Danish", isOn: Binding(
                    get: { isSmartInputEnabled(for: activeApplication) },
                    set: { setSmartInputEnabled($0, for: activeApplication) }
                ))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button {
                NSLog("[Menu] Dashboard tapped")
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                NSLog("[Menu] Dashboard openWindow called")
            } label: {
                Label("Dashboard", systemImage: "rectangle.stack")
            }

            Button {
                NSLog("[Menu] Website Rules tapped")
                appState.selectedSidebarSection = .websites
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Websites", systemImage: "globe")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
        }
        .controlSize(.small)
    }

    private func statusText(for application: RecentApplicationContext) -> String {
        guard appState.store.configuration.automationEnabled else {
            return "Auto-switching off"
        }
        if isAutoSwitchActive(for: application) {
            return "Auto: \(autoSwitchTargetName(for: applicationRule(for: application)))"
        }
        if appState.store.configuration.defaultAutoSwitchEnabled {
            return "Default: \(defaultTargetName())"
        }
        return "Manual"
    }

    private func applicationRule(for application: RecentApplicationContext) -> ApplicationLayoutRule? {
        appState.store.configuration.rules.first { $0.applicationBundleID == application.bundleID }
    }

    private func autoSwitchSelection(for application: RecentApplicationContext) -> String {
        guard let rule = applicationRule(for: application), rule.isEnabled else {
            return "none"
        }

        switch rule.target {
        case .profile:
            return "profile:\(rule.profileID.uuidString)"
        case .lastUsed:
            return "lastUsed"
        }
    }

    private func setAutoSwitchSelection(_ selection: String, for application: RecentApplicationContext) {
        if selection == "none" {
            removeAutoSwitch(for: application)
            return
        }

        let fallbackProfileID = applicationRule(for: application)?.profileID ?? appState.store.configuration.profiles.first?.id ?? UUID()
        let target: ApplicationLayoutRuleTarget
        let profileID: UUID

        if selection == "lastUsed" {
            target = .lastUsed
            profileID = fallbackProfileID
        } else if selection.hasPrefix("profile:"),
                  let selectedProfileID = UUID(uuidString: String(selection.dropFirst("profile:".count))) {
            target = .profile
            profileID = selectedProfileID
        } else {
            return
        }

        setAutoSwitch(for: application, profileID: profileID, target: target)
    }

    private func isSmartInputEnabled(for application: RecentApplicationContext) -> Bool {
        appState.store.configuration.smartDanishInputAllowedBundleIDs.contains(application.bundleID)
    }

    private func isSmartBilingualEnabled(for application: RecentApplicationContext) -> Bool {
        appState.store.configuration.smartBilingualAllowedBundleIDs.contains(application.bundleID)
    }

    private func isAutoSwitchActive(for application: RecentApplicationContext) -> Bool {
        applicationRule(for: application)?.isEnabled ?? false
    }

    private func setAutoSwitch(
        for application: RecentApplicationContext,
        profileID: UUID,
        target: ApplicationLayoutRuleTarget
    ) {
        let rule = ApplicationLayoutRule(
            applicationBundleID: application.bundleID,
            applicationName: application.applicationName,
            profileID: profileID,
            target: target,
            isEnabled: true
        )
        appState.store.upsertRule(rule)
        appState.engine.refreshNow()
    }

    private func autoSwitchTargetName(for rule: ApplicationLayoutRule?) -> String {
        guard let rule else { return "Unknown" }

        switch rule.target {
        case .profile:
            return appState.store.configuration.profiles.first { $0.id == rule.profileID }?.name ?? "Unknown"
        case .lastUsed:
            return "Last Used"
        }
    }

    private func defaultTargetName() -> String {
        switch appState.store.configuration.defaultAutoSwitchTarget {
        case .lastUsed:
            return "Last Used"
        case .profile:
            let id = appState.store.configuration.defaultAutoSwitchProfileID
            return appState.store.configuration.profiles.first { $0.id == id }?.name ?? "Last Used"
        }
    }

    private func removeAutoSwitch(for application: RecentApplicationContext) {
        guard let rule = applicationRule(for: application) else {
            return
        }

        var updated = rule
        updated.isEnabled = false
        appState.store.upsertRule(updated)
        appState.engine.refreshNow()
    }

    private func setSmartInputEnabled(_ isEnabled: Bool, for application: RecentApplicationContext) {
        if isEnabled {
            appState.store.addSmartDanishInputAllowedBundleID(application.bundleID)
        } else {
            appState.store.removeSmartDanishInputAllowedBundleID(application.bundleID)
        }
        appState.engine.refreshNow()
    }

    private func setSmartBilingualEnabled(_ isEnabled: Bool, for application: RecentApplicationContext) {
        if isEnabled {
            appState.store.addSmartBilingualAllowedBundleID(application.bundleID)
        } else {
            appState.store.removeSmartBilingualAllowedBundleID(application.bundleID)
        }
        appState.engine.refreshNow()
    }

    private func displayName(for applicationName: String) -> String {
        let maximumLength = 30
        guard applicationName.count > maximumLength else {
            return applicationName
        }

        return String(applicationName.prefix(maximumLength - 3)) + "..."
    }

    private func activeWebsiteHeader(domain: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(domain)
                    .font(.headline)
                    .lineLimit(1)
                Text(websiteStatusText(for: domain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private func activeWebsiteControls(domain: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Layout", selection: Binding(
                get: { websiteRuleSelection(for: domain) },
                set: { setWebsiteRuleSelection($0, for: domain) }
            )) {
                Text("None (Use App Default)").tag("none")
                ForEach(appState.store.configuration.profiles) { profile in
                    Text(profile.name).tag(profile.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private func matchedWebsiteRule(for domain: String) -> WebsiteLayoutRule? {
        appState.store.configuration.websiteRules.first { rule in
            domain == rule.domain || domain.hasSuffix("." + rule.domain)
        }
    }

    private func websiteStatusText(for domain: String) -> String {
        guard appState.store.configuration.automationEnabled else {
            return "Auto-switching off"
        }
        if let rule = matchedWebsiteRule(for: domain), rule.isEnabled {
            let profileName = appState.store.profile(for: rule.profileID)?.name ?? "Unknown Layout"
            return "Auto: \(profileName)"
        }
        return "Using app default"
    }

    private func websiteRuleSelection(for domain: String) -> String {
        guard let rule = matchedWebsiteRule(for: domain), rule.isEnabled else {
            return "none"
        }
        return rule.profileID.uuidString
    }

    private func setWebsiteRuleSelection(_ selection: String, for domain: String) {
        if selection == "none" {
            if let rule = matchedWebsiteRule(for: domain) {
                appState.store.deleteWebsiteRule(id: rule.id)
                appState.engine.refreshNow()
            }
            return
        }

        guard let profileID = UUID(uuidString: selection) else { return }

        if var rule = matchedWebsiteRule(for: domain) {
            rule.profileID = profileID
            rule.isEnabled = true
            appState.store.upsertWebsiteRule(rule)
        } else {
            let rule = WebsiteLayoutRule(domain: domain, profileID: profileID, isEnabled: true)
            appState.store.upsertWebsiteRule(rule)
        }
        appState.engine.refreshNow()
    }
}
