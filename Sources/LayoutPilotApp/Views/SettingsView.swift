import LayoutPilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: LayoutPilotAppState

    var body: some View {
        TabView {
            Form {
                Toggle("Automation enabled", isOn: Binding(
                    get: { appState.store.configuration.automationEnabled },
                    set: { appState.store.setAutomationEnabled($0) }
                ))

                Toggle("Show menu bar item", isOn: Binding(
                    get: { appState.store.configuration.showMenuBarItem },
                    set: { appState.store.setShowMenuBarItem($0) }
                ))

                Toggle("Smart Danish Input", isOn: Binding(
                    get: { appState.store.configuration.smartDanishInputEnabled },
                    set: { appState.store.setSmartDanishInputEnabled($0) }
                ))

                Toggle("Smart RU/EN Input", isOn: Binding(
                    get: { appState.store.configuration.smartBilingualEnabled },
                    set: { appState.store.setSmartBilingualEnabled($0) }
                ))

                if appState.store.configuration.smartBilingualEnabled {
                    Stepper(value: Binding(
                        get: { appState.store.configuration.smartBilingualUndoDelay },
                        set: { appState.store.setSmartBilingualUndoDelay($0) }
                    ), in: 0.1...3.0, step: 0.1) {
                        Text(String(format: "Undo delay: %.1f seconds", appState.store.configuration.smartBilingualUndoDelay))
                    }
                    .padding(.leading, 16)
                }

                Section("Defaults for all apps") {
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

                    Toggle("Smart RU/EN autocorrect in every app", isOn: Binding(
                        get: { appState.store.configuration.smartBilingualApplyToAll },
                        set: { appState.store.setSmartBilingualApplyToAll($0) }
                    ))
                    .disabled(!appState.store.configuration.smartBilingualEnabled)

                    Toggle("Smart Danish input in every app", isOn: Binding(
                        get: { appState.store.configuration.smartDanishApplyToAll },
                        set: { appState.store.setSmartDanishApplyToAll($0) }
                    ))
                    .disabled(!appState.store.configuration.smartDanishInputEnabled)
                }

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
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
        }
        .frame(width: 520, height: 440)
        .scenePadding()
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
