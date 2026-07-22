import LayoutPilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: LayoutPilotAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose how LayoutPilot behaves across your Mac.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("General") {
                    Toggle("Show menu bar item", isOn: Binding(
                        get: { appState.store.configuration.showMenuBarItem },
                        set: { appState.store.setShowMenuBarItem($0) }
                    ))

                    Button("Choose Modules…") {
                        appState.selectedSidebarSection = .overview
                    }
                }

                if appState.store.configuration.isModuleAdded(.layoutSwitching) {
                    Section("Layout Switching") {
                        Toggle("Automatic switching", isOn: Binding(
                            get: { appState.store.configuration.automationEnabled },
                            set: { appState.store.setAutomationEnabled($0) }
                        ))

                        Toggle("Auto-switch layout in every app", isOn: Binding(
                            get: { appState.store.configuration.defaultAutoSwitchEnabled },
                            set: { appState.store.setDefaultAutoSwitchEnabled($0) }
                        ))

                        Toggle("Instant Globe switching", isOn: Binding(
                            get: { appState.store.configuration.instantGlobeSwitchingEnabled },
                            set: { appState.store.setInstantGlobeSwitchingEnabled($0) }
                        ))

                        if appState.store.configuration.instantGlobeSwitchingEnabled {
                            Text("Globe becomes a dedicated layout key. LayoutPilot switches on press and sets the macOS Globe action to Do Nothing, preventing a second system switch or voice input.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }

                        if appState.store.configuration.defaultAutoSwitchEnabled {
                            Picker("Default switches to", selection: Binding(
                                get: { defaultAutoSwitchSelection },
                                set: { setDefaultAutoSwitchSelection($0) }
                            )) {
                                Text("Last Used").tag("lastUsed")
                                ForEach(appState.store.configuration.profiles) { profile in
                                    Text(profile.name).tag("profile:\(profile.id.uuidString)")
                                }
                            }
                            .padding(.leading, 16)

                            Text("Applies to apps without their own rule. Disable auto-switching on a specific app to opt it out.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }

                    }
                }

                if appState.store.configuration.isModuleAdded(.smartBilingual) {
                    Section("Writing Assistance") {
                        Toggle("Spelling Autocorrect", isOn: Binding(
                            get: { appState.store.configuration.spellingAutocorrectEnabled },
                            set: { appState.store.setSpellingAutocorrectEnabled($0) }
                        ))
                    }
                }

                Section("Startup") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { appState.store.configuration.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch item status: \(appState.launchAtLoginState.statusDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.launchAtLoginState.requiresApproval {
                            Text("Approve LayoutPilot in System Settings > General > Login Items.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if let errorMessage = appState.launchAtLoginState.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Remote Experiment") {
                    if appState.store.configuration.remotePrankPackEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote prank pack is enabled on this install.")
                                .font(.headline)
                            if appState.store.configuration.appliedRemotePrankPackID != nil {
                                Text("A remote prank pack has already been handled for this install.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("If the remote manifest is available, it will be applied once and cannot be changed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Disable & Remove Remote Pack") {
                                appState.disableAndRemoveRemotePrankPack()
                                appState.syncAnonymousUsageReporting()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .foregroundStyle(.red)
                            .tint(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote prank pack has been disabled for this install.")
                                .font(.headline)
                            if let campaignID = appState.store.configuration.appliedRemotePrankPackID,
                               !campaignID.isEmpty {
                                Text("A previous pack was handled and cannot be re-applied.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle("Send anonymous usage statistics", isOn: Binding(
                        get: { appState.store.configuration.anonymousUsageStatisticsEnabled },
                        set: { appState.store.setAnonymousUsageStatisticsEnabled($0) }
                    ))

                    Text("No exact replacement text, raw password, device identifier, or bundle IDs are sent. Rejected words are sanitized and sent only for non-browser apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(28)
        .navigationTitle("Settings")
    }

    private var defaultAutoSwitchSelection: String {
        switch appState.store.configuration.defaultAutoSwitchTarget {
        case .lastUsed:
            return "lastUsed"
        case .profile:
            if let id = appState.store.configuration.defaultAutoSwitchProfileID {
                return "profile:\(id.uuidString)"
            }
            return "lastUsed"
        }
    }

    private func setDefaultAutoSwitchSelection(_ selection: String) {
        if selection == "lastUsed" {
            appState.store.setDefaultAutoSwitchTarget(.lastUsed)
            return
        }
        if selection.hasPrefix("profile:"),
           let id = UUID(uuidString: String(selection.dropFirst("profile:".count))) {
            appState.store.setDefaultAutoSwitchProfileID(id)
            appState.store.setDefaultAutoSwitchTarget(.profile)
        }
    }
}
