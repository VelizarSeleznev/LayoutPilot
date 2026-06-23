import LayoutPilotCore
import SwiftUI
import AppKit

struct OverviewView: View {
    @Bindable var appState: LayoutPilotAppState


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                        
                        Text("Dashboard")
                            .font(.system(.title, design: .rounded).weight(.bold))
                    }
                    
                    Text("Automated layout switching is active. Watch app rules trigger keyboard layout adjustments in real time below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                }
                .padding(.bottom, 4)

                // Master Engine Status Card
                engineStatusCard

                // Interactive Live Flow Bridge
                liveFlowCard

                // Quick Toggle Settings
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        toggleCard(
                            title: "Smart RU/EN Input",
                            description: "Automatically switches layout and corrects text if typed in the wrong language.",
                            systemImage: "globe",
                            accentColor: .green,
                            isOn: Binding(
                                get: { appState.store.configuration.smartBilingualEnabled },
                                set: { appState.store.setSmartBilingualEnabled($0) }
                            )
                        )

                        toggleCard(
                            title: "Smart Danish Input",
                            description: "Use key combinations (;, ', [) to type Danish chars natively.",
                            systemImage: "keyboard",
                            accentColor: .orange,
                            isOn: Binding(
                                get: { appState.store.configuration.smartDanishInputEnabled },
                                set: { appState.store.setSmartDanishInputEnabled($0) }
                            )
                        )
                    }
                    
                    HStack(spacing: 16) {
                        toggleCard(
                            title: "Menu Bar Icon",
                            description: "Access quick controls and active app settings from the menu bar.",
                            systemImage: "uiwindow.split.2x1",
                            accentColor: .blue,
                            isOn: Binding(
                                get: { appState.store.configuration.showMenuBarItem },
                                set: { appState.store.setShowMenuBarItem($0) }
                            )
                        )
                    }
                }

                // Metric Grid Counters (2 Column Layout)
                metricsGrid
            }
            .padding(.trailing, 4)
        }

    }

    // Engine Status
    private var engineStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // Pulsing Active Dot
                Circle()
                    .fill(appState.store.configuration.automationEnabled ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.store.configuration.automationEnabled ? "Layout Switching Active" : "Layout Switching Suspended")
                        .font(.headline)
                    Text(appState.store.configuration.automationEnabled ? "LayoutPilot automatically adjusts keyboard layouts as you switch between applications." : "Automatic layout switching is currently paused.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { appState.store.configuration.automationEnabled },
                    set: { appState.store.setAutomationEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
            
            if let error = appState.engine.lastErrorMessage ?? appState.store.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // Live Flow Pipeline
    private var liveFlowCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Application Flow")
                .font(.headline)
            
            HStack(spacing: 0) {
                // 1. Active App Card
                VStack(spacing: 12) {
                    AppIconView(bundleID: appState.engine.snapshot.frontmostBundleID, size: 48)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    
                    VStack(spacing: 2) {
                        Text(appState.engine.snapshot.frontmostApplicationName)
                            .font(.body.weight(.bold))
                            .lineLimit(1)
                        Text(appState.engine.snapshot.frontmostBundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(10)
                
                // 2. Connector Flow
                VStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(appState.store.configuration.automationEnabled ? .accentColor : .secondary)
                    
                    Text("Auto Match")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                
                // 3. Current Keyboard Layout Card
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.title)
                        .foregroundColor(.accentColor)
                        .frame(width: 48, height: 48)
                    
                    VStack(spacing: 2) {
                        Text(layoutName(for: appState.engine.snapshot.currentInputSourceID))
                            .font(.body.weight(.bold))
                            .lineLimit(1)
                        Text(appState.engine.snapshot.currentInputSourceID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(10)
            }
            .padding(10)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(12)
            
            // Flow Details Subtitle
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Trigger Status:")
                        .font(.caption.weight(.bold))
                    Text(appState.engine.snapshot.matchedRuleDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent App Settings")
                    .font(.subheadline.weight(.semibold))

                if appState.engine.recentApplications.isEmpty {
                    Text("Switch to an application to edit its quick settings here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(appState.engine.recentApplications) { application in
                            recentApplicationSettingsRow(for: application)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func recentApplicationSettingsRow(for application: RecentApplicationContext) -> some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: application.bundleID, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(application.applicationName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(application.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)

            Picker("Auto-Switch", selection: Binding(
                get: { autoSwitchSelection(for: application) },
                set: { setAutoSwitchSelection($0, for: application) }
            )) {
                Text("None").tag("none")
                Text("Last Used").tag("lastUsed")
                Divider()
                ForEach(appState.store.configuration.profiles) { profile in
                    Text(profile.name).tag("profile:\(profile.id.uuidString)")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)

            Toggle("RU/EN", isOn: Binding(
                get: { isSmartBilingualEnabled(for: application) },
                set: { setSmartBilingualEnabled($0, for: application) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("Danish", isOn: Binding(
                get: { isSmartDanishEnabled(for: application) },
                set: { setSmartDanishEnabled($0, for: application) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // Dynamic layout name translation
    private func layoutName(for sourceID: String) -> String {
        let sources = SystemInputSourceClient().availableInputSources()
        if let source = sources.first(where: { $0.sourceID == sourceID }) {
            return source.localizedName
        }
        if sourceID.hasPrefix("com.apple.keylayout.") {
            return sourceID.replacingOccurrences(of: "com.apple.keylayout.", with: "")
        }
        return sourceID
    }

    private func rule(for application: RecentApplicationContext) -> ApplicationLayoutRule? {
        appState.store.configuration.rules.first { $0.applicationBundleID == application.bundleID }
    }

    private func autoSwitchSelection(for application: RecentApplicationContext) -> String {
        guard let rule = rule(for: application), rule.isEnabled else {
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
            disableAutoSwitch(for: application)
            return
        }

        let fallbackProfileID = rule(for: application)?.profileID ?? appState.store.configuration.profiles.first?.id ?? UUID()
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

    private func disableAutoSwitch(for application: RecentApplicationContext) {
        guard let rule = rule(for: application) else {
            return
        }

        var updated = rule
        updated.isEnabled = false
        appState.store.upsertRule(updated)
        appState.engine.refreshNow()
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
        appState.engine.refreshNow()
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
        appState.engine.refreshNow()
    }

    // Polished Toggle Cards
    private func toggleCard(
        title: String,
        description: String,
        systemImage: String,
        accentColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(isOn.wrappedValue ? accentColor : .secondary)
                
                Spacer()
                
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.bold))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // Stats Grid
    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine Statistics")
                .font(.headline)
            
            HStack(spacing: 16) {
                metricCard(
                    title: "Applications Rules",
                    value: "\(appState.store.configuration.rules.count)",
                    subValue: "\(appState.store.configuration.rules.filter { $0.isEnabled }.count) layout triggers",
                    systemImage: "arrow.triangle.2.circlepath.keyboard",
                    color: .purple
                )
                
                metricCard(
                    title: "Layout Profiles",
                    value: "\(appState.store.configuration.profiles.count)",
                    subValue: "Keyboard presets configured",
                    systemImage: "list.bullet.rectangle",
                    color: .blue
                )
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        subValue: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.title2.weight(.bold))
                
                Text(subValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(color.opacity(0.8))
                .padding(8)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
}
