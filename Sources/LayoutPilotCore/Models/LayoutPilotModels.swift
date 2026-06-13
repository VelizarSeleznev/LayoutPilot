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

public struct RecentApplicationContext: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public var applicationName: String
    public var bundleID: String

    public init(applicationName: String, bundleID: String) {
        self.applicationName = applicationName
        self.bundleID = bundleID
    }
}

public struct TranslationLanguage: Identifiable, Codable, Hashable, Sendable {
    public var id: String { code }
    public var code: String
    public var name: String
    public var shortcutKey: String
    public var keyCode: Int
    public var isEnabled: Bool

    public init(code: String, name: String, shortcutKey: String, keyCode: Int, isEnabled: Bool) {
        self.code = code
        self.name = name
        self.shortcutKey = shortcutKey
        self.keyCode = keyCode
        self.isEnabled = isEnabled
    }
}

public struct LLMConfiguration: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var endpointURL: String
    public var model: String
    public var translationEnabled: Bool?
    public var translationLanguages: [TranslationLanguage]?

    public init(
        isEnabled: Bool = false,
        endpointURL: String = "http://127.0.0.1:1234/v1",
        model: String = "google/gemma-4-e4b"
    ) {
        self.isEnabled = isEnabled
        self.endpointURL = endpointURL
        self.model = model
        self.translationEnabled = true
        self.translationLanguages = [
            TranslationLanguage(code: "en", name: "English", shortcutKey: "E", keyCode: 14, isEnabled: true),
            TranslationLanguage(code: "ru", name: "Russian", shortcutKey: "R", keyCode: 15, isEnabled: true),
            TranslationLanguage(code: "da", name: "Danish", shortcutKey: "D", keyCode: 2, isEnabled: true),
            TranslationLanguage(code: "es", name: "Spanish", shortcutKey: "S", keyCode: 1, isEnabled: false),
            TranslationLanguage(code: "de", name: "German", shortcutKey: "G", keyCode: 5, isEnabled: false)
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.endpointURL = try container.decodeIfPresent(String.self, forKey: .endpointURL) ?? "http://127.0.0.1:1234/v1"
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "google/gemma-4-e4b"
        self.translationEnabled = try container.decodeIfPresent(Bool.self, forKey: .translationEnabled) ?? true
        self.translationLanguages = try container.decodeIfPresent([TranslationLanguage].self, forKey: .translationLanguages) ?? [
            TranslationLanguage(code: "en", name: "English", shortcutKey: "E", keyCode: 14, isEnabled: true),
            TranslationLanguage(code: "ru", name: "Russian", shortcutKey: "R", keyCode: 15, isEnabled: true),
            TranslationLanguage(code: "da", name: "Danish", shortcutKey: "D", keyCode: 2, isEnabled: true),
            TranslationLanguage(code: "es", name: "Spanish", shortcutKey: "S", keyCode: 1, isEnabled: false),
            TranslationLanguage(code: "de", name: "German", shortcutKey: "G", keyCode: 5, isEnabled: false)
        ]
    }
}

public struct LayoutPilotConfiguration: Codable, Hashable, Sendable {
    public var automationEnabled: Bool
    public var launchAtLogin: Bool
    public var showMenuBarItem: Bool
    public var smartDanishInputEnabled: Bool
    public var smartDanishInputAllowedBundleIDs: [String]
    public var smartBilingualEnabled: Bool
    public var smartBilingualAllowedBundleIDs: [String]
    public var smartBilingualUndoDelay: Double
    public var profiles: [InputLayoutProfile]
    public var rules: [ApplicationLayoutRule]
    public var llm: LLMConfiguration

    public init(
        automationEnabled: Bool = true,
        launchAtLogin: Bool = false,
        showMenuBarItem: Bool = true,
        smartDanishInputEnabled: Bool = true,
        smartDanishInputAllowedBundleIDs: [String] = [],
        smartBilingualEnabled: Bool = true,
        smartBilingualAllowedBundleIDs: [String] = [],
        smartBilingualUndoDelay: Double = 0.5,
        profiles: [InputLayoutProfile],
        rules: [ApplicationLayoutRule],
        llm: LLMConfiguration = .init()
    ) {
        self.automationEnabled = automationEnabled
        self.launchAtLogin = launchAtLogin
        self.showMenuBarItem = showMenuBarItem
        self.smartDanishInputEnabled = smartDanishInputEnabled
        self.smartDanishInputAllowedBundleIDs = smartDanishInputAllowedBundleIDs
        self.smartBilingualEnabled = smartBilingualEnabled
        self.smartBilingualAllowedBundleIDs = smartBilingualAllowedBundleIDs
        self.smartBilingualUndoDelay = smartBilingualUndoDelay
        self.profiles = profiles
        self.rules = rules
        self.llm = llm
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
        case profiles
        case rules
        case llm
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
        self.smartBilingualUndoDelay = try container.decodeIfPresent(Double.self, forKey: .smartBilingualUndoDelay) ?? 0.5
        self.profiles = try container.decodeIfPresent([InputLayoutProfile].self, forKey: .profiles) ?? []
        self.rules = try container.decodeIfPresent([ApplicationLayoutRule].self, forKey: .rules) ?? []
        self.llm = try container.decodeIfPresent(LLMConfiguration.self, forKey: .llm) ?? .init()
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
            smartBilingualUndoDelay: 0.5,
            profiles: [us, russian],
            rules: [
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
            llm: .init()
        )
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
    case translation
    case profiles
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .rules:
            return "Applications"
        case .translation:
            return "LLM Translation"
        case .profiles:
            return "Input Profiles"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.3.group"
        case .rules:
            return "app.badge"
        case .translation:
            return "translate"
        case .profiles:
            return "keyboard"
        case .diagnostics:
            return "waveform.path.ecg"
        }
    }
}
