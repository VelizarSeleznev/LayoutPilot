import SwiftUI
import LayoutPilotCore

struct MenuBarView: View {
    @Bindable var appState: LayoutPilotAppState
    @Environment(\.openWindow) private var openWindow

    var activeAppName: String {
        appState.engine.snapshot.frontmostApplicationName
    }
    
    var activeBundleID: String {
        appState.engine.snapshot.frontmostBundleID
    }

    var isSmartInputEnabledForActiveApp: Bool {
        appState.store.configuration.smartDanishInputAllowedBundleIDs.contains(activeBundleID)
    }

    var isAutoSwitchActive: Bool {
        activeAppRule()?.isEnabled ?? false
    }

    var body: some View {
        Group {
            // Context Header
            Text("Active App: \(activeAppName)")
                .font(.headline)
            Text(activeBundleID)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            
            Divider()
            
            // 1. Auto-Switch Submenu for Active App
            Menu {
                Button(action: {
                    removeAutoSwitchForActiveApp()
                }) {
                    Text(!isAutoSwitchActive ? "✓ None (Do Not Switch)" : "   None (Do Not Switch)")
                }
                
                Divider()
                
                ForEach(appState.store.configuration.profiles) { profile in
                    let isSelected = isAutoSwitchActive && activeAppRule()?.profileID == profile.id
                    Button(action: {
                        setAutoSwitchForActiveApp(profileID: profile.id)
                    }) {
                        Text(isSelected ? "✓ \(profile.name)" : "   \(profile.name)")
                    }
                }
            } label: {
                let currentProfileName = isAutoSwitchActive
                    ? (appState.store.configuration.profiles.first { $0.id == activeAppRule()?.profileID }?.name ?? "Unknown")
                    : "None"
                Label("Auto-Switch Layout: \(currentProfileName)", systemImage: "arrow.triangle.2.circlepath.keyboard")
            }
            
            // 2. Smart Danish Input checkmark toggle for Active App
            Button {
                toggleSmartInputForActiveApp()
            } label: {
                Label(
                    isSmartInputEnabledForActiveApp ? "Smart Danish Input: ON" : "Smart Danish Input: OFF",
                    systemImage: isSmartInputEnabledForActiveApp ? "checkmark.circle.fill" : "keyboard"
                )
            }

            Divider()
            
            // Global Controls
            Toggle("Global Auto-Switching", isOn: Binding(
                get: { appState.store.configuration.automationEnabled },
                set: { appState.store.setAutomationEnabled($0) }
            ))

            Toggle("Global Smart Danish Input", isOn: Binding(
                get: { appState.store.configuration.smartDanishInputEnabled },
                set: { appState.store.setSmartDanishInputEnabled($0) }
            ))

            Divider()

            Button {
                openWindow(id: "main")
            } label: {
                Label("Open Settings Dashboard...", systemImage: "rectangle.stack")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit LayoutPilot", systemImage: "power")
            }
        }
    }

    private func activeAppRule() -> ApplicationLayoutRule? {
        appState.store.configuration.rules.first { $0.applicationBundleID == activeBundleID }
    }

    private func setAutoSwitchForActiveApp(profileID: UUID) {
        let rule = ApplicationLayoutRule(
            applicationBundleID: activeBundleID,
            applicationName: activeAppName,
            profileID: profileID,
            isEnabled: true
        )
        appState.store.upsertRule(rule)
        appState.engine.refreshNow()
    }

    private func removeAutoSwitchForActiveApp() {
        if let rule = activeAppRule() {
            var updated = rule
            updated.isEnabled = false
            appState.store.upsertRule(updated)
            appState.engine.refreshNow()
        }
    }

    private func toggleSmartInputForActiveApp() {
        if isSmartInputEnabledForActiveApp {
            appState.store.removeSmartDanishInputAllowedBundleID(activeBundleID)
        } else {
            appState.store.addSmartDanishInputAllowedBundleID(activeBundleID)
        }
        appState.engine.refreshNow()
    }
}
