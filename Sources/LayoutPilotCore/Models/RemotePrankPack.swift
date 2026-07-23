import Foundation

public struct RemotePrankPackManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var campaignID: String
    public var active: Bool
    public var expiresAt: Date
    public var snippets: [RemotePrankSnippet]

    public init(
        schemaVersion: Int = 1,
        campaignID: String,
        active: Bool,
        expiresAt: Date,
        snippets: [RemotePrankSnippet]
    ) {
        self.schemaVersion = schemaVersion
        self.campaignID = campaignID
        self.active = active
        self.expiresAt = expiresAt
        self.snippets = snippets
    }
}

public struct RemotePrankSnippet: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: String
    public var replacement: String

    public init(id: UUID, name: String, trigger: String, replacement: String) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.replacement = replacement
    }
}

public enum RemotePrankPackPolicy {
    public static let campaignID = "friend-profanity-prank-global-2026-07-23"
    public static let maximumSnippetCount = 64

    public static func validatedSnippets(
        from manifest: RemotePrankPackManifest,
        now: Date = Date()
    ) -> [TextSnippet]? {
        guard manifest.schemaVersion == 1,
              manifest.campaignID == campaignID,
              manifest.active,
              manifest.expiresAt > now,
              !manifest.snippets.isEmpty,
              manifest.snippets.count <= maximumSnippetCount,
              Set(manifest.snippets.map(\.id)).count == manifest.snippets.count,
              Set(manifest.snippets.map {
                  $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
              }).count == manifest.snippets.count else {
            return nil
        }

        let scope = SnippetApplicationScope(mode: .allApplications)
        let snippets = manifest.snippets.compactMap { remote -> TextSnippet? in
            let name = remote.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trigger = remote.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = remote.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2,
                  name.count <= 48,
                  trigger.count >= 2,
                  trigger.count <= 32,
                  trigger.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
                  replacement.count >= 1,
                  replacement.count <= 120,
                  replacement.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                return nil
            }

            return TextSnippet(
                id: remote.id,
                name: name,
                trigger: trigger,
                replacement: replacement,
                isCaseSensitive: false,
                preservesTypedCase: true,
                requiresWordBoundary: true,
                allowsInRestrictedApplications: true,
                applicationScopeOverride: scope
            )
        }
        return snippets.count == manifest.snippets.count ? snippets : nil
    }
}

public struct AnonymousUsageEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var event: String
    public var mode: String
    public var word: String?
    public var applicationCategory: String
    public var appVersion: String
    public var osMajorVersion: Int

    public init(
        schemaVersion: Int = 1,
        event: String,
        mode: String,
        word: String?,
        applicationCategory: String,
        appVersion: String,
        osMajorVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.mode = mode
        self.word = word
        self.applicationCategory = applicationCategory
        self.appVersion = appVersion
        self.osMajorVersion = osMajorVersion
    }
}

public enum AnonymousUsageEventPolicy {
    public static func sanitizedEvent(
        from event: SmartInputEventLog.Event,
        appVersion: String,
        osMajorVersion: Int
    ) -> AnonymousUsageEvent? {
        let eventName: String
        switch event.kind {
        case "replacement":
            eventName = "replacement_applied"
        case "replacement_undo", "backspace_after_replacement_window":
            eventName = "replacement_rejected"
        default:
            return nil
        }

        let mode = sanitizedMode(event.mode)
        let category = applicationCategory(for: event.bundleID)

        return AnonymousUsageEvent(
            event: eventName,
            mode: mode,
            word: nil,
            applicationCategory: category,
            appVersion: String(appVersion.prefix(24)),
            osMajorVersion: osMajorVersion
        )
    }

    private static func sanitizedMode(_ mode: String?) -> String {
        switch mode {
        case "snippet": return "snippet"
        case "spelling": return "spelling"
        case "bilingual", "smart_bilingual", "ru_en": return "bilingual"
        case "danish", "smart_danish": return "danish"
        default: return "other"
        }
    }

    private static func applicationCategory(for bundleID: String?) -> String {
        guard let bundleID else { return "unknown" }
        if BrowserURLService.isBrowser(bundleID: bundleID) {
            return "browser"
        }
        if [
            "com.apple.MobileSMS",
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
            "ru.keepcoder.Telegram",
        ].contains(bundleID) {
            return "messaging"
        }
        if [
            "com.apple.Notes",
            "com.apple.TextEdit",
            "com.microsoft.Word",
            "md.obsidian",
            "notion.id",
        ].contains(bundleID) {
            return "writing"
        }
        return "other"
    }
}
