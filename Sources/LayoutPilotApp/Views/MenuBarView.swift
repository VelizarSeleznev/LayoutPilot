import AppKit
import LayoutPilotCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: LayoutPilotAppState
    @Environment(\.openWindow) private var openWindow
    @State private var showsQuickSnippet = false
    @State private var quickSnippetTrigger = ""
    @State private var quickSnippetText = ""
    @State private var quickSnippetError: String?
    @FocusState private var focusedQuickSnippetField: QuickSnippetField?

    private var activeApplication: RecentApplicationContext? {
        appState.engine.lastExternalApplication
    }

    private var hasSnippetsModule: Bool {
        appState.store.configuration.isModuleAdded(.snippets)
    }

    private var activeMenuBarModules: [FeatureModule] {
        let configuration = appState.store.configuration
        return configuration.menuBarModuleOrder.filter(configuration.addedModules.contains)
    }

    private var activeSmartMenuBarModules: [FeatureModule] {
        activeMenuBarModules.filter { module in
            module == .smartBilingual || module == .smartDanish
        }
    }

    private var hasContextControls: Bool {
        let modules = Set(activeMenuBarModules)
        return modules.contains(.layoutSwitching)
            || modules.contains(.smartDanish)
            || modules.contains(.smartBilingual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masterHeader

            if hasContextControls, let application = activeApplication {
                Divider()
                applicationSection(application)
            } else if hasContextControls {
                Divider()
                ContentUnavailableView(
                    "No Recent App",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Switch to another app to configure it.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            if hasSnippetsModule {
                Divider()
                quickSnippetSection
            }

            Divider()
            actionSection
        }
        .padding(.vertical, 8)
        .frame(width: 340)
        .onChange(of: hasSnippetsModule) { _, isAdded in
            if !isAdded {
                closeQuickSnippet()
            }
        }
        .onAppear {
            appState.engine.refreshNow()
            appState.engine.refreshWebsiteNow()
        }
    }

    private var masterHeader: some View {
        HStack(spacing: 12) {
            Text("LayoutPilot")
                .font(.title3.weight(.semibold))
            Spacer()
            if appState.store.configuration.isModuleAdded(.layoutSwitching) {
                Toggle("Automatic switching", isOn: Binding(
                    get: { appState.store.configuration.automationEnabled },
                    set: { appState.store.setAutomationEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var quickSnippetSection: some View {
        if showsQuickSnippet {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Trigger", text: $quickSnippetTrigger, prompt: Text(";sig"))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .frame(width: 82)
                        .focused($focusedQuickSnippetField, equals: .trigger)
                        .onSubmit {
                            focusedQuickSnippetField = .replacement
                        }

                    TextField("Text", text: $quickSnippetText, prompt: Text("Replacement"))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .focused($focusedQuickSnippetField, equals: .replacement)
                        .onSubmit {
                            addQuickSnippet()
                        }

                    Button(action: addQuickSnippet) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canAddQuickSnippet)
                    .help("Add snippet")
                    .accessibilityLabel("Add snippet")

                    Button(action: closeQuickSnippet) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Cancel")
                    .accessibilityLabel("Cancel adding snippet")
                }

                if let quickSnippetError {
                    Text(quickSnippetError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else {
            MenuActionRow(title: "Add Global Snippet", symbol: "text.badge.plus") {
                showsQuickSnippet = true
                quickSnippetError = nil
                Task { @MainActor in
                    await Task.yield()
                    focusedQuickSnippetField = .trigger
                }
            }
            .padding(6)
        }
    }

    private var canAddQuickSnippet: Bool {
        !quickSnippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !quickSnippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addQuickSnippet() {
        guard canAddQuickSnippet else { return }
        let snippet = TextSnippet(
            name: "",
            trigger: quickSnippetTrigger,
            replacement: quickSnippetText
        )
        switch appState.store.saveTextSnippet(snippet) {
        case .success:
            closeQuickSnippet()
        case .failure(let error):
            quickSnippetError = error.localizedDescription
        }
    }

    private func closeQuickSnippet() {
        showsQuickSnippet = false
        quickSnippetTrigger = ""
        quickSnippetText = ""
        quickSnippetError = nil
        focusedQuickSnippetField = nil
    }

    @ViewBuilder
    private func smartModuleRow(
        _ module: FeatureModule,
        application: RecentApplicationContext
    ) -> some View {
        switch module {
        case .smartBilingual:
            MenuToggleRow(
                title: "Smart RU/EN",
                symbol: "character.book.closed",
                isOn: isSmartBilingualEnabled(for: application)
            ) {
                setSmartBilingualEnabled(!isSmartBilingualEnabled(for: application), for: application)
            }
        case .smartDanish:
            MenuToggleRow(
                title: "Smart Danish",
                symbol: "character.textbox",
                isOn: isSmartDanishEnabled(for: application)
            ) {
                setSmartDanishEnabled(!isSmartDanishEnabled(for: application), for: application)
            }
        case .layoutSwitching, .snippets:
            EmptyView()
        }
    }

    private func applicationSection(_ application: RecentApplicationContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                AppIconView(bundleID: application.bundleID, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.applicationName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Controls for this app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                if appState.store.configuration.isModuleAdded(.layoutSwitching) {
                    VStack(alignment: .center, spacing: 1) {
                        Text("Default layout")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("Default layout for \(application.applicationName)", selection: Binding(
                            get: { autoSwitchSelection(for: application) },
                            set: { setAutoSwitchSelection($0, for: application) }
                        )) {
                            Text("No Override").tag("none")
                            Text("Last Used").tag("lastUsed")
                            Divider()
                            ForEach(appState.store.configuration.profiles) { profile in
                                Text(profile.name).tag("profile:\(profile.id.uuidString)")
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 118)
                        .accessibilityLabel("Default layout for \(application.applicationName)")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if appState.store.configuration.isModuleAdded(.layoutSwitching),
               let domain = appState.engine.activeWebsiteDomain {
                websiteSection(domain: domain)
            }

            ForEach(activeSmartMenuBarModules) { module in
                smartModuleRow(module, application: application)
            }
        }
        .padding(.bottom, 6)
    }

    private func websiteSection(domain: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(domain)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Current website")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            pickerRow(
                title: "Site Layout",
                systemImage: "keyboard",
                selection: Binding(
                    get: { websiteRuleSelection(for: domain) },
                    set: { setWebsiteRuleSelection($0, for: domain) }
                ),
                includesLastUsed: false,
                inheritedTitle: "Use App Layout"
            )
        }
        .padding(.bottom, 8)
    }

    private func pickerRow(
        title: String,
        systemImage: String,
        selection: Binding<String>,
        includesLastUsed: Bool,
        inheritedTitle: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(title)
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
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
            .frame(width: 138)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var actionSection: some View {
        VStack(spacing: 2) {
            MenuActionRow(title: "Open LayoutPilot", symbol: "house") {
                openMainWindow(section: .overview)
            }
            MenuActionRow(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                openMainWindow(section: .settings)
            }
            MenuActionRow(title: "Quit LayoutPilot", symbol: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(6)
    }

    private func openMainWindow(section: SidebarSection) {
        appState.selectedSidebarSection = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
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

private enum QuickSnippetField: Hashable {
    case trigger
    case replacement
}

private struct MenuToggleRow: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
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
        .frame(height: 38)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct MenuActionRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
