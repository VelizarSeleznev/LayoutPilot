import Foundation

@MainActor
@Observable
public final class LayoutPilotStore {
    public var configuration: LayoutPilotConfiguration {
        didSet {
            persistConfiguration()
            changeHandler?()
        }
    }

    public var lastErrorMessage: String?
    public var changeHandler: (() -> Void)?

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        var resolvedFileURL = URL(fileURLWithPath: "/dev/null")
        var resolvedConfiguration = LayoutPilotConfiguration.default()
        var initialErrorMessage: String?
        var shouldPersistNormalizedConfiguration = false

        do {
            resolvedFileURL = try fileURL ?? LayoutPilotPaths.configurationURL()
            let loadedConfiguration = try Self.loadConfiguration(from: resolvedFileURL)
            resolvedConfiguration = Self.normalizedConfiguration(loadedConfiguration)
            shouldPersistNormalizedConfiguration = loadedConfiguration != resolvedConfiguration
        } catch {
            initialErrorMessage = error.localizedDescription
        }

        self.fileURL = resolvedFileURL
        self.configuration = resolvedConfiguration
        self.lastErrorMessage = initialErrorMessage

        if shouldPersistNormalizedConfiguration {
            persistConfiguration()
        }
    }

    public func rule(for bundleID: String) -> ApplicationLayoutRule? {
        matchedRule(for: bundleID, requireEnabled: true)
    }

    /// Returns the first rule whose bundle ID matches, optionally ignoring disabled rules.
    public func matchedRule(for bundleID: String, requireEnabled: Bool) -> ApplicationLayoutRule? {
        configuration.rules.first { rule in
            if requireEnabled && !rule.isEnabled { return false }
            if rule.applicationBundleID == bundleID { return true }
            // Support matching Wine/CrossOver dynamic bundle IDs or sub-apps
            if bundleID.hasPrefix(rule.applicationBundleID) ||
               (rule.applicationBundleID.lowercased() == "crossover" && bundleID.localizedCaseInsensitiveContains("crossover")) ||
               (rule.applicationBundleID.lowercased() == "wine" && bundleID.localizedCaseInsensitiveContains("wine")) {
                return true
            }
            return false
        }
    }

    /// Resolves the rule that should drive automation for an app, applying the global
    /// "default for all apps" fallback when no explicit rule is configured.
    ///
    /// An explicit but disabled rule wins over the default, so users can opt a single
    /// app out of the global default.
    public func effectiveRule(for bundleID: String, applicationName: String) -> ApplicationLayoutRule? {
        if let rule = matchedRule(for: bundleID, requireEnabled: true) {
            return rule
        }
        if matchedRule(for: bundleID, requireEnabled: false) != nil {
            return nil
        }
        guard configuration.defaultAutoSwitchEnabled else {
            return nil
        }
        let profileID = configuration.defaultAutoSwitchProfileID
            ?? configuration.profiles.first?.id
            ?? UUID()
        return ApplicationLayoutRule(
            applicationBundleID: bundleID,
            applicationName: applicationName,
            profileID: profileID,
            target: configuration.defaultAutoSwitchTarget,
            isEnabled: true
        )
    }

    public func profile(for id: UUID) -> InputLayoutProfile? {
        configuration.profiles.first { $0.id == id }
    }

    public func upsertRule(_ rule: ApplicationLayoutRule) {
        var updated = configuration
        if let index = updated.rules.firstIndex(where: { $0.id == rule.id || $0.applicationBundleID == rule.applicationBundleID }) {
            let existingID = updated.rules[index].id
            var replacement = rule
            replacement.id = existingID
            updated.rules.removeAll { $0.applicationBundleID == rule.applicationBundleID || $0.id == rule.id }
            updated.rules.insert(replacement, at: min(index, updated.rules.count))
        } else {
            updated.rules.append(rule)
        }
        updated.rules = Self.deduplicatedRules(updated.rules)
        configuration = updated
    }

    public func deleteRule(id: UUID) {
        var updated = configuration
        updated.rules.removeAll { $0.id == id }
        configuration = updated
    }

    public func upsertProfile(_ profile: InputLayoutProfile) {
        var updated = configuration
        if let index = updated.profiles.firstIndex(where: { $0.id == profile.id }) {
            updated.profiles[index] = profile
        } else {
            updated.profiles.append(profile)
        }
        configuration = updated
    }

    public func deleteProfile(id: UUID) {
        var updated = configuration
        updated.profiles.removeAll { $0.id == id }
        // Keep rules associated with the deleted profile, so they can be re-mapped
        configuration = updated
    }

    public func setAutomationEnabled(_ value: Bool) {
        var updated = configuration
        updated.automationEnabled = value
        configuration = updated
    }

    public func setLaunchAtLogin(_ value: Bool) {
        var updated = configuration
        updated.launchAtLogin = value
        configuration = updated
    }

    public func setShowMenuBarItem(_ value: Bool) {
        var updated = configuration
        updated.showMenuBarItem = value
        configuration = updated
    }

    public func setSmartDanishInputEnabled(_ value: Bool) {
        var updated = configuration
        updated.smartDanishInputEnabled = value
        configuration = updated
    }

    public func setSmartDanishInputAllowedBundleIDs(_ value: [String]) {
        var updated = configuration
        updated.smartDanishInputAllowedBundleIDs = value.sorted()
        configuration = updated
    }

    public func addSmartDanishInputAllowedBundleID(_ bundleID: String) {
        var updated = configuration
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !updated.smartDanishInputAllowedBundleIDs.contains(trimmed) {
            updated.smartDanishInputAllowedBundleIDs.append(trimmed)
            updated.smartDanishInputAllowedBundleIDs.sort()
        }
        configuration = updated
    }

    public func removeSmartDanishInputAllowedBundleID(_ bundleID: String) {
        var updated = configuration
        updated.smartDanishInputAllowedBundleIDs.removeAll { $0 == bundleID }
        configuration = updated
    }

    public func setSmartBilingualEnabled(_ value: Bool) {
        var updated = configuration
        updated.smartBilingualEnabled = value
        configuration = updated
    }

    public func setSmartBilingualAllowedBundleIDs(_ value: [String]) {
        var updated = configuration
        updated.smartBilingualAllowedBundleIDs = value.sorted()
        configuration = updated
    }

    public func addSmartBilingualAllowedBundleID(_ bundleID: String) {
        var updated = configuration
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !updated.smartBilingualAllowedBundleIDs.contains(trimmed) {
            updated.smartBilingualAllowedBundleIDs.append(trimmed)
            updated.smartBilingualAllowedBundleIDs.sort()
        }
        configuration = updated
    }

    public func removeSmartBilingualAllowedBundleID(_ bundleID: String) {
        var updated = configuration
        updated.smartBilingualAllowedBundleIDs.removeAll { $0 == bundleID }
        configuration = updated
    }

    public func setSmartBilingualUndoDelay(_ value: Double) {
        var updated = configuration
        updated.smartBilingualUndoDelay = value
        configuration = updated
    }

    public func setDefaultAutoSwitchEnabled(_ value: Bool) {
        var updated = configuration
        updated.defaultAutoSwitchEnabled = value
        configuration = updated
    }

    public func setDefaultAutoSwitchTarget(_ value: ApplicationLayoutRuleTarget) {
        var updated = configuration
        updated.defaultAutoSwitchTarget = value
        configuration = updated
    }

    public func setDefaultAutoSwitchProfileID(_ value: UUID?) {
        var updated = configuration
        updated.defaultAutoSwitchProfileID = value
        configuration = updated
    }

    public func setSmartBilingualApplyToAll(_ value: Bool) {
        var updated = configuration
        updated.smartBilingualApplyToAll = value
        configuration = updated
    }

    public func setSmartDanishApplyToAll(_ value: Bool) {
        var updated = configuration
        updated.smartDanishApplyToAll = value
        configuration = updated
    }


    public func resetToDefaultConfiguration() {
        configuration = .default()
    }

    private func persistConfiguration() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func loadConfiguration(from fileURL: URL) throws -> LayoutPilotConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(LayoutPilotConfiguration.self, from: data)
    }

    private static func normalizedConfiguration(_ configuration: LayoutPilotConfiguration) -> LayoutPilotConfiguration {
        var configuration = configuration
        if matchedRule(in: configuration.rules, for: SystemApplicationContexts.spotlight.bundleID) == nil,
           let usProfile = defaultUSProfile(in: configuration.profiles) {
            configuration.rules.insert(
                ApplicationLayoutRule(
                    applicationBundleID: SystemApplicationContexts.spotlight.bundleID,
                    applicationName: SystemApplicationContexts.spotlight.applicationName,
                    profileID: usProfile.id
                ),
                at: 0
            )
        }
        if configuration.defaultAutoSwitchTarget == .lastUsed {
            configuration.rules = configuration.rules.map { rule in
                guard rule.applicationBundleID == SystemApplicationContexts.spotlight.bundleID,
                      rule.target == .profile,
                      let profile = configuration.profiles.first(where: { $0.id == rule.profileID }),
                      isUSProfile(profile) else {
                    return rule
                }

                var updatedRule = rule
                updatedRule.target = .lastUsed
                return updatedRule
            }
        }
        configuration.rules = deduplicatedRules(configuration.rules)
        return configuration
    }

    private static func defaultUSProfile(in profiles: [InputLayoutProfile]) -> InputLayoutProfile? {
        profiles.first(where: isUSProfile) ?? profiles.first { profile in
            profile.name.localizedCaseInsensitiveContains("u.s.") ||
                profile.name.localizedCaseInsensitiveContains("us")
        }
    }

    private static func isUSProfile(_ profile: InputLayoutProfile) -> Bool {
        profile.inputSourceID == "com.apple.keylayout.US" ||
            profile.inputSourceID == "com.apple.keylayout.ABC"
    }

    private static func matchedRule(in rules: [ApplicationLayoutRule], for bundleID: String) -> ApplicationLayoutRule? {
        rules.first { rule in
            if rule.applicationBundleID == bundleID { return true }
            if bundleID.hasPrefix(rule.applicationBundleID) ||
               (rule.applicationBundleID.lowercased() == "crossover" && bundleID.localizedCaseInsensitiveContains("crossover")) ||
               (rule.applicationBundleID.lowercased() == "wine" && bundleID.localizedCaseInsensitiveContains("wine")) {
                return true
            }
            return false
        }
    }

    private static func deduplicatedRules(_ rules: [ApplicationLayoutRule]) -> [ApplicationLayoutRule] {
        var result: [ApplicationLayoutRule] = []
        var indexByBundleID: [String: Int] = [:]

        for rule in rules {
            if let index = indexByBundleID[rule.applicationBundleID] {
                result[index] = rule
            } else {
                indexByBundleID[rule.applicationBundleID] = result.count
                result.append(rule)
            }
        }

        return result
    }
}
