import LayoutPilotCore
import SwiftUI
import AppKit

struct OverviewView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var pulseIndicator = false
    @State private var connectionTimer: Timer? = nil
    
    // Live LLM State
    @State private var llmOnline = false
    @State private var llmStatusText = "Checking..."
    
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

                // Dynamic Offline LLM Card
                llmCockpitCard

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
        .onAppear {
            checkLLMConnection()
            
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseIndicator = true
            }
            
            // Check connection every 5.0 seconds
            connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                checkLLMConnection()
            }
        }
        .onDisappear {
            connectionTimer?.invalidate()
            connectionTimer = nil
        }
    }

    // Engine Status
    private var engineStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // Pulsing Active Dot
                Circle()
                    .fill(appState.store.configuration.automationEnabled ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulseIndicator && appState.store.configuration.automationEnabled ? 1.3 : 1.0)
                    .opacity(pulseIndicator && appState.store.configuration.automationEnabled ? 0.7 : 1.0)
                    .animation(appState.store.configuration.automationEnabled ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: pulseIndicator)

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

    // Dynamic Offline LLM Card
    private var llmCockpitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(llmOnline ? .green : .secondary)
                    .padding(8)
                    .background(llmOnline ? Color.green.opacity(0.1) : Color.primary.opacity(0.05))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Local Translation Server")
                            .font(.headline)
                        
                        Circle()
                            .fill(llmOnline ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    
                    Text(llmOnline ? "Connected & Inference Active" : "LM Studio Offline (Launch Server)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !llmOnline {
                    Button(action: launchLMStudio) {
                        Label("Launch LM Studio", systemImage: "arrow.up.forward.app")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: checkLLMConnection) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh connection")
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Server Model")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                    Text(llmStatusText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("API Endpoint")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                    Text(appState.store.configuration.llm.endpointURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
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
    
    // Check local server connection dynamically
    private func checkLLMConnection() {
        guard appState.store.configuration.llm.translationEnabled ?? true else {
            llmOnline = false
            llmStatusText = "Translation Disabled"
            return
        }
        
        let endpoint = appState.store.configuration.llm.endpointURL
        var urlString = endpoint
        if !urlString.hasSuffix("/models") {
            if urlString.hasSuffix("/") {
                urlString += "models"
            } else if urlString.hasSuffix("/v1") {
                urlString += "/models"
            } else {
                urlString += "/v1/models"
            }
        }
        
        guard let url = URL(string: urlString) else {
            llmOnline = false
            llmStatusText = "Invalid Server URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.llmOnline = false
                    self.llmStatusText = "Offline (Click to launch)"
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]],
                   let firstModel = dataArray.first,
                   let modelName = firstModel["id"] as? String {
                    self.llmOnline = true
                    self.llmStatusText = modelName.components(separatedBy: "/").last ?? modelName
                } else {
                    self.llmOnline = true
                    self.llmStatusText = "Inference Active"
                }
            }
        }.resume()
    }
    
    // Interactive startup of LM Studio
    private func launchLMStudio() {
        let bundleIDs = ["ai.element.lmstudio", "com.lmstudio.lmstudio"]
        for bid in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.checkLLMConnection()
                    }
                }
                return
            }
        }
        
        // Custom URL schemas or download page redirects
        if let url = URL(string: "lmstudio://") {
            if NSWorkspace.shared.open(url) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.checkLLMConnection()
                }
                return
            }
        }
        
        if let url = URL(string: "https://lmstudio.ai") {
            NSWorkspace.shared.open(url)
        }
    }
}
