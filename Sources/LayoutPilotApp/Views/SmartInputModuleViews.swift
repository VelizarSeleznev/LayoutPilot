import LayoutPilotCore
import SwiftUI

struct SmartDanishModuleView: View {
    @Bindable var appState: LayoutPilotAppState

    var body: some View {
        SmartInputModulePage(
            title: "Smart Danish",
            summary: "Type æ, ø, and å without changing your familiar keyboard layout.",
            symbol: "character.textbox",
            isActive: Binding(
                get: { appState.store.configuration.smartDanishInputEnabled },
                set: { appState.store.setSmartDanishInputEnabled($0) }
            ),
            appliesToAll: Binding(
                get: { appState.store.configuration.smartDanishApplyToAll },
                set: { appState.store.setSmartDanishApplyToAll($0) }
            ),
            allowedBundleIDs: appState.store.configuration.smartDanishInputAllowedBundleIDs,
            applications: applicationChoices
        ) { bundleID, enabled in
            if enabled {
                appState.store.addSmartDanishInputAllowedBundleID(bundleID)
            } else {
                appState.store.removeSmartDanishInputAllowedBundleID(bundleID)
            }
        }
        .navigationTitle("Smart Danish")
    }

    private var applicationChoices: [ModuleApplicationChoice] {
        applicationChoicesFor(appState: appState, configured: appState.store.configuration.smartDanishInputAllowedBundleIDs)
    }
}

struct SmartBilingualModuleView: View {
    @Bindable var appState: LayoutPilotAppState

    var body: some View {
        SmartInputModulePage(
            title: "Smart RU/EN",
            summary: "Repair Russian and English words typed in the wrong keyboard layout.",
            symbol: "character.book.closed",
            isActive: Binding(
                get: { appState.store.configuration.smartBilingualEnabled },
                set: { appState.store.setSmartBilingualEnabled($0) }
            ),
            appliesToAll: Binding(
                get: { appState.store.configuration.smartBilingualApplyToAll },
                set: { appState.store.setSmartBilingualApplyToAll($0) }
            ),
            allowedBundleIDs: appState.store.configuration.smartBilingualAllowedBundleIDs,
            applications: applicationChoices,
            additionalSettings: AnyView(
                Stepper(value: Binding(
                    get: { appState.store.configuration.smartBilingualUndoDelay },
                    set: { appState.store.setSmartBilingualUndoDelay($0) }
                ), in: 0.5...5.0, step: 0.1) {
                    Text(String(format: "Undo window: %.1f seconds", appState.store.configuration.smartBilingualUndoDelay))
                }
            )
        ) { bundleID, enabled in
            if enabled {
                appState.store.addSmartBilingualAllowedBundleID(bundleID)
            } else {
                appState.store.removeSmartBilingualAllowedBundleID(bundleID)
            }
        }
        .navigationTitle("Smart RU/EN")
    }

    private var applicationChoices: [ModuleApplicationChoice] {
        applicationChoicesFor(appState: appState, configured: appState.store.configuration.smartBilingualAllowedBundleIDs)
    }
}

private struct SmartInputModulePage: View {
    let title: String
    let summary: String
    let symbol: String
    @Binding var isActive: Bool
    @Binding var appliesToAll: Bool
    let allowedBundleIDs: [String]
    let applications: [ModuleApplicationChoice]
    var additionalSettings: AnyView? = nil
    let setApplicationEnabled: (String, Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.largeTitle.weight(.semibold))
                        Text(summary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Active", isOn: $isActive)
                        .toggleStyle(.switch)
                }

                GroupBox("Availability") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use in every supported application", isOn: $appliesToAll)
                        if !appliesToAll {
                            Divider()
                            if applications.isEmpty {
                                Text("Applications appear here after you use them.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(applications) { application in
                                    Toggle(isOn: Binding(
                                        get: { allowedBundleIDs.contains(application.bundleID) },
                                        set: { setApplicationEnabled(application.bundleID, $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(application.name)
                                            Text(application.bundleID)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                if let additionalSettings {
                    GroupBox("Behavior") {
                        additionalSettings.padding(8)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }
}

private struct ModuleApplicationChoice: Identifiable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
}

@MainActor
private func applicationChoicesFor(
    appState: LayoutPilotAppState,
    configured: [String]
) -> [ModuleApplicationChoice] {
    var names: [String: String] = [:]
    for app in appState.engine.recentApplications {
        names[app.bundleID] = app.applicationName
    }
    if let app = appState.engine.lastExternalApplication {
        names[app.bundleID] = app.applicationName
    }
    for rule in appState.store.configuration.rules {
        names[rule.applicationBundleID] = rule.applicationName
    }
    for bundleID in configured where names[bundleID] == nil {
        names[bundleID] = bundleID
    }
    return names.compactMap { bundleID, name in
        guard !TextSnippetPolicy.securityExcludedBundleIDs.contains(bundleID) else { return nil }
        return ModuleApplicationChoice(name: name, bundleID: bundleID)
    }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
