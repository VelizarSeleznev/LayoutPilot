import Foundation

public enum TextSnippetValidationError: LocalizedError, Equatable {
    case emptyTrigger
    case emptyReplacement
    case duplicateTrigger(existingName: String)
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger:
            return "Enter a trigger."
        case .emptyReplacement:
            return "Enter the text LayoutPilot should type."
        case .duplicateTrigger(let existingName):
            return "This trigger is already used by \(existingName)."
        case .persistenceFailed(let message):
            return "The snippet could not be saved: \(message)"
        }
    }
}

public enum RemotePrankPackApplyResult: Equatable, Sendable {
    case disabled
    case alreadyHandled
    case invalidManifest
    case applied(addedSnippetCount: Int)
}

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

    public func upsertWebsiteRule(_ rule: WebsiteLayoutRule) {
        var updated = configuration
        let normalizedDomain = rule.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedDomain.isEmpty else { return }
        var normalizedRule = rule
        normalizedRule.domain = normalizedDomain

        if let index = updated.websiteRules.firstIndex(where: { $0.id == normalizedRule.id || $0.domain == normalizedRule.domain }) {
            let existingID = updated.websiteRules[index].id
            var replacement = normalizedRule
            replacement.id = existingID
            updated.websiteRules.removeAll { $0.domain == normalizedRule.domain || $0.id == normalizedRule.id }
            updated.websiteRules.insert(replacement, at: min(index, updated.websiteRules.count))
        } else {
            updated.websiteRules.append(normalizedRule)
        }
        updated.websiteRules = Self.deduplicatedWebsiteRules(updated.websiteRules)
        configuration = updated
    }

    public func deleteWebsiteRule(id: UUID) {
        var updated = configuration
        updated.websiteRules.removeAll { $0.id == id }
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

    public func setMenuBarModuleOrder(_ order: [FeatureModule]) {
        var updated = configuration
        updated.menuBarModuleOrder = LayoutPilotConfiguration.normalizedMenuBarModuleOrder(order)
        configuration = updated
    }

    public func moveMenuBarModule(_ module: FeatureModule, by offset: Int) {
        var order = configuration.menuBarModuleOrder
        guard let sourceIndex = order.firstIndex(of: module) else { return }
        let destinationIndex = sourceIndex + offset
        guard order.indices.contains(destinationIndex) else { return }
        order.swapAt(sourceIndex, destinationIndex)
        setMenuBarModuleOrder(order)
    }

    public func moveMenuBarModule(_ module: FeatureModule, to target: FeatureModule) {
        var order = configuration.menuBarModuleOrder
        guard let sourceIndex = order.firstIndex(of: module),
              let targetIndex = order.firstIndex(of: target),
              sourceIndex != targetIndex else {
            return
        }
        order.remove(at: sourceIndex)
        order.insert(module, at: min(targetIndex, order.endIndex))
        setMenuBarModuleOrder(order)
    }

    public func setInstantGlobeSwitchingEnabled(_ value: Bool) {
        var updated = configuration
        updated.instantGlobeSwitchingEnabled = value
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

    public func setSpellingAutocorrectEnabled(_ value: Bool) {
        var updated = configuration
        updated.spellingAutocorrectEnabled = value
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

    public func setSmartInputLearningScope(_ value: SmartInputLearningScope) {
        var updated = configuration
        updated.smartInputLearningScope = value
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

    public func setTextSnippetsEnabled(_ value: Bool) {
        var updated = configuration
        updated.textSnippetsEnabled = value
        configuration = updated
    }

    public func setTextSnippetExpansionMode(_ mode: TextSnippetExpansionMode) {
        var updated = configuration
        updated.textSnippetExpansionMode = mode
        configuration = updated
    }

    @discardableResult
    public func applyRemotePrankPack(
        _ manifest: RemotePrankPackManifest,
        now: Date = Date()
    ) -> RemotePrankPackApplyResult {
        guard configuration.remotePrankPackEnabled else { return .disabled }
        guard configuration.appliedRemotePrankPackID != manifest.campaignID else {
            return .alreadyHandled
        }
        guard let snippets = RemotePrankPackPolicy.validatedSnippets(from: manifest, now: now) else {
            return .invalidManifest
        }

        var updated = configuration
        let previousRemoteIDs = Set(updated.remotePrankSnippetIDs)
        let wasPaused = !previousRemoteIDs.isEmpty && !updated.textSnippets.contains {
            previousRemoteIDs.contains($0.id) && $0.isEnabled
        }
        updated.textSnippets.removeAll { previousRemoteIDs.contains($0.id) }

        let existingTriggers = Set(updated.textSnippets.map { $0.trigger.lowercased() })
        let existingIDs = Set(updated.textSnippets.map(\.id))
        var additions = snippets.filter {
            !existingTriggers.contains($0.trigger.lowercased()) && !existingIDs.contains($0.id)
        }
        if wasPaused {
            for index in additions.indices {
                additions[index].isEnabled = false
            }
        }
        updated.textSnippets.append(contentsOf: additions)
        updated.remotePrankSnippetIDs = additions.map(\.id)
        updated.appliedRemotePrankPackID = manifest.campaignID

        if !updated.addedModules.contains(.snippets) {
            updated.addedModules.insert(.snippets)
            updated.remotePrankAddedSnippetsModule = true
        }

        configuration = updated
        return .applied(addedSnippetCount: additions.count)
    }

    public var isRemotePrankPackActive: Bool {
        let remoteIDs = Set(configuration.remotePrankSnippetIDs)
        return configuration.textSnippets.contains {
            remoteIDs.contains($0.id) && $0.isEnabled
        }
    }

    public func setRemotePrankPackActive(_ isActive: Bool) {
        var updated = configuration
        let remoteIDs = Set(updated.remotePrankSnippetIDs)
        guard !remoteIDs.isEmpty else { return }
        for index in updated.textSnippets.indices where remoteIDs.contains(updated.textSnippets[index].id) {
            updated.textSnippets[index].isEnabled = isActive
        }
        configuration = updated
    }

    public func disableAndRemoveRemotePrankPack() {
        var updated = configuration
        let remoteIDs = Set(updated.remotePrankSnippetIDs)
        updated.textSnippets.removeAll { remoteIDs.contains($0.id) }
        if updated.remotePrankAddedSnippetsModule && updated.textSnippets.isEmpty {
            updated.addedModules.remove(.snippets)
        }
        updated.remotePrankPackEnabled = false
        updated.anonymousUsageStatisticsEnabled = false
        updated.remotePrankSnippetIDs = []
        updated.remotePrankAddedSnippetsModule = false
        configuration = updated
    }

    public func setAnonymousUsageStatisticsEnabled(_ value: Bool) {
        var updated = configuration
        updated.anonymousUsageStatisticsEnabled = value
        configuration = updated
    }

    public func setModuleAdded(_ module: FeatureModule, isAdded: Bool) {
        var updated = configuration
        if isAdded {
            updated.addedModules.insert(module)
        } else {
            updated.addedModules.remove(module)
        }
        configuration = updated
    }

    public func completeModuleSelection() {
        var updated = configuration
        updated.moduleSelectionCompleted = true
        configuration = updated
    }

    @available(*, deprecated, message: "Use saveTextSnippet(_:) to receive validation errors.")
    public func upsertTextSnippet(_ snippet: TextSnippet) {
        _ = saveTextSnippet(snippet)
    }

    @discardableResult
    public func saveTextSnippet(_ snippet: TextSnippet) -> Result<TextSnippet, TextSnippetValidationError> {
        let normalized: TextSnippet
        switch Self.validatedTextSnippet(snippet, existing: configuration.textSnippets) {
        case .success(let value):
            normalized = value
        case .failure(let error):
            return .failure(error)
        }

        var updated = configuration
        if let index = updated.textSnippets.firstIndex(where: { $0.id == normalized.id }) {
            updated.textSnippets[index] = normalized
        } else {
            updated.textSnippets.append(normalized)
        }
        configuration = updated

        if let lastErrorMessage {
            return .failure(.persistenceFailed(lastErrorMessage))
        }
        return .success(normalized)
    }

    public func deleteTextSnippet(id: UUID) {
        var updated = configuration
        updated.textSnippets.removeAll { $0.id == id }
        configuration = updated
    }

    @discardableResult
    public func saveTextSnippetGroup(_ group: TextSnippetGroup) -> TextSnippetGroup? {
        var normalized = group
        normalized.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.name.isEmpty else { return nil }
        normalized.applicationScope = Self.normalizedScope(group.applicationScope)

        var updated = configuration
        if let index = updated.textSnippetGroups.firstIndex(where: { $0.id == group.id }) {
            updated.textSnippetGroups[index] = normalized
        } else {
            updated.textSnippetGroups.append(normalized)
        }
        updated.textSnippetGroups.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        configuration = updated
        return normalized
    }

    public func deleteTextSnippetGroup(id: UUID) {
        var updated = configuration
        updated.textSnippetGroups.removeAll { $0.id == id }
        updated.textSnippets = updated.textSnippets.map { snippet in
            guard snippet.groupID == id else { return snippet }
            var ungrouped = snippet
            ungrouped.groupID = nil
            return ungrouped
        }
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
        configuration.menuBarModuleOrder = LayoutPilotConfiguration.normalizedMenuBarModuleOrder(
            configuration.menuBarModuleOrder
        )
        if configuration.smartBilingualUndoDelay <= 0.5 {
            configuration.smartBilingualUndoDelay = LayoutPilotConfiguration.defaultSmartBilingualUndoDelay
        }
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
        configuration.textSnippetGroups = normalizedTextSnippetGroups(configuration.textSnippetGroups)
        let validGroupIDs = Set(configuration.textSnippetGroups.map(\.id))
        configuration.textSnippets = deduplicatedTextSnippets(configuration.textSnippets).map { snippet in
            guard let groupID = snippet.groupID, !validGroupIDs.contains(groupID) else {
                return snippet
            }
            var ungrouped = snippet
            ungrouped.groupID = nil
            return ungrouped
        }
        configuration.websiteRules = deduplicatedWebsiteRules(configuration.websiteRules)
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

    private static func normalizedTextSnippet(_ snippet: TextSnippet) -> TextSnippet? {
        var normalized = snippet
        normalized.trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scope = snippet.applicationScopeOverride {
            normalized.applicationScopeOverride = normalizedScope(scope)
        }
        guard !normalized.trigger.isEmpty,
              !normalized.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmedName = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.name = trimmedName.isEmpty ? normalized.trigger : trimmedName
        return normalized
    }

    private static func validatedTextSnippet(
        _ snippet: TextSnippet,
        existing: [TextSnippet]
    ) -> Result<TextSnippet, TextSnippetValidationError> {
        var normalized = snippet
        normalized.trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scope = snippet.applicationScopeOverride {
            normalized.applicationScopeOverride = normalizedScope(scope)
        }

        guard !normalized.trigger.isEmpty else { return .failure(.emptyTrigger) }
        guard !normalized.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyReplacement)
        }
        let trimmedName = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.name = trimmedName.isEmpty ? normalized.trigger : trimmedName
        if let duplicate = existing.first(where: {
            $0.id != normalized.id && $0.trigger == normalized.trigger
        }) {
            return .failure(.duplicateTrigger(existingName: duplicate.name))
        }
        return .success(normalized)
    }

    private static func deduplicatedTextSnippets(_ snippets: [TextSnippet]) -> [TextSnippet] {
        var result: [TextSnippet] = []
        var indexByTrigger: [String: Int] = [:]

        for snippet in snippets {
            guard let normalized = normalizedTextSnippet(snippet) else {
                continue
            }
            if let index = indexByTrigger[normalized.trigger] {
                result[index] = normalized
            } else {
                indexByTrigger[normalized.trigger] = result.count
                result.append(normalized)
            }
        }

        return result
    }

    private static func normalizedTextSnippetGroups(_ groups: [TextSnippetGroup]) -> [TextSnippetGroup] {
        var seen = Set<UUID>()
        return groups.compactMap { group in
            guard seen.insert(group.id).inserted else { return nil }
            var normalized = group
            normalized.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.name.isEmpty else { return nil }
            normalized.applicationScope = normalizedScope(group.applicationScope)
            return normalized
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func normalizedScope(_ scope: SnippetApplicationScope) -> SnippetApplicationScope {
        SnippetApplicationScope(mode: scope.mode, bundleIDs: scope.bundleIDs)
    }

    private static func deduplicatedWebsiteRules(_ rules: [WebsiteLayoutRule]) -> [WebsiteLayoutRule] {
        var result: [WebsiteLayoutRule] = []
        var indexByDomain: [String: Int] = [:]

        for rule in rules {
            let domain = rule.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !domain.isEmpty else { continue }
            var normalizedRule = rule
            normalizedRule.domain = domain

            if let index = indexByDomain[normalizedRule.domain] {
                result[index] = normalizedRule
            } else {
                indexByDomain[normalizedRule.domain] = result.count
                result.append(normalizedRule)
            }
        }

        return result
    }
}
