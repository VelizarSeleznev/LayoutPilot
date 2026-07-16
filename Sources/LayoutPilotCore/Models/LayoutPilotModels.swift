import Foundation

public struct InputLayoutProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var inputSourceID: String
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        inputSourceID: String,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.inputSourceID = inputSourceID
        self.notes = notes
    }
}

public enum ApplicationLayoutRuleTarget: String, Codable, Hashable, Sendable {
    case profile
    case lastUsed
}

public struct ApplicationLayoutRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var applicationBundleID: String
    public var applicationName: String
    public var profileID: UUID
    public var target: ApplicationLayoutRuleTarget
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        applicationBundleID: String,
        applicationName: String,
        profileID: UUID,
        target: ApplicationLayoutRuleTarget = .profile,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.applicationBundleID = applicationBundleID
        self.applicationName = applicationName
        self.profileID = profileID
        self.target = target
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case applicationBundleID
        case applicationName
        case profileID
        case target
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.applicationBundleID = try container.decode(String.self, forKey: .applicationBundleID)
        self.applicationName = try container.decode(String.self, forKey: .applicationName)
        self.profileID = try container.decode(UUID.self, forKey: .profileID)
        self.target = try container.decodeIfPresent(ApplicationLayoutRuleTarget.self, forKey: .target) ?? .profile
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct WebsiteLayoutRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var domain: String
    public var profileID: UUID
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        domain: String,
        profileID: UUID,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.domain = domain
        self.profileID = profileID
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case profileID
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.domain = try container.decode(String.self, forKey: .domain)
        self.profileID = try container.decode(UUID.self, forKey: .profileID)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct RecentApplicationContext: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public var applicationName: String
    public var bundleID: String

    public init(applicationName: String, bundleID: String) {
        self.applicationName = applicationName
        self.bundleID = bundleID
    }
}

public enum FeatureModule: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case snippets
    case smartDanish
    case smartBilingual
    case layoutSwitching

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .snippets: return "Snippets"
        case .smartDanish: return "Smart Danish"
        case .smartBilingual: return "Smart RU/EN"
        case .layoutSwitching: return "Layout Switching"
        }
    }

    public var summary: String {
        switch self {
        case .snippets: return "Expand short triggers into text you use every day."
        case .smartDanish: return "Type Danish characters from a familiar Latin layout."
        case .smartBilingual: return "Repair words typed in the wrong Russian or English layout."
        case .layoutSwitching: return "Choose keyboard layouts for apps and websites."
        }
    }

    public var systemImage: String {
        switch self {
        case .snippets: return "text.badge.plus"
        case .smartDanish: return "character.textbox"
        case .smartBilingual: return "character.book.closed"
        case .layoutSwitching: return "keyboard.badge.ellipsis"
        }
    }
}

public enum SnippetApplicationScopeMode: String, CaseIterable, Codable, Hashable, Sendable {
    case allApplications
    case onlySelected
    case allExceptSelected
}

public struct SnippetApplicationScope: Codable, Hashable, Sendable {
    public var mode: SnippetApplicationScopeMode
    public var bundleIDs: [String]

    public init(mode: SnippetApplicationScopeMode = .allApplications, bundleIDs: [String] = []) {
        self.mode = mode
        self.bundleIDs = Array(Set(bundleIDs.filter { !$0.isEmpty })).sorted()
    }

    public func allows(bundleID: String) -> Bool {
        switch mode {
        case .allApplications:
            return true
        case .onlySelected:
            return bundleIDs.contains(bundleID)
        case .allExceptSelected:
            return !bundleIDs.contains(bundleID)
        }
    }
}

public struct TextSnippetGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var applicationScope: SnippetApplicationScope

    public init(
        id: UUID = UUID(),
        name: String,
        applicationScope: SnippetApplicationScope = SnippetApplicationScope()
    ) {
        self.id = id
        self.name = name
        self.applicationScope = applicationScope
    }
}

public struct TextSnippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: String
    public var replacement: String
    public var isEnabled: Bool
    public var groupID: UUID?
    public var applicationScopeOverride: SnippetApplicationScope?

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        trigger: String,
        replacement: String,
        isEnabled: Bool = true,
        groupID: UUID? = nil,
        applicationScopeOverride: SnippetApplicationScope? = nil
    ) {
        self.id = id
        self.name = name ?? trigger
        self.trigger = trigger
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.groupID = groupID
        self.applicationScopeOverride = applicationScopeOverride
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case trigger
        case replacement
        case isEnabled
        case groupID
        case applicationScopeOverride
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.trigger = try container.decode(String.self, forKey: .trigger)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? self.trigger
        self.replacement = try container.decode(String.self, forKey: .replacement)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        self.applicationScopeOverride = try container.decodeIfPresent(
            SnippetApplicationScope.self,
            forKey: .applicationScopeOverride
        )
    }
}

public enum TextSnippetPolicy {
    public static let securityExcludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.celeste",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    public static func effectiveScope(
        for snippet: TextSnippet,
        groups: [TextSnippetGroup]
    ) -> SnippetApplicationScope {
        if let override = snippet.applicationScopeOverride {
            return override
        }
        if let groupID = snippet.groupID,
           let group = groups.first(where: { $0.id == groupID }) {
            return group.applicationScope
        }
        return SnippetApplicationScope()
    }

    public static func allows(
        _ snippet: TextSnippet,
        in bundleID: String,
        groups: [TextSnippetGroup]
    ) -> Bool {
        !securityExcludedBundleIDs.contains(bundleID)
            && snippet.isEnabled
            && effectiveScope(for: snippet, groups: groups).allows(bundleID: bundleID)
    }
}

public struct LayoutPilotConfiguration: Codable, Hashable, Sendable {
    public static let defaultSmartBilingualUndoDelay = 3.0

    public var automationEnabled: Bool
    public var launchAtLogin: Bool
    public var showMenuBarItem: Bool
    public var smartDanishInputEnabled: Bool
    public var smartDanishInputAllowedBundleIDs: [String]
    public var smartBilingualEnabled: Bool
    public var smartBilingualAllowedBundleIDs: [String]
    public var smartBilingualUndoDelay: Double
    /// When enabled, apps without an explicit rule fall back to `defaultAutoSwitchTarget`.
    public var defaultAutoSwitchEnabled: Bool
    public var defaultAutoSwitchTarget: ApplicationLayoutRuleTarget
    public var defaultAutoSwitchProfileID: UUID?
    /// When enabled, smart RU/EN autocorrection applies to every app (except built-in exclusions).
    public var smartBilingualApplyToAll: Bool
    /// When enabled, smart Danish input applies to every app (except built-in exclusions).
    public var smartDanishApplyToAll: Bool
    public var textSnippetsEnabled: Bool
    public var textSnippets: [TextSnippet]
    public var textSnippetGroups: [TextSnippetGroup]
    public var addedModules: Set<FeatureModule>
    public var moduleSelectionCompleted: Bool
    public var profiles: [InputLayoutProfile]
    public var rules: [ApplicationLayoutRule]
    public var websiteRules: [WebsiteLayoutRule]
    public var spellingAutocorrectEnabled: Bool

    public init(
        automationEnabled: Bool = true,
        launchAtLogin: Bool = false,
        showMenuBarItem: Bool = true,
        smartDanishInputEnabled: Bool = true,
        smartDanishInputAllowedBundleIDs: [String] = [],
        smartBilingualEnabled: Bool = true,
        smartBilingualAllowedBundleIDs: [String] = [],
        smartBilingualUndoDelay: Double = Self.defaultSmartBilingualUndoDelay,
        defaultAutoSwitchEnabled: Bool = false,
        defaultAutoSwitchTarget: ApplicationLayoutRuleTarget = .lastUsed,
        defaultAutoSwitchProfileID: UUID? = nil,
        smartBilingualApplyToAll: Bool = false,
        smartDanishApplyToAll: Bool = false,
        textSnippetsEnabled: Bool = true,
        textSnippets: [TextSnippet] = [],
        textSnippetGroups: [TextSnippetGroup] = [],
        addedModules: Set<FeatureModule> = Set(FeatureModule.allCases),
        moduleSelectionCompleted: Bool = true,
        profiles: [InputLayoutProfile],
        rules: [ApplicationLayoutRule],
        websiteRules: [WebsiteLayoutRule] = [],
        spellingAutocorrectEnabled: Bool = true
    ) {
        self.automationEnabled = automationEnabled
        self.launchAtLogin = launchAtLogin
        self.showMenuBarItem = showMenuBarItem
        self.smartDanishInputEnabled = smartDanishInputEnabled
        self.smartDanishInputAllowedBundleIDs = smartDanishInputAllowedBundleIDs
        self.smartBilingualEnabled = smartBilingualEnabled
        self.smartBilingualAllowedBundleIDs = smartBilingualAllowedBundleIDs
        self.smartBilingualUndoDelay = smartBilingualUndoDelay
        self.defaultAutoSwitchEnabled = defaultAutoSwitchEnabled
        self.defaultAutoSwitchTarget = defaultAutoSwitchTarget
        self.defaultAutoSwitchProfileID = defaultAutoSwitchProfileID
        self.smartBilingualApplyToAll = smartBilingualApplyToAll
        self.smartDanishApplyToAll = smartDanishApplyToAll
        self.textSnippetsEnabled = textSnippetsEnabled
        self.textSnippets = textSnippets
        self.textSnippetGroups = textSnippetGroups
        self.addedModules = addedModules
        self.moduleSelectionCompleted = moduleSelectionCompleted
        self.profiles = profiles
        self.rules = rules
        self.websiteRules = websiteRules
        self.spellingAutocorrectEnabled = spellingAutocorrectEnabled
    }

    enum CodingKeys: String, CodingKey {
        case automationEnabled
        case launchAtLogin
        case showMenuBarItem
        case smartDanishInputEnabled
        case smartDanishInputAllowedBundleIDs
        case smartBilingualEnabled
        case smartBilingualAllowedBundleIDs
        case smartBilingualUndoDelay
        case defaultAutoSwitchEnabled
        case defaultAutoSwitchTarget
        case defaultAutoSwitchProfileID
        case smartBilingualApplyToAll
        case smartDanishApplyToAll
        case textSnippetsEnabled
        case textSnippets
        case textSnippetGroups
        case addedModules
        case moduleSelectionCompleted
        case profiles
        case rules
        case websiteRules
        case spellingAutocorrectEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? true
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.showMenuBarItem = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        self.smartDanishInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartDanishInputEnabled) ?? true
        self.smartDanishInputAllowedBundleIDs = try container.decodeIfPresent([String].self, forKey: .smartDanishInputAllowedBundleIDs) ?? []
        self.smartBilingualEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartBilingualEnabled) ?? true
        self.smartBilingualAllowedBundleIDs = try container.decodeIfPresent([String].self, forKey: .smartBilingualAllowedBundleIDs) ?? self.smartDanishInputAllowedBundleIDs
        self.smartBilingualUndoDelay = try container.decodeIfPresent(Double.self, forKey: .smartBilingualUndoDelay) ?? Self.defaultSmartBilingualUndoDelay
        self.defaultAutoSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultAutoSwitchEnabled) ?? false
        self.defaultAutoSwitchTarget = try container.decodeIfPresent(ApplicationLayoutRuleTarget.self, forKey: .defaultAutoSwitchTarget) ?? .lastUsed
        self.defaultAutoSwitchProfileID = try container.decodeIfPresent(UUID.self, forKey: .defaultAutoSwitchProfileID)
        self.smartBilingualApplyToAll = try container.decodeIfPresent(Bool.self, forKey: .smartBilingualApplyToAll) ?? false
        self.smartDanishApplyToAll = try container.decodeIfPresent(Bool.self, forKey: .smartDanishApplyToAll) ?? false
        self.textSnippetsEnabled = try container.decodeIfPresent(Bool.self, forKey: .textSnippetsEnabled) ?? true
        self.textSnippets = try container.decodeIfPresent([TextSnippet].self, forKey: .textSnippets) ?? []
        self.textSnippetGroups = try container.decodeIfPresent([TextSnippetGroup].self, forKey: .textSnippetGroups) ?? []
        self.addedModules = try container.decodeIfPresent(Set<FeatureModule>.self, forKey: .addedModules)
            ?? Set(FeatureModule.allCases)
        self.moduleSelectionCompleted = try container.decodeIfPresent(Bool.self, forKey: .moduleSelectionCompleted) ?? true
        self.profiles = try container.decodeIfPresent([InputLayoutProfile].self, forKey: .profiles) ?? []
        self.rules = try container.decodeIfPresent([ApplicationLayoutRule].self, forKey: .rules) ?? []
        self.websiteRules = try container.decodeIfPresent([WebsiteLayoutRule].self, forKey: .websiteRules) ?? []
        self.spellingAutocorrectEnabled = try container.decodeIfPresent(Bool.self, forKey: .spellingAutocorrectEnabled) ?? true
    }

    public static func `default`() -> LayoutPilotConfiguration {
        let us = InputLayoutProfile(
            name: "U.S.",
            inputSourceID: "com.apple.keylayout.US",
            notes: "Default Latin layout for code and general typing."
        )
        let russian = InputLayoutProfile(
            name: "Russian",
            inputSourceID: "com.apple.keylayout.RussianWin",
            notes: "Default Russian layout for typing in Russian."
        )

        let defaultApps = [
            "com.apple.Safari",
            SystemApplicationContexts.spotlight.bundleID,
            "com.apple.Notes",
            "com.apple.TextEdit",
            "com.apple.mail",
            "com.apple.MobileSMS",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.microsoft.Word",
            "org.mozilla.firefox",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.raycast.macos",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "ru.keepcoder.Telegram",
            "notion.id",
            "md.obsidian",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.sublimetext.4",
            "com.barebones.bbedit"
        ]

        return LayoutPilotConfiguration(
            automationEnabled: true,
            launchAtLogin: false,
            showMenuBarItem: true,
            smartDanishInputEnabled: true,
            smartDanishInputAllowedBundleIDs: defaultApps,
            smartBilingualEnabled: true,
            smartBilingualAllowedBundleIDs: defaultApps,
            smartBilingualUndoDelay: Self.defaultSmartBilingualUndoDelay,
            addedModules: [],
            moduleSelectionCompleted: false,
            profiles: [us, russian],
            rules: [
                ApplicationLayoutRule(
                    applicationBundleID: SystemApplicationContexts.spotlight.bundleID,
                    applicationName: SystemApplicationContexts.spotlight.applicationName,
                    profileID: us.id,
                    target: .lastUsed
                ),
                ApplicationLayoutRule(
                    applicationBundleID: "com.microsoft.Word",
                    applicationName: "Microsoft Word",
                    profileID: russian.id
                ),
                ApplicationLayoutRule(
                    applicationBundleID: "notion.id",
                    applicationName: "Notion",
                    profileID: russian.id
                ),
                ApplicationLayoutRule(
                    applicationBundleID: "com.apple.Terminal",
                    applicationName: "Terminal",
                    profileID: us.id
                )
            ],
            websiteRules: [],
            spellingAutocorrectEnabled: true
        )
    }

    public func isModuleAdded(_ module: FeatureModule) -> Bool {
        addedModules.contains(module)
    }

    public var isLayoutSwitchingActive: Bool {
        isModuleAdded(.layoutSwitching) && automationEnabled
    }

    public var isSmartDanishActive: Bool {
        isModuleAdded(.smartDanish) && smartDanishInputEnabled
    }

    public var isSmartBilingualActive: Bool {
        isModuleAdded(.smartBilingual) && smartBilingualEnabled
    }

    public var areTextSnippetsActive: Bool {
        isModuleAdded(.snippets) && textSnippetsEnabled
    }
}

public struct AutomationSnapshot: Hashable, Sendable {
    public var frontmostApplicationName: String
    public var frontmostBundleID: String
    public var currentInputSourceID: String
    public var matchedRuleDescription: String
    public var lastAction: String

    public init(
        frontmostApplicationName: String = "Unknown",
        frontmostBundleID: String = "Unknown",
        currentInputSourceID: String = "Unknown",
        matchedRuleDescription: String = "No rule matched",
        lastAction: String = "Idle"
    ) {
        self.frontmostApplicationName = frontmostApplicationName
        self.frontmostBundleID = frontmostBundleID
        self.currentInputSourceID = currentInputSourceID
        self.matchedRuleDescription = matchedRuleDescription
        self.lastAction = lastAction
    }
}

public enum SidebarSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case rules
    case websites
    case profiles
    case snippets
    case smartDanish
    case smartBilingual
    case settings
    case chat
    case diagnostics

    public var id: String { rawValue }

    public static func visibleCases(for addedModules: Set<FeatureModule>) -> [SidebarSection] {
        var result: [SidebarSection] = [.overview]
        if addedModules.contains(.snippets) {
            result.append(.snippets)
        }
        if addedModules.contains(.smartDanish) {
            result.append(.smartDanish)
        }
        if addedModules.contains(.smartBilingual) {
            result.append(.smartBilingual)
        }
        if addedModules.contains(.layoutSwitching) {
            result.append(contentsOf: [.rules, .websites, .profiles])
        }
        result.append(.settings)
        return result
    }

    public var title: String {
        switch self {
        case .overview:
            return "My Modules"
        case .rules:
            return "Applications"
        case .websites:
            return "Websites"
        case .profiles:
            return "Input Profiles"
        case .snippets:
            return "Snippets"
        case .smartDanish:
            return "Smart Danish"
        case .smartBilingual:
            return "Smart RU/EN"
        case .settings:
            return "Settings"
        case .chat:
            return "LLM Chat (Test)"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview:
            return "square.grid.2x2"
        case .rules:
            return "app.badge"
        case .websites:
            return "globe"
        case .profiles:
            return "keyboard"
        case .snippets:
            return "text.badge.plus"
        case .smartDanish:
            return "character.textbox"
        case .smartBilingual:
            return "character.book.closed"
        case .settings:
            return "gearshape"
        case .chat:
            return "bubble.left.and.bubble.right"
        case .diagnostics:
            return "waveform.path.ecg"
        }
    }
}
