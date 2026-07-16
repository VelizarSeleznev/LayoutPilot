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
