import LayoutPilotCore
import SwiftUI
import AppKit

struct UnifiedAppConfig: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let rule: ApplicationLayoutRule?
    let isSmartInputEnabled: Bool
}

struct RulesView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var selection: String? // Selected app bundleID
    @State private var ruleSearchText = ""
    @State private var isShowingAppPicker = false
    @State private var draft = ApplicationLayoutRule(
        applicationBundleID: "",
        applicationName: "",
        profileID: UUID(),
        isEnabled: true
    )

    // Unifies layout rules and smart input allowed bundle IDs
    var unifiedConfigs: [UnifiedAppConfig] {
        var configs: [String: UnifiedAppConfig] = [:]
        
        // 1. Add from rules
        for rule in appState.store.configuration.rules {
            configs[rule.applicationBundleID] = UnifiedAppConfig(
                bundleID: rule.applicationBundleID,
                name: rule.applicationName,
                rule: rule,
                isSmartInputEnabled: appState.store.configuration.smartDanishInputAllowedBundleIDs.contains(rule.applicationBundleID)
            )
        }
        
        // 2. Add from smart input allowed
        for bundleID in appState.store.configuration.smartDanishInputAllowedBundleIDs {
            if configs[bundleID] == nil {
                configs[bundleID] = UnifiedAppConfig(
                    bundleID: bundleID,
                    name: appName(for: bundleID),
                    rule: nil,
                    isSmartInputEnabled: true
                )
            }
        }
        
        let sorted = configs.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        if ruleSearchText.isEmpty {
            return sorted
        }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(ruleSearchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(ruleSearchText)
        }
    }

    var body: some View {
        let _ = appState.store.configuration.rules
        let _ = appState.store.configuration.smartDanishInputAllowedBundleIDs
        let _ = appState.store.configuration.automationEnabled
        
        HStack(spacing: 0) {
            appList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)

            Divider()

            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
        .navigationTitle("Applications")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: appState.store.configuration.rules) { _, _ in
            ensureSelection()
        }
        .onChange(of: appState.store.configuration.smartDanishInputAllowedBundleIDs) { _, _ in
            ensureSelection()
        }
        .onChange(of: selection) { _, newValue in
            loadDraft(for: newValue)
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Configured Apps")
                    .font(.headline)
                Spacer()
                Button {
                    isShowingAppPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add application settings")
                .sheet(isPresented: $isShowingAppPicker) {
                    AppPickerView(
                        onSelect: { app in
                            addRule(for: app)
                            isShowingAppPicker = false
                        },
                        onCancel: {
                            isShowingAppPicker = false
                        },
                        profileChoices: appState.store.configuration.profiles
                    )
                    .frame(width: 450, height: 500)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter applications...", text: $ruleSearchText)
                    .textFieldStyle(.plain)
                if !ruleSearchText.isEmpty {
                    Button {
                        ruleSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: $selection) {
                ForEach(unifiedConfigs) { config in
                    HStack(spacing: 8) {
                        AppIconView(bundleID: config.bundleID, size: 24)
                        
                        let isAutoSwitchingGloballyEnabled = appState.store.configuration.automationEnabled
                        let isAutoSwitchingActive = (config.rule?.isEnabled ?? false) && isAutoSwitchingGloballyEnabled
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.name.isEmpty ? config.bundleID : config.name)
                                .lineLimit(1)
                                .foregroundColor(isAutoSwitchingActive || config.isSmartInputEnabled ? .primary : .secondary)
                            
                            if let rule = config.rule, rule.isEnabled {
                                Text(isAutoSwitchingGloballyEnabled ? targetName(for: rule) : "\(targetName(for: rule)) (Suspended)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("No auto-switching")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        // 1-Click Auto-Switching Toggle Button
                        Image(systemName: "arrow.triangle.2.circlepath.keyboard")
                            .font(.body)
                            .foregroundColor(isAutoSwitchingActive ? .orange : .secondary.opacity(0.4))
                            .onTapGesture {
                                toggleLayoutSwitch(for: config, enabled: !(config.rule?.isEnabled ?? false))
                            }
                            .help((config.rule?.isEnabled ?? false) ? "Disable Auto-Switching" : "Enable Auto-Switching")
                        
                        // 1-Click Smart Input Toggle Button
                        Image(systemName: "keyboard")
                            .font(.body)
                            .foregroundColor(config.isSmartInputEnabled ? .blue : .secondary.opacity(0.4))
                            .onTapGesture {
                                toggleSmartInput(for: config, enabled: !config.isSmartInputEnabled)
                            }
                            .help(config.isSmartInputEnabled ? "Disable Smart Danish Input" : "Enable Smart Danish Input")
                    }
                    .tag(Optional(config.bundleID))
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPanel: some View {
        Group {
            if let selectedConfig = selectedConfig {
                RuleEditorView(
                    rule: $draft,
                    isSmartInputEnabled: Binding(
                        get: { appState.store.configuration.smartDanishInputAllowedBundleIDs.contains(selectedConfig.bundleID) },
                        set: { newValue in
                            if newValue {
                                appState.store.addSmartDanishInputAllowedBundleID(selectedConfig.bundleID)
                            } else {
                                appState.store.removeSmartDanishInputAllowedBundleID(selectedConfig.bundleID)
                            }
                        }
                    ),
                    profileChoices: appState.store.configuration.profiles,
                    onDelete: {
                        if let rule = selectedConfig.rule {
                            appState.store.deleteRule(id: rule.id)
                        }
                        appState.store.removeSmartDanishInputAllowedBundleID(selectedConfig.bundleID)
                        selection = unifiedConfigs.first(where: { $0.bundleID != selectedConfig.bundleID })?.bundleID
                    }
                )
                .onChange(of: draft) { _, updatedRule in
                    if updatedRule.applicationBundleID == selectedConfig.bundleID {
                        let original = appState.store.configuration.rules.first(where: { $0.applicationBundleID == selectedConfig.bundleID })
                        if original != updatedRule {
                            appState.store.upsertRule(updatedRule)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No App Selected",
                    systemImage: "app.badge",
                    description: Text("Select a configured application or add a new one.")
                )
            }
        }
    }

    private var selectedConfig: UnifiedAppConfig? {
        guard let selection else { return nil }
        return unifiedConfigs.first(where: { $0.bundleID == selection })
    }

    private func ensureSelection() {
        if selection == nil {
            selection = unifiedConfigs.first?.bundleID
        }
        loadDraft(for: selection)
    }

    private func loadDraft(for selection: String?) {
        guard let selection,
              let config = unifiedConfigs.first(where: { $0.bundleID == selection }) else {
            return
        }
        if let rule = config.rule {
            draft = rule
        } else {
            // Load a mock draft rule if layout switching is disabled
            let defaultProfileID = appState.store.configuration.profiles.first?.id ?? UUID()
            draft = ApplicationLayoutRule(
                id: UUID(),
                applicationBundleID: config.bundleID,
                applicationName: config.name,
                profileID: defaultProfileID,
                isEnabled: false
            )
        }
    }

    private func addRule(for app: AppInfo) {
        let defaultProfileID = appState.store.configuration.profiles.first?.id ?? UUID()
        let newRule = ApplicationLayoutRule(
            applicationBundleID: app.bundleID,
            applicationName: app.name,
            profileID: defaultProfileID,
            isEnabled: true
        )
        appState.store.upsertRule(newRule)
        selection = app.bundleID
        draft = newRule
    }

    private func targetName(for rule: ApplicationLayoutRule) -> String {
        switch rule.target {
        case .profile:
            return appState.store.profile(for: rule.profileID)?.name ?? "Missing profile"
        case .lastUsed:
            return "Last Used"
        }
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    // Toggle layout switching directly from list
    private func toggleLayoutSwitch(for config: UnifiedAppConfig, enabled: Bool) {
        if let rule = config.rule {
            var updated = rule
            updated.isEnabled = enabled
            appState.store.upsertRule(updated)
            if selection == config.bundleID {
                draft = updated
            }
        } else if enabled {
            let defaultProfileID = appState.store.configuration.profiles.first?.id ?? UUID()
            let newRule = ApplicationLayoutRule(
                applicationBundleID: config.bundleID,
                applicationName: config.name,
                profileID: defaultProfileID,
                isEnabled: true
            )
            appState.store.upsertRule(newRule)
            if selection == config.bundleID {
                draft = newRule
            }
        }
    }

    // Toggle smart input directly from list
    private func toggleSmartInput(for config: UnifiedAppConfig, enabled: Bool) {
        if enabled {
            appState.store.addSmartDanishInputAllowedBundleID(config.bundleID)
        } else {
            appState.store.removeSmartDanishInputAllowedBundleID(config.bundleID)
        }
    }
}

private struct RuleEditorView: View {
    @Binding var rule: ApplicationLayoutRule
    @Binding var isSmartInputEnabled: Bool
    let profileChoices: [InputLayoutProfile]
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Premium App Header Card
                HStack(spacing: 16) {
                    AppIconView(bundleID: rule.applicationBundleID, size: 64)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.applicationName.isEmpty ? "Application Rule" : rule.applicationName)
                            .font(.title2.weight(.bold))
                        
                        HStack(spacing: 6) {
                            Text(rule.applicationBundleID.isEmpty ? "No Bundle ID" : rule.applicationBundleID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !rule.applicationBundleID.isEmpty {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(rule.applicationBundleID, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                                .help("Copy bundle ID")
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
                
                // Profile Missing Warning Banner
                if rule.isEnabled && rule.target == .profile && !profileChoices.contains(where: { $0.id == rule.profileID }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic Switching Inactive")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("The layout profile previously assigned to this rule has been deleted. Automatic layout switching is currently disabled for this app until a profile is selected below.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }

                // Auto-Switching Settings Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Automatic Layout Switching")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $rule.isEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    if rule.isEnabled {
                        Picker("Switch To", selection: $rule.target) {
                            Text("Layout Profile").tag(ApplicationLayoutRuleTarget.profile)
                            Text("Last Used").tag(ApplicationLayoutRuleTarget.lastUsed)
                        }
                        .pickerStyle(.segmented)

                        if rule.target == .profile {
                            Picker("Target Layout Profile", selection: $rule.profileID) {
                                if !profileChoices.contains(where: { $0.id == rule.profileID }) {
                                    Text("Profile Not Configured").tag(rule.profileID)
                                }
                                ForEach(profileChoices) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        Text("Keyboard layout switching is suspended for this app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                // Smart Danish Input Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Danish Input")
                                .font(.headline)
                            Text("Enable key-combinations (;, ', [) to automatically replace Danish letters in this app.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isSmartInputEnabled)
                            .toggleStyle(.switch)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                // Advanced App Details Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("Advanced Details")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Application Display Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $rule.applicationName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bundle Identifier")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Bundle Identifier", text: $rule.applicationBundleID)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true) // Bundle ID is fixed for unified configs
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                // Unified Actions Card
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Remove App Settings")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            .padding(.trailing, 4)
        }
    }
}

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let url: URL?
    let isRunning: Bool
    
    func icon() -> NSImage {
        if let url = url {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return runningApp.icon ?? NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
        }
        return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
    }
    
    static func discoverApplications() -> [AppInfo] {
        var apps: [AppInfo] = []
        let fileManager = FileManager.default
        
        // 1. Add running apps
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        var seenBundleIDs = Set<String>()
        
        for app in running {
            if let name = app.localizedName, let bundleID = app.bundleIdentifier {
                seenBundleIDs.insert(bundleID)
                apps.append(AppInfo(
                    name: name,
                    bundleID: bundleID,
                    url: app.bundleURL,
                    isRunning: true
                ))
            }
        }
        
        // 2. Scan standard directories
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        for path in searchPaths {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { continue }
            for item in contents {
                if item.hasSuffix(".app") {
                    let appPath = (path as NSString).appendingPathComponent(item)
                    let appURL = URL(fileURLWithPath: appPath)
                    
                    let infoPlistPath = appURL.appendingPathComponent("Contents/Info.plist")
                    guard fileManager.fileExists(atPath: infoPlistPath.path) else { continue }
                    
                    if let dict = NSDictionary(contentsOf: infoPlistPath),
                       let bundleID = dict["CFBundleIdentifier"] as? String {
                        
                        if seenBundleIDs.contains(bundleID) { continue }
                        seenBundleIDs.insert(bundleID)
                        
                        let name = (dict["CFBundleDisplayName"] as? String) ??
                                   (dict["CFBundleName"] as? String) ??
                                   appURL.deletingPathExtension().lastPathComponent
                        
                        apps.append(AppInfo(
                            name: name,
                            bundleID: bundleID,
                            url: appURL,
                            isRunning: false
                        ))
                    }
                }
            }
        }
        
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 20
    
    var body: some View {
        if let icon = appIcon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(.secondary)
        }
    }
    
    private func appIcon(for bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return running.icon
        }
        return nil
    }
}

struct AppPickerView: View {
    let onSelect: (AppInfo) -> Void
    let onCancel: () -> Void
    let profileChoices: [InputLayoutProfile]
    
    @State private var searchText = ""
    @State private var allApps: [AppInfo] = []
    @State private var isLoading = true
    
    @State private var customName = ""
    @State private var customBundleID = ""
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return allApps
        }
        return allApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Application")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Main Content
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Scanning applications...")
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    // Custom Selection row
                    Section {
                        Button(action: selectFromDisk) {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Select App from Disk...")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text("Browse and select any .app package using Finder")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if !searchText.isEmpty && filteredApps.isEmpty {
                        Section("No Results") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No apps found matching \"\(searchText)\".")
                                    .foregroundColor(.secondary)
                                
                                Divider()
                                
                                Text("Create Custom App Rule:")
                                    .font(.headline)
                                    .padding(.top, 4)
                                
                                TextField("App Name (e.g. My App)", text: $customName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Bundle ID (e.g. com.example.app)", text: $customBundleID)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button("Add Custom App Rule") {
                                    let app = AppInfo(
                                        name: customName.isEmpty ? customBundleID : customName,
                                        bundleID: customBundleID,
                                        url: nil,
                                        isRunning: false
                                    )
                                    onSelect(app)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(.vertical, 8)
                        }
                    } else {
                        // Running Apps Section
                        let runningApps = filteredApps.filter { $0.isRunning }
                        if !runningApps.isEmpty {
                            Section("Running Applications") {
                                ForEach(runningApps) { app in
                                    AppPickerRow(app: app) {
                                        onSelect(app)
                                    }
                                }
                            }
                        }
                        
                        // Installed Apps Section
                        let installedApps = filteredApps.filter { !$0.isRunning }
                        if !installedApps.isEmpty {
                            Section("Installed Applications") {
                                ForEach(installedApps) { app in
                                    AppPickerRow(app: app) {
                                        onSelect(app)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let apps = AppInfo.discoverApplications()
                DispatchQueue.main.async {
                    self.allApps = apps
                    self.isLoading = false
                }
            }
        }
    }
    
    private func selectFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url),
               let bundleID = bundle.bundleIdentifier {
                let name = url.deletingPathExtension().lastPathComponent
                let app = AppInfo(name: name, bundleID: bundleID, url: url, isRunning: false)
                onSelect(app)
            } else {
                let infoPlistPath = url.appendingPathComponent("Contents/Info.plist")
                if let dict = NSDictionary(contentsOf: infoPlistPath),
                   let bundleID = dict["CFBundleIdentifier"] as? String {
                    let name = (dict["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                    let app = AppInfo(name: name, bundleID: bundleID, url: url, isRunning: false)
                    onSelect(app)
                }
            }
        }
    }
}

struct AppPickerRow: View {
    let app: AppInfo
    @State private var isHovered = false
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon())
                .resizable()
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if app.isRunning {
                Text("Running")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }
}
