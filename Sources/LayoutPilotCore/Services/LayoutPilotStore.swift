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

        do {
            resolvedFileURL = try fileURL ?? LayoutPilotPaths.configurationURL()
            resolvedConfiguration = try Self.loadConfiguration(from: resolvedFileURL)
        } catch {
            initialErrorMessage = error.localizedDescription
        }

        self.fileURL = resolvedFileURL
        self.configuration = resolvedConfiguration
        self.lastErrorMessage = initialErrorMessage
    }

    public func rule(for bundleID: String) -> ApplicationLayoutRule? {
        configuration.rules.first { rule in
            guard rule.isEnabled else { return false }
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

    public func profile(for id: UUID) -> InputLayoutProfile? {
        configuration.profiles.first { $0.id == id }
    }

    public func upsertRule(_ rule: ApplicationLayoutRule) {
        var updated = configuration
        if let index = updated.rules.firstIndex(where: { $0.id == rule.id }) {
            updated.rules[index] = rule
        } else {
            updated.rules.append(rule)
        }
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

    public func setLLMEnabled(_ value: Bool) {
        var updated = configuration
        updated.llm.isEnabled = value
        configuration = updated
    }

    public func setLLMEndpointURL(_ value: String) {
        var updated = configuration
        updated.llm.endpointURL = value
        configuration = updated
    }

    public func setLLMModel(_ value: String) {
        var updated = configuration
        updated.llm.model = value
        configuration = updated
    }

    public func setTranslationEnabled(_ value: Bool) {
        var updated = configuration
        updated.llm.translationEnabled = value
        configuration = updated
    }

    public func setTranslationLanguages(_ value: [TranslationLanguage]) {
        var updated = configuration
        updated.llm.translationLanguages = value
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
}
