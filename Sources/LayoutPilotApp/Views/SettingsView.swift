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

                Toggle("Launch at login", isOn: Binding(
                    get: { appState.store.configuration.launchAtLogin },
                    set: { appState.store.setLaunchAtLogin($0) }
                ))
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Toggle("LLM enabled", isOn: Binding(
                    get: { appState.store.configuration.llm.isEnabled },
                    set: { appState.store.setLLMEnabled($0) }
                ))

                TextField("Endpoint URL", text: Binding(
                    get: { appState.store.configuration.llm.endpointURL },
                    set: { appState.store.setLLMEndpointURL($0) }
                ))

                TextField("Model", text: Binding(
                    get: { appState.store.configuration.llm.model },
                    set: { appState.store.setLLMModel($0) }
                ))
            }
            .tabItem {
                Label("LLM", systemImage: "brain.head.profile")
            }
        }
        .frame(width: 520, height: 320)
        .scenePadding()
    }
}

