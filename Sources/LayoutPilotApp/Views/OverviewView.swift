import AppKit
import LayoutPilotCore
import SwiftUI

struct OverviewView: View {
    @Bindable var appState: LayoutPilotAppState

    private var currentApplication: RecentApplicationContext? {
        appState.engine.lastExternalApplication
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let error = appState.engine.lastErrorMessage ?? appState.store.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if let application = currentApplication {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            currentContextCard(application)
                                .frame(maxWidth: .infinity)
                            recentApplicationsCard
                                .frame(maxWidth: .infinity)
                        }

                        VStack(spacing: 18) {
                            currentContextCard(application)
                            recentApplicationsCard
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Switch to another app to begin",
                        systemImage: "rectangle.on.rectangle",
                        description: Text("LayoutPilot will keep that app ready here when you return.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(28)
        }
        .navigationTitle("Home")
        .onAppear {
            appState.engine.refreshWebsiteNow()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOME")
                    .font(.caption.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("Everything is ready")
                    .font(.largeTitle.weight(.semibold))
                Text("LayoutPilot follows the app and website you use.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Automatic switching", isOn: Binding(
                get: { appState.store.configuration.automationEnabled },
                set: { appState.store.setAutomationEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.top, 8)
        }
    }

    private func currentContextCard(_ application: RecentApplicationContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Last Active Context")

            HStack(spacing: 12) {
                AppIconView(bundleID: application.bundleID, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.applicationName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Last active application")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)

            Divider()
            appLayoutRow(application)
            Divider()
            smartInputRow(
                title: "Smart RU/EN",
                symbol: "character.book.closed",
                isOn: isSmartBilingualEnabled(for: application)
            ) {
                setSmartBilingualEnabled(!isSmartBilingualEnabled(for: application), for: application)
            }
            Divider()
            smartInputRow(
                title: "Smart Danish",
                symbol: "character.textbox",
                isOn: isSmartDanishEnabled(for: application)
            ) {
                setSmartDanishEnabled(!isSmartDanishEnabled(for: application), for: application)
            }

            if let domain = appState.engine.activeWebsiteDomain {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(domain)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Last active website")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.secondary.opacity(0.035))

                Divider()
                siteLayoutRow(domain)
            }
        }
        .homeCardStyle()
    }

    private var recentApplicationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Recent Applications")

            if appState.engine.recentApplications.isEmpty {
                ContentUnavailableView(
                    "No Recent Apps",
                    systemImage: "clock",
                    description: Text("Apps appear here as you switch between them.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ForEach(Array(appState.engine.recentApplications.prefix(4).enumerated()), id: \.element.id) { index, application in
                    if index > 0 { Divider() }
                    recentApplicationRow(application)
                }
            }
        }
        .homeCardStyle()
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.035))
    }

    private func appLayoutRow(_ application: RecentApplicationContext) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text("App Layout")
            Spacer(minLength: 8)
            layoutPicker(
                selection: Binding(
                    get: { autoSwitchSelection(for: application) },
                    set: { setAutoSwitchSelection($0, for: application) }
                ),
                inheritedTitle: "No Override",
                includesLastUsed: true
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func siteLayoutRow(_ domain: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text("Site Layout")
            Spacer(minLength: 8)
            layoutPicker(
                selection: Binding(
                    get: { websiteRuleSelection(for: domain) },
                    set: { setWebsiteRuleSelection($0, for: domain) }
                ),
                inheritedTitle: "Use App Layout",
                includesLastUsed: false
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func smartInputRow(
        title: String,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(isOn ? Color.accentColor : Color.secondary.opacity(0.14), in: Circle())
                Text(title)
                Spacer()
                Text(isOn ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func recentApplicationRow(_ application: RecentApplicationContext) -> some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: application.bundleID, size: 32)

            VStack(alignment: .leading, spacing: 7) {
                Text(application.applicationName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    layoutPicker(
                        selection: Binding(
                            get: { autoSwitchSelection(for: application) },
                            set: { setAutoSwitchSelection($0, for: application) }
                        ),
                        inheritedTitle: "No Override",
                        includesLastUsed: true,
                        width: 120
                    )

                    compactToggle(
                        symbol: "character.book.closed",
                        label: "Smart RU/EN",
                        isOn: isSmartBilingualEnabled(for: application)
                    ) {
                        setSmartBilingualEnabled(!isSmartBilingualEnabled(for: application), for: application)
                    }
                    compactToggle(
                        symbol: "character.textbox",
                        label: "Smart Danish",
                        isOn: isSmartDanishEnabled(for: application)
                    ) {
                        setSmartDanishEnabled(!isSmartDanishEnabled(for: application), for: application)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 72)
    }

    private func compactToggle(
        symbol: String,
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .help("\(label): \(isOn ? "On" : "Off")")
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func layoutPicker(
        selection: Binding<String>,
        inheritedTitle: String,
        includesLastUsed: Bool,
        width: CGFloat = 138
    ) -> some View {
        Picker("Layout", selection: selection) {
            Text(inheritedTitle).tag("none")
            if includesLastUsed {
                Text("Last Used").tag("lastUsed")
                Divider()
            }
            ForEach(appState.store.configuration.profiles) { profile in
                Text(profile.name).tag("profile:\(profile.id.uuidString)")
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: width)
    }

    private func applicationRule(for application: RecentApplicationContext) -> ApplicationLayoutRule? {
        appState.store.configuration.rules.first { $0.applicationBundleID == application.bundleID }
    }

    private func autoSwitchSelection(for application: RecentApplicationContext) -> String {
        guard let rule = applicationRule(for: application), rule.isEnabled else { return "none" }
        switch rule.target {
        case .lastUsed:
            return "lastUsed"
        case .profile:
            return "profile:\(rule.profileID.uuidString)"
        }
    }

    private func setAutoSwitchSelection(_ selection: String, for application: RecentApplicationContext) {
        if selection == "none" {
            guard var rule = applicationRule(for: application) else { return }
            rule.isEnabled = false
            appState.store.upsertRule(rule)
            return
        }

        let fallbackID = applicationRule(for: application)?.profileID
            ?? appState.store.configuration.profiles.first?.id
            ?? UUID()
        let target: ApplicationLayoutRuleTarget
        let profileID: UUID
        if selection == "lastUsed" {
            target = .lastUsed
            profileID = fallbackID
        } else if selection.hasPrefix("profile:"),
                  let id = UUID(uuidString: String(selection.dropFirst("profile:".count))) {
            target = .profile
            profileID = id
        } else {
            return
        }

        appState.store.upsertRule(ApplicationLayoutRule(
            applicationBundleID: application.bundleID,
            applicationName: application.applicationName,
            profileID: profileID,
            target: target,
            isEnabled: true
        ))
    }

    private func isSmartBilingualEnabled(for application: RecentApplicationContext) -> Bool {
        appState.store.configuration.smartBilingualAllowedBundleIDs.contains(application.bundleID)
    }

    private func setSmartBilingualEnabled(_ isEnabled: Bool, for application: RecentApplicationContext) {
        if isEnabled {
            appState.store.addSmartBilingualAllowedBundleID(application.bundleID)
        } else {
            appState.store.removeSmartBilingualAllowedBundleID(application.bundleID)
        }
    }

    private func isSmartDanishEnabled(for application: RecentApplicationContext) -> Bool {
        appState.store.configuration.smartDanishInputAllowedBundleIDs.contains(application.bundleID)
    }

    private func setSmartDanishEnabled(_ isEnabled: Bool, for application: RecentApplicationContext) {
        if isEnabled {
            appState.store.addSmartDanishInputAllowedBundleID(application.bundleID)
        } else {
            appState.store.removeSmartDanishInputAllowedBundleID(application.bundleID)
        }
    }

    private func matchedWebsiteRule(for domain: String) -> WebsiteLayoutRule? {
        appState.store.configuration.websiteRules.first {
            domain == $0.domain || domain.hasSuffix("." + $0.domain)
        }
    }

    private func websiteRuleSelection(for domain: String) -> String {
        guard let rule = matchedWebsiteRule(for: domain), rule.isEnabled else { return "none" }
        return "profile:\(rule.profileID.uuidString)"
    }

    private func setWebsiteRuleSelection(_ selection: String, for domain: String) {
        if selection == "none" {
            if let rule = matchedWebsiteRule(for: domain) {
                appState.store.deleteWebsiteRule(id: rule.id)
            }
            return
        }
        guard selection.hasPrefix("profile:"),
              let profileID = UUID(uuidString: String(selection.dropFirst("profile:".count))) else {
            return
        }

        if var rule = matchedWebsiteRule(for: domain) {
            rule.profileID = profileID
            rule.isEnabled = true
            appState.store.upsertWebsiteRule(rule)
        } else {
            appState.store.upsertWebsiteRule(WebsiteLayoutRule(domain: domain, profileID: profileID))
        }
    }
}

private extension View {
    func homeCardStyle() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
