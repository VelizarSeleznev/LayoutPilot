import SwiftUI
import LayoutPilotCore

struct MenuBarView: View {
    @Bindable var appState: LayoutPilotAppState
    @Environment(\.openWindow) private var openWindow

    private var activeApplication: RecentApplicationContext {
        RecentApplicationContext(
            applicationName: appState.engine.snapshot.frontmostApplicationName,
            bundleID: appState.engine.snapshot.frontmostBundleID
        )
    }

    private var olderRecentApplications: [RecentApplicationContext] {
        appState.engine.recentApplications.filter { $0.bundleID != activeApplication.bundleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeApplicationPanel

            if !olderRecentApplications.isEmpty {
                recentApplicationsPanel
            }

            globalControlsPanel
            footerActions
        }
        .padding(12)
        .frame(width: 390)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.accentColor.opacity(0.08),
                        Color.black.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }

    private var activeApplicationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIconView(bundleID: activeApplication.bundleID, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: activeApplication.applicationName))
                        .font(.headline)
                        .lineLimit(1)
                    Text(activeApplication.bundleID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            applicationControls(for: activeApplication, isProminent: true)
        }
        .glassLikePanel(cornerRadius: 20)
    }

    private var recentApplicationsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(olderRecentApplications) { application in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AppIconView(bundleID: application.bundleID, size: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName(for: application.applicationName))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(application.bundleID)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    applicationControls(for: application, isProminent: false)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
            }
        }
        .glassLikePanel(cornerRadius: 18)
    }

    private var globalControlsPanel: some View {
        VStack(spacing: 8) {
            Toggle("Global Auto-Switching", isOn: Binding(
                get: { appState.store.configuration.automationEnabled },
                set: { appState.store.setAutomationEnabled($0) }
            ))

            Toggle("Global Smart RU/EN", isOn: Binding(
                get: { appState.store.configuration.smartBilingualEnabled },
                set: { appState.store.setSmartBilingualEnabled($0) }
            ))

            Toggle("Global Smart Danish", isOn: Binding(
                get: { appState.store.configuration.smartDanishInputEnabled },
                set: { appState.store.setSmartDanishInputEnabled($0) }
            ))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .glassLikePanel(cornerRadius: 16)
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "main")
            } label: {
                Label("Dashboard", systemImage: "rectangle.stack")
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }

    private func applicationControls(for application: RecentApplicationContext, isProminent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Auto-Switch", selection: Binding(
                    get: { autoSwitchSelection(for: application) },
                    set: { setAutoSwitchSelection($0, for: application) }
                )) {
                    Text("None").tag("none")
                    Text("Last Used").tag("lastUsed")
                    ForEach(appState.store.configuration.profiles) { profile in
                        Text(profile.name).tag("profile:\(profile.id.uuidString)")
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                Spacer()

                statusBadge(for: application)
            }

            HStack(spacing: 14) {
                Toggle("RU/EN", isOn: Binding(
                    get: { isSmartBilingualEnabled(for: application) },
                    set: { setSmartBilingualEnabled($0, for: application) }
                ))

                Toggle("Danish", isOn: Binding(
                    get: { isSmartInputEnabled(for: application) },
                    set: { setSmartInputEnabled($0, for: application) }
                ))
            }
            .toggleStyle(.switch)
            .controlSize(isProminent ? .regular : .small)
        }
    }

    private func statusBadge(for application: RecentApplicationContext) -> some View {
        let targetName = isAutoSwitchActive(for: application)
            ? autoSwitchTargetName(for: applicationRule(for: application))
            : "Manual"

        return Text(targetName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
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
}

private extension View {
    func glassLikePanel(cornerRadius: CGFloat) -> some View {
        padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.12),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
            .shadow(color: Color.white.opacity(0.12), radius: 1, y: -1)
    }
}
