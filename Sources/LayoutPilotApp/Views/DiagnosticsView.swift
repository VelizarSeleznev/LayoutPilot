import LayoutPilotCore
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var appState: LayoutPilotAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        diagnosticsRow(title: "Engine running", value: appState.engine.isRunning ? "Yes" : "No")
                        diagnosticsRow(title: "Configuration file", value: configurationPath)
                        diagnosticsRow(title: "Smart RU/EN Input", value: appState.store.configuration.smartBilingualEnabled ? "Yes" : "No")
                        diagnosticsRow(title: "Smart Danish Input", value: appState.store.configuration.smartDanishInputEnabled ? "Yes" : "No")
                        diagnosticsRow(title: "Automation error", value: appState.engine.lastErrorMessage ?? "None")
                        diagnosticsRow(title: "Store error", value: appState.store.lastErrorMessage ?? "None")
                    }
                }

                GroupBox("Available Input Sources") {
                    let sources = SystemInputSourceClient().availableInputSources()
                    VStack(alignment: .leading, spacing: 8) {
                        if sources.isEmpty {
                            Text("No input sources detected.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sources) { source in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.localizedName)
                                    Text(source.sourceID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Diagnostics")
    }

    private var configurationPath: String {
        (try? LayoutPilotPaths.configurationURL().path) ?? "Unavailable"
    }

    private func diagnosticsRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

