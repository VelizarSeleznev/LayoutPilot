import Carbon
@testable import LayoutPilotCore
import XCTest

@MainActor
final class LayoutPilotCoreTests: XCTestCase {
    func testDefaultConfigurationIncludesSeedProfilesAndRules() {
        let configuration = LayoutPilotConfiguration.default()

        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertGreaterThanOrEqual(configuration.rules.count, 4)
        XCTAssertTrue(configuration.rules.contains { $0.applicationBundleID == SystemApplicationContexts.spotlight.bundleID })
        XCTAssertEqual(configuration.smartInputLearningScope, .global)
    }

    func testSmartInputLearningScopeDefaultsToGlobalForExistingConfigurations() throws {
        let missingScope = Data(#"{"profiles":[],"rules":[]}"#.utf8)
        let unknownScope = Data(#"{"profiles":[],"rules":[],"smartInputLearningScope":"futureScope"}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(LayoutPilotConfiguration.self, from: missingScope).smartInputLearningScope,
            .global
        )
        XCTAssertEqual(
            try JSONDecoder().decode(LayoutPilotConfiguration.self, from: unknownScope).smartInputLearningScope,
            .global
        )
    }

    func testStorePersistsSmartInputLearningScope() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        store.setSmartInputLearningScope(.perApplication)

        XCTAssertEqual(store.configuration.smartInputLearningScope, .perApplication)
        XCTAssertEqual(
            LayoutPilotStore(fileURL: fileURL).configuration.smartInputLearningScope,
            .perApplication
        )
    }

    func testStoreCanUpsertAndDeleteRulesInTemporaryFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let profile = InputLayoutProfile(name: "Test", inputSourceID: "com.apple.keylayout.US")
        store.upsertProfile(profile)

        let rule = ApplicationLayoutRule(
            applicationBundleID: "com.example.Test",
            applicationName: "Test",
            profileID: profile.id
        )

        store.upsertRule(rule)

        XCTAssertEqual(store.rule(for: "com.example.Test")?.applicationName, "Test")
        store.deleteRule(id: rule.id)
        XCTAssertNil(store.rule(for: "com.example.Test"))
    }

    func testEffectiveRuleAppliesGlobalDefaultWhenNoExplicitRule() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        // No default configured yet: an unknown app gets no rule.
        XCTAssertNil(store.effectiveRule(for: "com.unknown.App", applicationName: "Unknown"))

        store.setDefaultAutoSwitchTarget(.lastUsed)
        store.setDefaultAutoSwitchEnabled(true)

        let resolved = store.effectiveRule(for: "com.unknown.App", applicationName: "Unknown")
        XCTAssertEqual(resolved?.target, .lastUsed)
        XCTAssertTrue(resolved?.isEnabled ?? false)
        XCTAssertEqual(resolved?.applicationBundleID, "com.unknown.App")
    }

    func testEffectiveRuleRespectsExplicitlyDisabledRuleOverDefault() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        store.setDefaultAutoSwitchEnabled(true)
        store.setDefaultAutoSwitchTarget(.lastUsed)

        let profile = InputLayoutProfile(name: "Test", inputSourceID: "com.apple.keylayout.US")
        store.upsertProfile(profile)
        store.upsertRule(ApplicationLayoutRule(
            applicationBundleID: "com.opted.Out",
            applicationName: "Opted Out",
            profileID: profile.id,
            isEnabled: false
        ))

        // An explicit disabled rule opts the app out of the global default.
        XCTAssertNil(store.effectiveRule(for: "com.opted.Out", applicationName: "Opted Out"))
    }

    func testStoreUpsertReplacesRuleForSameBundleID() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let us = store.configuration.profiles[0]
        let russian = store.configuration.profiles[1]
        let firstRule = ApplicationLayoutRule(
            applicationBundleID: "com.example.Duplicate",
            applicationName: "Duplicate",
            profileID: us.id,
            target: .profile,
            isEnabled: true
        )
        let secondRule = ApplicationLayoutRule(
            applicationBundleID: "com.example.Duplicate",
            applicationName: "Duplicate",
            profileID: russian.id,
            target: .lastUsed,
            isEnabled: false
        )

        store.upsertRule(firstRule)
        store.upsertRule(secondRule)

        let matchingRules = store.configuration.rules.filter { $0.applicationBundleID == "com.example.Duplicate" }
        XCTAssertEqual(matchingRules.count, 1)
        XCTAssertEqual(matchingRules.first?.target, .lastUsed)
        XCTAssertFalse(matchingRules.first?.isEnabled ?? true)
    }

    func testStoreDeduplicatesRulesWhenLoadingConfiguration() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        var configuration = LayoutPilotConfiguration.default()
        let us = configuration.profiles[0]
        let russian = configuration.profiles[1]
        configuration.rules = [
            ApplicationLayoutRule(
                applicationBundleID: "com.example.Duplicate",
                applicationName: "Duplicate",
                profileID: us.id,
                target: .profile,
                isEnabled: true
            ),
            ApplicationLayoutRule(
                applicationBundleID: "com.example.Duplicate",
                applicationName: "Duplicate",
                profileID: russian.id,
                target: .lastUsed,
                isEnabled: false
            )
        ]

        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL)

        let store = LayoutPilotStore(fileURL: fileURL)
        let matchingRules = store.configuration.rules.filter { $0.applicationBundleID == "com.example.Duplicate" }

        XCTAssertEqual(matchingRules.count, 1)
        XCTAssertEqual(matchingRules.first?.target, .lastUsed)
        XCTAssertFalse(matchingRules.first?.isEnabled ?? true)
    }

    func testStoreAddsSpotlightRuleWhenLoadingExistingConfiguration() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let us = InputLayoutProfile(name: "U.S.", inputSourceID: "com.apple.keylayout.US")
        let configuration = LayoutPilotConfiguration(
            profiles: [us],
            rules: []
        )

        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL)

        let store = LayoutPilotStore(fileURL: fileURL)
        let spotlightRule = store.rule(for: SystemApplicationContexts.spotlight.bundleID)

        XCTAssertEqual(spotlightRule?.applicationName, SystemApplicationContexts.spotlight.applicationName)
        XCTAssertEqual(spotlightRule?.profileID, us.id)
        XCTAssertEqual(spotlightRule?.target, .lastUsed)
    }

    func testStoreMigratesLegacySmartBilingualUndoDelay() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let configuration = LayoutPilotConfiguration(
            smartBilingualUndoDelay: 0.5,
            profiles: [],
            rules: []
        )

        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL)

        let store = LayoutPilotStore(fileURL: fileURL)

        XCTAssertEqual(
            store.configuration.smartBilingualUndoDelay,
            LayoutPilotConfiguration.defaultSmartBilingualUndoDelay
        )
    }

    func testStoreValidatesTextSnippetsWithoutMergingDuplicateTriggers() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let first = store.saveTextSnippet(TextSnippet(
            name: "Email",
            trigger: " @@email ",
            replacement: "first@example.com"
        ))
        let duplicate = store.saveTextSnippet(TextSnippet(
            name: "Other email",
            trigger: "@@email",
            replacement: "second@example.com"
        ))
        let empty = store.saveTextSnippet(TextSnippet(name: "Empty", trigger: "", replacement: "ignored"))

        guard case .success(let saved) = first else {
            return XCTFail("Expected the first snippet to save")
        }
        XCTAssertEqual(saved.trigger, "@@email")
        XCTAssertEqual(duplicate, .failure(.duplicateTrigger(existingName: "Email")))
        XCTAssertEqual(empty, .failure(.emptyTrigger))
        XCTAssertEqual(store.configuration.textSnippets.count, 1)
        XCTAssertEqual(store.configuration.textSnippets.first?.trigger, "@@email")
        XCTAssertEqual(store.configuration.textSnippets.first?.replacement, "first@example.com")
    }

    func testStoreUsesTriggerAsNameWhenSnippetNameIsEmpty() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let result = store.saveTextSnippet(TextSnippet(
            name: "  \n ",
            trigger: " ;sig ",
            replacement: "Best regards"
        ))

        guard case .success(let saved) = result else {
            return XCTFail("Expected a snippet without a custom name to save")
        }
        XCTAssertEqual(saved.name, ";sig")
        XCTAssertEqual(saved.trigger, ";sig")
        XCTAssertEqual(store.configuration.textSnippets.first?.name, ";sig")
    }

    func testTextSnippetDefaultsForExistingConfigurations() throws {
        let data = """
        {
          "automationEnabled": true,
          "launchAtLogin": false,
          "showMenuBarItem": true,
          "profiles": [],
          "rules": []
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(LayoutPilotConfiguration.self, from: data)

        XCTAssertTrue(configuration.textSnippetsEnabled)
        XCTAssertTrue(configuration.textSnippets.isEmpty)
        XCTAssertEqual(configuration.textSnippetExpansionMode, .immediately)
        XCTAssertFalse(configuration.spellingAutocorrectEnabled)
        XCTAssertEqual(configuration.addedModules, Set(FeatureModule.allCases))
        XCTAssertTrue(configuration.moduleSelectionCompleted)
        XCTAssertTrue(configuration.remotePrankPackEnabled)
        XCTAssertNil(configuration.appliedRemotePrankPackID)
        XCTAssertTrue(configuration.remotePrankSnippetIDs.isEmpty)
        XCTAssertFalse(configuration.remotePrankAddedSnippetsModule)
        XCTAssertTrue(configuration.anonymousUsageStatisticsEnabled)
    }

    func testRemotePrankPackAppliedOnceWithGlobalScopeAndRollback() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let manifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            defaultProbability: 0.2,
            snippets: [
                RemotePrankSnippet(
                    id: UUID(uuidString: "BF4334B7-FD64-48F4-8C35-6CA5489EA794")!,
                    name: "Prank",
                    trigger: "fucking",
                    replacement: "f****** (fucking)"
                ),
                RemotePrankSnippet(
                    id: UUID(),
                    name: "One",
                    trigger: "shit",
                    replacement: "s*** (shit)"
                )
            ]
        )

        XCTAssertEqual(store.applyRemotePrankPack(manifest), .applied(addedSnippetCount: 2))
        XCTAssertEqual(store.configuration.textSnippets.count, 2)
        XCTAssertEqual(Set(store.configuration.textSnippets.map(\.trigger)), ["fucking", "shit"])
        XCTAssertTrue(store.configuration.addedModules.contains(.snippets))
        XCTAssertTrue(store.configuration.remotePrankAddedSnippetsModule)
        XCTAssertEqual(store.configuration.remotePrankSnippetIDs.count, 2)
        XCTAssertEqual(store.configuration.appliedRemotePrankPackID, RemotePrankPackPolicy.campaignID)
        XCTAssertEqual(store.applyRemotePrankPack(manifest), .alreadyHandled)
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy { !$0.isCaseSensitive })
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy(\.preservesTypedCase))
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy {
            $0.replacementProbability == 0.2
        })
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy(\.requiresWordBoundary))
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy(\.allowsInRestrictedApplications))
        XCTAssertTrue(store.configuration.textSnippets.allSatisfy {
            $0.applicationScopeOverride?.mode == .allApplications
        })
        let remoteSnippet = store.configuration.textSnippets[0]
        for bundleID in [
            "com.openai.codex",
            "com.apple.Safari",
            "com.apple.Terminal",
            "com.1password.1password"
        ] {
            XCTAssertTrue(
                TextSnippetPolicy.allows(remoteSnippet, in: bundleID, groups: []),
                bundleID
            )
        }

        store.configuration.textSnippets.append(TextSnippet(
            id: UUID(),
            name: "Manual",
            trigger: "man",
            replacement: "manual snippet"
        ))
        store.disableAndRemoveRemotePrankPack()

        XCTAssertEqual(store.configuration.textSnippets.map(\.trigger), ["man"])
        XCTAssertFalse(store.configuration.remotePrankPackEnabled)
        XCTAssertFalse(store.configuration.remotePrankAddedSnippetsModule)
        XCTAssertTrue(store.configuration.remotePrankSnippetIDs.isEmpty)
        XCTAssertFalse(store.configuration.anonymousUsageStatisticsEnabled)
        XCTAssertTrue(store.configuration.textSnippetGroups.isEmpty)
        XCTAssertTrue(store.configuration.addedModules.contains(.snippets))
    }

    func testRemotePrankPackCanBePausedAndEnabledWithoutRemovingSnippets() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        let remoteID = UUID()
        let manualID = UUID()
        let manifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            defaultProbability: 0.1,
            snippets: [
                RemotePrankSnippet(
                    id: remoteID,
                    name: "Remote",
                    trigger: "fucking",
                    replacement: "f****** (fucking)"
                )
            ]
        )
        store.configuration.textSnippets = [
            TextSnippet(id: manualID, trigger: "brb", replacement: "be right back")
        ]

        XCTAssertEqual(store.applyRemotePrankPack(manifest), .applied(addedSnippetCount: 1))
        XCTAssertTrue(store.isRemotePrankPackActive)

        store.setRemotePrankPackActive(false)

        XCTAssertFalse(store.isRemotePrankPackActive)
        XCTAssertFalse(store.configuration.textSnippets.first { $0.id == remoteID }?.isEnabled ?? true)
        XCTAssertTrue(store.configuration.textSnippets.first { $0.id == manualID }?.isEnabled ?? false)
        XCTAssertEqual(store.configuration.remotePrankSnippetIDs, [remoteID])
        XCTAssertTrue(store.configuration.remotePrankPackEnabled)

        store.setRemotePrankPackActive(true)

        XCTAssertTrue(store.isRemotePrankPackActive)
        XCTAssertTrue(store.configuration.textSnippets.first { $0.id == remoteID }?.isEnabled ?? false)
    }

    func testRemotePrankPackMigratesOldCampaignWithoutTouchingManualSnippets() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        let oldRemoteID = UUID(uuidString: "BF4334B7-FD64-48F4-8C35-6CA5489EA794")!
        let manualID = UUID()
        store.configuration.textSnippets = [
            TextSnippet(
                id: oldRemoteID,
                name: "Old remote",
                trigger: "fucking",
                replacement: "old replacement",
                isEnabled: false
            ),
            TextSnippet(
                id: manualID,
                name: "Manual",
                trigger: "brb",
                replacement: "be right back"
            )
        ]
        store.configuration.appliedRemotePrankPackID = "friend-profanity-prank-global-2026-07-23"
        store.configuration.remotePrankSnippetIDs = [oldRemoteID]

        let newRemoteID = UUID()
        let manifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            snippets: [
                RemotePrankSnippet(
                    id: newRemoteID,
                    name: "New remote",
                    trigger: "fucking",
                    replacement: "f****** (fucking)"
                )
            ]
        )

        XCTAssertEqual(store.applyRemotePrankPack(manifest), .applied(addedSnippetCount: 1))
        XCTAssertNil(store.configuration.textSnippets.first { $0.id == oldRemoteID })
        XCTAssertEqual(
            store.configuration.textSnippets.first { $0.id == manualID }?.replacement,
            "be right back"
        )
        XCTAssertEqual(store.configuration.remotePrankSnippetIDs, [newRemoteID])
        XCTAssertEqual(store.configuration.appliedRemotePrankPackID, RemotePrankPackPolicy.campaignID)
        XCTAssertFalse(store.isRemotePrankPackActive)
        XCTAssertFalse(store.configuration.textSnippets.first { $0.id == newRemoteID }?.isEnabled ?? true)
    }

    func testRemotePrankPackDoesNotOverwriteCaseInsensitiveManualTrigger() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        let manualID = UUID()
        store.configuration.textSnippets = [
            TextSnippet(
                id: manualID,
                name: "Manual",
                trigger: "FUCKING",
                replacement: "manual replacement"
            )
        ]
        let manifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            snippets: [
                RemotePrankSnippet(
                    id: UUID(),
                    name: "Remote",
                    trigger: "fucking",
                    replacement: "f****** (fucking)"
                )
            ]
        )

        XCTAssertEqual(store.applyRemotePrankPack(manifest), .applied(addedSnippetCount: 0))
        XCTAssertEqual(store.configuration.textSnippets.count, 1)
        XCTAssertEqual(store.configuration.textSnippets.first?.id, manualID)
        XCTAssertEqual(store.configuration.textSnippets.first?.replacement, "manual replacement")
        XCTAssertTrue(store.configuration.remotePrankSnippetIDs.isEmpty)
    }

    func testDisabledRemotePrankPackCannotBeReenabledByNewCampaign() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        store.disableAndRemoveRemotePrankPack()
        let manifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            snippets: [
                RemotePrankSnippet(
                    id: UUID(),
                    name: "Remote",
                    trigger: "fucking",
                    replacement: "f****** (fucking)"
                )
            ]
        )

        XCTAssertEqual(store.applyRemotePrankPack(manifest), .disabled)
        XCTAssertFalse(store.configuration.remotePrankPackEnabled)
        XCTAssertTrue(store.configuration.textSnippets.isEmpty)
        XCTAssertTrue(store.configuration.remotePrankSnippetIDs.isEmpty)
    }

    func testBundledRemotePrankManifestIsBroadAndValid() throws {
        let bundle = Bundle(for: LayoutPilotCoreTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "friend-prank", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            RemotePrankPackManifest.self,
            from: Data(contentsOf: url)
        )
        let snippets = try XCTUnwrap(
            RemotePrankPackPolicy.validatedSnippets(from: manifest, now: Date())
        )

        XCTAssertEqual(manifest.campaignID, RemotePrankPackPolicy.campaignID)
        XCTAssertEqual(manifest.defaultProbability, 0.18)
        XCTAssertEqual(snippets.count, 78)
        XCTAssertEqual(snippets.first { $0.trigger == "бля" }?.replacement, "б** (бля)")
        XCTAssertEqual(snippets.first { $0.trigger == "fucking" }?.replacement, "f****** (fucking)")
        XCTAssertEqual(snippets.first { $0.trigger == "fucking" }?.replacementProbability, 0.18)
        XCTAssertTrue(snippets.first { $0.trigger == "fucking" }?.preservesTypedCase ?? false)
        XCTAssertEqual(snippets.first { $0.trigger == "я" }?.replacement, "мы с мамой")
        XCTAssertEqual(snippets.first { $0.trigger == "я" }?.replacementProbability, 0.03)
        XCTAssertEqual(snippets.first { $0.trigger == "i" }?.replacement, "we, as a family")
        XCTAssertFalse(snippets.first { $0.trigger == "i" }?.preservesTypedCase ?? true)
        XCTAssertEqual(snippets.first { $0.trigger == "no" }?.replacementProbability, 0.008)
        XCTAssertTrue(snippets.allSatisfy(\.allowsInRestrictedApplications))
        XCTAssertTrue(snippets.allSatisfy {
            $0.replacementProbability > 0 && $0.replacementProbability < 0.2
        })
        XCTAssertTrue(snippets.allSatisfy {
            $0.applicationScopeOverride?.mode == .allApplications
        })
        XCTAssertGreaterThanOrEqual(snippets.filter {
            $0.trigger.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        }.count, 20)
        XCTAssertGreaterThanOrEqual(snippets.filter {
            $0.trigger.unicodeScalars.allSatisfy {
                (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
            }
        }.count, 15)
    }

    func testRemotePrankPackRejectsInvalidManifestForSafety() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        let validSnippet = RemotePrankSnippet(
            id: UUID(),
            name: "Bad",
            trigger: "bad trigger",
            replacement: "oops"
        )
        let invalidManifest = RemotePrankPackManifest(
            schemaVersion: 99,
            campaignID: "other-campaign",
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            snippets: [validSnippet]
        )
        let invalidProbabilityManifest = RemotePrankPackManifest(
            campaignID: RemotePrankPackPolicy.campaignID,
            active: true,
            expiresAt: Date().addingTimeInterval(3600),
            defaultProbability: 0,
            snippets: [
                RemotePrankSnippet(
                    id: UUID(),
                    name: "Probability",
                    trigger: "maybe",
                    replacement: "the council will decide"
                )
            ]
        )
        XCTAssertEqual(store.applyRemotePrankPack(invalidManifest), .invalidManifest)
        XCTAssertEqual(store.applyRemotePrankPack(invalidProbabilityManifest), .invalidManifest)
        XCTAssertTrue(store.configuration.textSnippets.isEmpty)
        XCTAssertNil(store.configuration.appliedRemotePrankPackID)
    }

    func testAnonymousUsageEventSanitizerDropsSensitiveContextAndBrowsers() {
        let applied = AnonymousUsageEventPolicy.sanitizedEvent(
            from: SmartInputEventLog.Event(
                kind: "replacement",
                mode: "snippet",
                bundleID: "com.apple.Notes",
                original: "fucking",
                replacement: "f****** (fucking)",
                contextBefore: ["password", "1234"]
            ),
            appVersion: "1.0.0",
            osMajorVersion: 15
        )

        XCTAssertEqual(applied?.event, "replacement_applied")
        XCTAssertEqual(applied?.mode, "snippet")
        XCTAssertEqual(applied?.word, nil)
        XCTAssertEqual(applied?.applicationCategory, "writing")

        let rejected = AnonymousUsageEventPolicy.sanitizedEvent(
            from: SmartInputEventLog.Event(
                kind: "replacement_undo",
                mode: "bilingual",
                bundleID: "com.apple.Notes",
                original: "fucking",
                replacement: "f******"
            ),
            appVersion: "1.0.0",
            osMajorVersion: 15
        )

        XCTAssertEqual(rejected?.event, "replacement_rejected")
        XCTAssertNil(rejected?.word)

        let browserRejected = AnonymousUsageEventPolicy.sanitizedEvent(
            from: SmartInputEventLog.Event(
                kind: "replacement_undo",
                mode: "bilingual",
                bundleID: "com.apple.Safari",
                original: "fucking",
                replacement: "f******"
            ),
            appVersion: "1.0.0",
            osMajorVersion: 15
        )

        XCTAssertEqual(browserRejected?.word, nil)

        let unsupported = AnonymousUsageEventPolicy.sanitizedEvent(
            from: SmartInputEventLog.Event(
                kind: "layout_switch",
                mode: "snippet",
                bundleID: "com.apple.Notes",
                original: "foo"
            ),
            appVersion: "1.0.0",
            osMajorVersion: 15
        )

        XCTAssertNil(unsupported)
    }

    func testSnippetExpansionModeAndExplicitAutocorrectPreferencePersist() throws {
        var configuration = LayoutPilotConfiguration.default()
        configuration.textSnippetExpansionMode = .afterSpace
        configuration.spellingAutocorrectEnabled = true

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(LayoutPilotConfiguration.self, from: data)

        XCTAssertEqual(decoded.textSnippetExpansionMode, .afterSpace)
        XCTAssertTrue(decoded.spellingAutocorrectEnabled)
    }

    func testNewConfigurationStartsWithModuleChooser() {
        let configuration = LayoutPilotConfiguration.default()

        XCTAssertTrue(configuration.addedModules.isEmpty)
        XCTAssertFalse(configuration.moduleSelectionCompleted)
        XCTAssertEqual(SidebarSection.visibleCases(for: configuration.addedModules), [.overview, .settings])
        XCTAssertFalse(configuration.isLayoutSwitchingActive)
        XCTAssertFalse(configuration.isSmartDanishActive)
        XCTAssertFalse(configuration.isSmartBilingualActive)
        XCTAssertFalse(configuration.areTextSnippetsActive)
        XCTAssertFalse(configuration.spellingAutocorrectEnabled)
    }

    func testModuleMembershipGatesRuntimeSwitches() {
        var configuration = LayoutPilotConfiguration.default()
        configuration.addedModules = [.snippets, .smartDanish]

        XCTAssertTrue(configuration.areTextSnippetsActive)
        XCTAssertTrue(configuration.isSmartDanishActive)
        XCTAssertFalse(configuration.isSmartBilingualActive)
        XCTAssertFalse(configuration.isLayoutSwitchingActive)

        configuration.textSnippetsEnabled = false
        configuration.smartDanishInputEnabled = false
        XCTAssertFalse(configuration.areTextSnippetsActive)
        XCTAssertFalse(configuration.isSmartDanishActive)
    }

    func testLegacySnippetDecodesWithTriggerAsName() throws {
        let data = """
        {
          "id": "D5A1466C-3E0B-42E9-88A1-842FD24679D2",
          "trigger": ";sig",
          "replacement": "Best regards",
          "isEnabled": true
        }
        """.data(using: .utf8)!

        let snippet = try JSONDecoder().decode(TextSnippet.self, from: data)

        XCTAssertEqual(snippet.name, ";sig")
        XCTAssertFalse(snippet.allowsInRestrictedApplications)
        XCTAssertEqual(snippet.replacementProbability, 1)
        XCTAssertNil(snippet.groupID)
        XCTAssertNil(snippet.applicationScopeOverride)
    }

    func testSecureTextFieldsRemainExcludedFromGlobalSnippetHandling() {
        XCTAssertTrue(AXFocusInspector.isSecureTextField(
            role: "AXSecureTextField",
            subrole: nil
        ))
        XCTAssertTrue(AXFocusInspector.isSecureTextField(
            role: "AXTextField",
            subrole: "AXSecureTextField"
        ))
        XCTAssertFalse(AXFocusInspector.isSecureTextField(
            role: "AXTextField",
            subrole: nil
        ))
    }

    func testRemoteSnippetHandlingCanEnterSecurityExcludedApplications() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))
        let regularSnippet = TextSnippet(
            name: "Regular",
            trigger: ";regular",
            replacement: "Regular"
        )
        let remoteSnippet = TextSnippet(
            name: "Remote",
            trigger: "fucking",
            replacement: "f****** (fucking)",
            isCaseSensitive: false,
            preservesTypedCase: true,
            requiresWordBoundary: true,
            allowsInRestrictedApplications: true,
            applicationScopeOverride: SnippetApplicationScope(mode: .allApplications)
        )

        service.textSnippets = [regularSnippet]
        XCTAssertFalse(service.isTextSnippetsAllowed(for: "com.apple.Terminal"))

        service.textSnippets = [regularSnippet, remoteSnippet]
        XCTAssertTrue(service.isTextSnippetsAllowed(for: "com.apple.Terminal"))
        XCTAssertTrue(service.isTextSnippetsAllowed(for: "com.openai.codex"))
    }

    func testSnippetScopeInheritanceAndOverride() {
        let group = TextSnippetGroup(
            name: "Work",
            applicationScope: SnippetApplicationScope(
                mode: .onlySelected,
                bundleIDs: ["com.apple.mail"]
            )
        )
        let inherited = TextSnippet(name: "Signature", trigger: ";sig", replacement: "Regards", groupID: group.id)
        let overridden = TextSnippet(
            name: "Everywhere",
            trigger: ";all",
            replacement: "Hello",
            groupID: group.id,
            applicationScopeOverride: SnippetApplicationScope(mode: .allApplications)
        )

        XCTAssertTrue(TextSnippetPolicy.allows(inherited, in: "com.apple.mail", groups: [group]))
        XCTAssertFalse(TextSnippetPolicy.allows(inherited, in: "com.apple.Notes", groups: [group]))
        XCTAssertTrue(TextSnippetPolicy.allows(overridden, in: "com.apple.Notes", groups: [group]))
    }

    func testSnippetAllExceptScope() {
        let snippet = TextSnippet(
            name: "Greeting",
            trigger: ";hi",
            replacement: "Hello",
            applicationScopeOverride: SnippetApplicationScope(
                mode: .allExceptSelected,
                bundleIDs: ["com.example.Blocked"]
            )
        )

        XCTAssertFalse(TextSnippetPolicy.allows(snippet, in: "com.example.Blocked", groups: []))
        XCTAssertTrue(TextSnippetPolicy.allows(snippet, in: "com.apple.Notes", groups: []))
        XCTAssertFalse(TextSnippetPolicy.allows(snippet, in: "com.apple.Terminal", groups: []))
    }

    func testDeletingSnippetFolderKeepsSnippetsUngrouped() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)
        let group = TextSnippetGroup(name: "Work")
        XCTAssertNotNil(store.saveTextSnippetGroup(group))
        let snippet = TextSnippet(name: "Signature", trigger: ";sig", replacement: "Regards", groupID: group.id)
        guard case .success = store.saveTextSnippet(snippet) else {
            return XCTFail("Expected snippet to save")
        }

        store.deleteTextSnippetGroup(id: group.id)

        XCTAssertTrue(store.configuration.textSnippetGroups.isEmpty)
        XCTAssertNil(store.configuration.textSnippets.first?.groupID)
    }

    func testStoreMigratesDefaultSpotlightUSRuleToLastUsedWhenDefaultIsLastUsed() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let us = InputLayoutProfile(name: "U.S.", inputSourceID: "com.apple.keylayout.US")
        let configuration = LayoutPilotConfiguration(
            defaultAutoSwitchTarget: .lastUsed,
            profiles: [us],
            rules: [
                ApplicationLayoutRule(
                    applicationBundleID: SystemApplicationContexts.spotlight.bundleID,
                    applicationName: SystemApplicationContexts.spotlight.applicationName,
                    profileID: us.id,
                    target: .profile
                )
            ]
        )

        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL)

        let store = LayoutPilotStore(fileURL: fileURL)
        let spotlightRule = store.rule(for: SystemApplicationContexts.spotlight.bundleID)

        XCTAssertEqual(spotlightRule?.target, .lastUsed)
    }

    func testApplicationLayoutRuleTargetDefaultsToProfileForExistingConfigurations() throws {
        let profileID = UUID()
        let data = """
        {
          "id": "\(UUID().uuidString)",
          "applicationBundleID": "com.example.Legacy",
          "applicationName": "Legacy",
          "profileID": "\(profileID.uuidString)",
          "isEnabled": true
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(ApplicationLayoutRule.self, from: data)

        XCTAssertEqual(rule.target, .profile)
        XCTAssertEqual(rule.profileID, profileID)
    }

    func testApplicationLayoutRuleCanPersistLastUsedTarget() throws {
        let rule = ApplicationLayoutRule(
            applicationBundleID: "com.example.LastUsed",
            applicationName: "Last Used",
            profileID: UUID(),
            target: .lastUsed
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ApplicationLayoutRule.self, from: data)

        XCTAssertEqual(decoded.target, .lastUsed)
    }

    func testRecentApplicationsAreDeduplicatedAndLimitedToFour() {
        var recent: [RecentApplicationContext] = []

        recent = LayoutAutomationEngine.updatedRecentApplications(
            recent,
            with: RecentApplicationContext(applicationName: "One", bundleID: "com.example.One")
        )
        recent = LayoutAutomationEngine.updatedRecentApplications(
            recent,
            with: RecentApplicationContext(applicationName: "Two", bundleID: "com.example.Two")
        )
        recent = LayoutAutomationEngine.updatedRecentApplications(
            recent,
            with: RecentApplicationContext(applicationName: "Three", bundleID: "com.example.Three")
        )
        recent = LayoutAutomationEngine.updatedRecentApplications(
            recent,
            with: RecentApplicationContext(applicationName: "Two", bundleID: "com.example.Two")
        )
        recent = LayoutAutomationEngine.updatedRecentApplications(
            recent,
            with: RecentApplicationContext(applicationName: "Four", bundleID: "com.example.Four")
        )

        XCTAssertEqual(recent.map(\.bundleID), [
            "com.example.Four",
            "com.example.Two",
            "com.example.Three",
            "com.example.One"
        ])
    }

    func testRecentApplicationsExcludeLayoutPilotAndUnknownContexts() {
        var recent = [
            RecentApplicationContext(applicationName: "Mail", bundleID: "com.apple.mail")
        ]

        for application in [
            RecentApplicationContext(applicationName: "Safari", bundleID: "com.apple.Safari"),
            RecentApplicationContext(applicationName: "Notes", bundleID: "com.apple.Notes"),
            RecentApplicationContext(applicationName: "Music", bundleID: "com.apple.Music"),
            RecentApplicationContext(applicationName: "Calendar", bundleID: "com.apple.iCal"),
            RecentApplicationContext(applicationName: "LayoutPilot", bundleID: "com.velizard.LayoutPilot"),
            RecentApplicationContext(applicationName: "Unknown", bundleID: "Unknown")
        ] {
            recent = LayoutAutomationEngine.updatedRecentApplications(
                recent,
                with: application,
                limit: 4
            )
        }

        XCTAssertEqual(recent.map(\.bundleID), [
            "com.apple.iCal",
            "com.apple.Music",
            "com.apple.Notes",
            "com.apple.Safari"
        ])
    }

    func testEngineRetainsLastExternalContextWhileLayoutPilotIsFrontmost() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        store.configuration = LayoutPilotConfiguration(
            automationEnabled: false,
            profiles: [],
            rules: []
        )

        let inputSourceClient = FakeInputSourceClient(currentSourceID: "us")
        var activeContext = RecentApplicationContext(
            applicationName: "Editor",
            bundleID: "com.example.Editor"
        )
        let engine = LayoutAutomationEngine(
            store: store,
            inputSourceClient: inputSourceClient,
            activeContextProvider: { activeContext }
        )

        engine.refreshNow()
        XCTAssertEqual(engine.lastExternalApplication, activeContext)
        XCTAssertTrue(engine.recentApplications.isEmpty)

        activeContext = RecentApplicationContext(
            applicationName: "LayoutPilot",
            bundleID: LayoutAutomationEngine.layoutPilotBundleID
        )
        engine.refreshNow()

        XCTAssertEqual(engine.lastExternalApplication?.bundleID, "com.example.Editor")
        XCTAssertEqual(engine.snapshot.frontmostBundleID, "com.example.Editor")
        XCTAssertTrue(engine.recentApplications.isEmpty)

        activeContext = RecentApplicationContext(
            applicationName: "Browser",
            bundleID: "com.example.Browser"
        )
        engine.refreshNow()

        XCTAssertEqual(engine.lastExternalApplication, activeContext)
        XCTAssertEqual(engine.recentApplications.map(\.bundleID), ["com.example.Editor"])
    }

    func testLastUsedRuleDoesNotFightManualSwitchInActiveApp() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)
        store.configuration = LayoutPilotConfiguration(
            automationEnabled: true,
            defaultAutoSwitchEnabled: true,
            defaultAutoSwitchTarget: .lastUsed,
            profiles: [InputLayoutProfile(name: "U.S.", inputSourceID: "us")],
            rules: []
        )

        let inputSourceClient = FakeInputSourceClient(currentSourceID: "ru")
        var activeContext = RecentApplicationContext(applicationName: "Editor", bundleID: "com.example.Editor")
        let engine = LayoutAutomationEngine(
            store: store,
            inputSourceClient: inputSourceClient,
            activeContextProvider: { activeContext }
        )

        engine.refreshNow()
        XCTAssertTrue(inputSourceClient.activatedSourceIDs.isEmpty)

        inputSourceClient.currentSourceID = "us"
        engine.refreshNow()
        XCTAssertTrue(inputSourceClient.activatedSourceIDs.isEmpty)

        activeContext = RecentApplicationContext(applicationName: "Browser", bundleID: "com.example.Browser")
        engine.refreshNow()
        XCTAssertTrue(inputSourceClient.activatedSourceIDs.isEmpty)

        inputSourceClient.currentSourceID = "ru"
        engine.refreshNow()
        XCTAssertTrue(inputSourceClient.activatedSourceIDs.isEmpty)

        activeContext = RecentApplicationContext(applicationName: "Editor", bundleID: "com.example.Editor")
        engine.refreshNow()
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us"])
    }

    func testProfileRuleDoesNotFightManualSwitchInActiveApp() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)
        let us = InputLayoutProfile(name: "U.S.", inputSourceID: "us")
        store.configuration = LayoutPilotConfiguration(
            automationEnabled: true,
            profiles: [us],
            rules: [
                ApplicationLayoutRule(
                    applicationBundleID: "com.example.Editor",
                    applicationName: "Editor",
                    profileID: us.id,
                    target: .profile
                )
            ]
        )

        let inputSourceClient = FakeInputSourceClient(currentSourceID: "ru")
        var activeContext = RecentApplicationContext(applicationName: "Editor", bundleID: "com.example.Editor")
        let engine = LayoutAutomationEngine(
            store: store,
            inputSourceClient: inputSourceClient,
            activeContextProvider: { activeContext }
        )

        engine.refreshNow()
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us"])

        inputSourceClient.currentSourceID = "ru"
        engine.refreshNow()
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us"])
        XCTAssertEqual(engine.snapshot.currentInputSourceID, "ru")

        engine.refreshNow(forceApplyRule: true)
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us", "us"])

        activeContext = RecentApplicationContext(applicationName: "Browser", bundleID: "com.example.Browser")
        inputSourceClient.currentSourceID = "ru"
        engine.refreshNow()
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us", "us"])

        activeContext = RecentApplicationContext(applicationName: "Editor", bundleID: "com.example.Editor")
        engine.refreshNow()
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us", "us", "us"])
    }

    func testApplicationActivationNotificationAppliesRuleForNewFrontmostApp() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LayoutPilotStore(fileURL: tempDirectory.appendingPathComponent("configuration.json"))
        let us = InputLayoutProfile(name: "U.S.", inputSourceID: "us")
        store.configuration = LayoutPilotConfiguration(
            automationEnabled: true,
            profiles: [us],
            rules: [
                ApplicationLayoutRule(
                    applicationBundleID: "com.apple.Terminal",
                    applicationName: "Terminal",
                    profileID: us.id
                )
            ]
        )

        let inputSourceClient = FakeInputSourceClient(currentSourceID: "ru")
        var activeContext = RecentApplicationContext(
            applicationName: "Editor",
            bundleID: "com.example.Editor"
        )
        let engine = LayoutAutomationEngine(
            store: store,
            inputSourceClient: inputSourceClient,
            activeContextProvider: { activeContext }
        )
        engine.start()
        defer { engine.stop() }

        activeContext = RecentApplicationContext(
            applicationName: "Terminal",
            bundleID: "com.apple.Terminal"
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        await Task.yield()

        XCTAssertEqual(engine.snapshot.frontmostBundleID, "com.apple.Terminal")
        XCTAssertEqual(inputSourceClient.activatedSourceIDs, ["us"])
    }

    func testDisablingSmartDanishOverridesPerAppAndApplyToAllSettings() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))
        service.isEnabled = false
        service.allowedBundleIDs = ["com.example.Editor"]
        service.danishApplyToAll = true

        XCTAssertFalse(service.isDanishAllowed(for: "com.example.Editor"))
        XCTAssertFalse(service.isDanishAllowed(for: "com.example.Other"))
    }

    func testSpellingAutocorrectServiceStartsDisabled() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))

        XCTAssertFalse(service.spellingAutocorrectEnabled)
    }

    func testSmartInputCommitsBufferedWordOnlyAfterBoundary() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))

        XCTAssertFalse(service.shouldCommitBufferedWord(after: "k"))
        XCTAssertFalse(service.shouldCommitBufferedWord(after: "'"))
        XCTAssertFalse(service.shouldCommitBufferedWord(after: "\""))

        for boundary in [" ", ".", ",", "!", "?", ")"] {
            XCTAssertTrue(service.shouldCommitBufferedWord(after: boundary), boundary)
        }
    }

    func testSmartInputRecoversWholeWordWhenBufferContainsOnlyRetypedSuffix() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))

        let resolution = service.resolveCommitToken(
            bufferedToken: "ока",
            focusedTextBeforeCaret: "Что это строка"
        )

        XCTAssertEqual(resolution.token, "строка")
        XCTAssertTrue(resolution.hasCompleteFocusedWord)
    }

    func testSmartInputDoesNotTrustFocusedWordWhenItDoesNotEndInBufferedSuffix() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))

        let resolution = service.resolveCommitToken(
            bufferedToken: "ока",
            focusedTextBeforeCaret: "Что это предложение"
        )

        XCTAssertEqual(resolution.token, "ока")
        XCTAssertFalse(resolution.hasCompleteFocusedWord)
    }

    func testEditedWordTrackerProtectsRetypedFragmentWithoutFocusedWordData() {
        let tracker = SmartInputService.EditedWordTracker()

        tracker.noteCommittedBoundary(hadWord: true)
        tracker.noteBackspace(bufferWasEmpty: true)

        XCTAssertTrue(tracker.isEditingExistingWord)
        XCTAssertTrue(tracker.shouldSuppressFragmentConversion(hasCompleteFocusedWord: false))
        XCTAssertFalse(tracker.shouldSuppressFragmentConversion(hasCompleteFocusedWord: true))
    }

    func testSpotlightForceSwitchOnlyRunsForOpenShortcut() {
        XCTAssertTrue(SmartInputService.shouldForceUSForSpotlight(
            keyCode: 49,
            flags: [.maskCommand]
        ))

        XCTAssertFalse(SmartInputService.shouldForceUSForSpotlight(
            keyCode: 0,
            flags: []
        ))

        XCTAssertFalse(SmartInputService.shouldForceUSForSpotlight(
            keyCode: 49,
            flags: [.maskCommand, .maskAlternate]
        ))
    }

    func testBilingualConversion() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("learning.json")
        try? FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))
        
        // Assert that arbitrary short words/abbreviations of length < 3 never trigger bilingual conversion
        XCTAssertNil(service.checkBilingualConversion(for: "lc"))
        XCTAssertNil(service.checkBilingualConversion(for: "a")) // Latin 'a' under US is valid English (returns nil); under Russian, translates to 'f' which is not in commonEnglishShortWords (returns nil)
        
        // Test explicit sourceLayoutID conversions for 3-letter words
        XCTAssertFalse(service.isValidEnglishWord("rfr"))
        XCTAssertTrue(service.isValidRussianWord("как"))
        let rfrUS = service.checkBilingualConversion(for: "rfr", sourceLayoutID: "com.apple.keylayout.US")
        XCTAssertNotNil(rfrUS)
        XCTAssertEqual(rfrUS?.replacement, "как")

        let kakRU = service.checkBilingualConversion(for: "как", sourceLayoutID: "com.apple.keylayout.RussianWin")
        XCTAssertNil(kakRU) // 'как' is a valid Russian word, shouldn't convert to English 'rfr'

        let vshpRU = service.checkBilingualConversion(for: "вщп", sourceLayoutID: "com.apple.keylayout.RussianWin")
        XCTAssertNotNil(vshpRU)
        XCTAssertEqual(vshpRU?.replacement, "dog")

        // Record 'rfr' as accepted in US layout 3 times.
        for _ in 0..<3 {
            service.learningStore.recordAcceptedWord("rfr", layoutID: "com.apple.keylayout.US", bundleID: "com.example.Test")
        }
        // Since 'rfr' is invalid in English but 'как' is valid in Russian, the accepted_word_dictionary suppression must be bypassed!
        let rfrUSAfterAccepted = service.checkBilingualConversion(for: "rfr", sourceLayoutID: "com.apple.keylayout.US")
        XCTAssertNotNil(rfrUSAfterAccepted)
        XCTAssertEqual(rfrUSAfterAccepted?.replacement, "как")

        // Record 2 rejections for 'rfr' -> 'как' conversion.
        for _ in 0..<2 {
            service.learningStore.recordRejectedConversion(
                mode: "bilingual",
                original: "rfr",
                replacement: "как",
                sourceLayoutID: "com.apple.keylayout.US",
                targetLayoutID: "com.apple.keylayout.RussianWin",
                bundleID: "com.example.Test"
            )
        }
        // This ubiquitous wrong-layout word is intentionally forced even if stale
        // learning data says that the user rejected it in the past.
        let rfrUSAfterRejected = service.checkBilingualConversion(for: "rfr", sourceLayoutID: "com.apple.keylayout.US")
        XCTAssertEqual(rfrUSAfterRejected?.replacement, "как")
        
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
        
        let isUS = sourceID.contains("US") || sourceID.contains("ABC")
        let isRussian = sourceID.localizedCaseInsensitiveContains("Russian") || 
                        sourceID.hasSuffix(".ru") || 
                        sourceID.contains(".ru.") || 
                        sourceID == "ru"
                        
        if isUS {
            // Under English layout, "hello" is valid English and should not trigger conversion
            XCTAssertNil(service.checkBilingualConversion(for: "hello"))
            XCTAssertNil(service.checkBilingualConversion(for: "bbuhf["))
            
            // "ghbdtn" is English layout for "привет", should trigger conversion to Russian
            let privetResult = service.checkBilingualConversion(for: "ghbdtn")
            XCTAssertNotNil(privetResult)
            XCTAssertEqual(privetResult?.replacement, "привет")
            
            // Single-character tokens are too ambiguous for safe automatic conversion.
            XCTAssertNil(service.checkBilingualConversion(for: "f"))
            
            // Short grammatical word: "ds" translates to "вы".
            let vyResult = service.checkBilingualConversion(for: "ds")
            XCTAssertNotNil(vyResult)
            XCTAssertEqual(vyResult?.replacement, "вы")
        } else if isRussian {
            // Under Russian layout, "привет" is valid Russian and should not trigger conversion
            XCTAssertNil(service.checkBilingualConversion(for: "привет"))
            
            // "флешка" is a valid Russian neologism/word and should not be converted to English
            XCTAssertNil(service.checkBilingualConversion(for: "флешка"))
            XCTAssertNil(service.checkBilingualConversion(for: "грах"))
            XCTAssertNil(service.checkBilingualConversion(for: "bbграх"))
            
            // "цщкдв" is Russian layout for "world", should trigger conversion to English
            let worldResult = service.checkBilingualConversion(for: "цщкдв")
            XCTAssertNotNil(worldResult)
            XCTAssertEqual(worldResult?.replacement, "world")
            
            // Single-character tokens are too ambiguous for safe automatic conversion.
            XCTAssertNil(service.checkBilingualConversion(for: "ш"))
            
            // Short grammatical word: "ещ" translates to "to".
            let toResult = service.checkBilingualConversion(for: "ещ")
            XCTAssertNotNil(toResult)
            XCTAssertEqual(toResult?.replacement, "to")
        }
    }

    func testBilingualConversionAcceptsUSKeysThatProduceRussianLetters() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: tempURL))
        let sourceLayoutID = "com.apple.keylayout.US"

        let cases = [
            ("vj;yj", "можно"),
            ("[jhjij", "хорошо"),
            ("'nj", "это"),
            ("j,]trn", "объект"),
            ("k.lb", "люди"),
            ("`krf", "ёлка"),
        ]

        for (typed, expected) in cases {
            XCTAssertEqual(
                service.checkBilingualConversion(
                    for: typed,
                    sourceLayoutID: sourceLayoutID
                )?.replacement,
                expected,
                typed
            )
        }

        XCTAssertEqual(
            service.checkBilingualConversion(
                for: "ghbdtn,,,",
                sourceLayoutID: sourceLayoutID
            )?.replacement,
            "привет,,,"
        )
        for englishWithPunctuation in ["hello,", "world.", "test;", "array["] {
            XCTAssertNil(
                service.checkBilingualConversion(
                    for: englishWithPunctuation,
                    sourceLayoutID: sourceLayoutID
                ),
                englishWithPunctuation
            )
        }
    }

    func testBilingualBufferDistinguishesRussianLetterKeysFromPunctuationKeys() {
        let service = SmartInputService.shared
        let sourceLayoutID = "com.apple.keylayout.US"

        for character in [
            "[", "]", ";", "'", ",", ".", "`",
            "{", "}", ":", "\"", "<", ">", "~",
        ] {
            XCTAssertTrue(
                service.shouldBufferBilingualInput(
                    character,
                    sourceLayoutID: sourceLayoutID
                ),
                character
            )
        }

        for character in ["/", "?", "!", "-"] {
            XCTAssertFalse(
                service.shouldBufferBilingualInput(
                    character,
                    sourceLayoutID: sourceLayoutID
                ),
                character
            )
        }

        XCTAssertFalse(service.shouldBufferBilingualInput(
            ",",
            sourceLayoutID: "com.apple.keylayout.RussianWin"
        ))
    }

    func testDoubleInitialUppercaseCorrectionForCurrentLayout() {
        let service = SmartInputService.shared

        XCTAssertEqual(
            service.capitalizationCorrection(
                for: "ЧТо",
                sourceLayoutID: "com.apple.keylayout.RussianWin"
            ),
            "Что"
        )

        XCTAssertNil(service.capitalizationCorrection(
            for: "США",
            sourceLayoutID: "com.apple.keylayout.RussianWin"
        ))
    }

    func testBilingualConversionCorrectsDoubleInitialUppercaseAfterTranslation() {
        let service = SmartInputService.shared

        let result = service.checkBilingualConversion(
            for: "XNj",
            sourceLayoutID: "com.apple.keylayout.US"
        )

        XCTAssertEqual(result?.replacement, "Что")
    }
    
    func testAvailableInputSourcesExcludePalettes() {
        let client = SystemInputSourceClient()
        let sources = client.availableInputSources()
        
        for source in sources {
            XCTAssertNotEqual(source.sourceID, "com.apple.PressAndHold")
            XCTAssertNotEqual(source.sourceID, "com.apple.CharacterPaletteIM")
        }
    }

    func testContextAwareLayoutSwitching() {
        let service = SmartInputService.shared
        
        // Reset context history
        service.contextHistory.reset()
        
        // 1. Verify language detection
        XCTAssertEqual(service.detectLanguage(of: "Привет"), .russian)
        XCTAssertEqual(service.detectLanguage(of: "hello"), .english)
        XCTAssertEqual(service.detectLanguage(of: "123"), .unknown)
        XCTAssertEqual(service.detectLanguage(of: "Приветhello"), .unknown)
        
        // 2. Verify empty history triggers switch
        XCTAssertTrue(service.shouldSwitchLayout(to: "en_layout", replacement: "hello"))
        
        // 3. Verify Russian context prevents switching to English for a single word
        service.contextHistory.append("Если")
        service.contextHistory.append("я")
        service.contextHistory.append("хочу")
        service.contextHistory.append("написать")
        
        XCTAssertFalse(service.shouldSwitchLayout(to: "en_layout", replacement: "applications"))
        
        // 4. Verify consecutive English words trigger layout switch
        service.contextHistory.append("applications")
        XCTAssertTrue(service.shouldSwitchLayout(to: "en_layout", replacement: "macos"))
        
        // 5. Clean up history
        service.contextHistory.reset()
    }

    func testSingleLetterConversionUsesStrongContextOnly() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        XCTAssertNil(service.checkBilingualConversion(
            for: "b",
            sourceLayoutID: "com.apple.keylayout.US",
            contextWords: []
        ))

        let result = service.checkBilingualConversion(
            for: "b",
            sourceLayoutID: "com.apple.keylayout.US",
            contextWords: ["Если", "я", "пишу", "текст"]
        )
        XCTAssertEqual(result?.replacement, "и")
    }

    func testRejectedConversionRequiresRepeatedUndoBeforeSuppression() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let store = SmartInputLearningStore(fileURL: storeURL)
        let service = SmartInputService(learningStore: store)

        let beforeLearning = service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            contextWords: ["пишу", "новый"]
        )
        XCTAssertEqual(beforeLearning?.replacement, "bygen")

        store.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        )

        let afterOneUndo = service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            contextWords: ["пишу", "новый"]
        )
        XCTAssertEqual(afterOneUndo?.replacement, "bygen")

        store.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        )

        let afterRepeatedUndo = service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            contextWords: ["пишу", "новый"]
        )
        XCTAssertNil(afterRepeatedUndo)
    }

    func testGlobalLearningUsesCorrectionsFromEveryApplication() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let store = SmartInputLearningStore(fileURL: storeURL)
        let service = SmartInputService(learningStore: store)

        store.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        )
        store.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Browser"
        )

        service.smartInputLearningScope = .global
        XCTAssertNil(service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            bundleID: "com.example.Other"
        ))
    }

    func testPerAppLearningKeepsCorrectionsIsolated() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let store = SmartInputLearningStore(fileURL: storeURL)
        let service = SmartInputService(learningStore: store)

        for _ in 0..<2 {
            store.recordRejectedConversion(
                mode: "bilingual",
                original: "инпут",
                replacement: "bygen",
                sourceLayoutID: "com.apple.keylayout.RussianWin",
                targetLayoutID: "com.apple.keylayout.US",
                bundleID: "com.example.Editor"
            )
        }

        service.smartInputLearningScope = .perApplication
        XCTAssertNil(service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            bundleID: "com.example.Editor"
        ))
        XCTAssertEqual(service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            bundleID: "com.example.Other"
        )?.replacement, "bygen")

        service.smartInputLearningScope = .global
        XCTAssertNil(service.checkBilingualConversion(
            for: "инпут",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            bundleID: "com.example.Other"
        ))
    }

    func testSnippetLookupAndPrefixHandling() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        service.textSnippets = [
            TextSnippet(trigger: "@@email", replacement: "me@example.com"),
            TextSnippet(trigger: "disabled", replacement: "ignored", isEnabled: false)
        ]

        XCTAssertTrue(service.isSnippetTriggerContinuation("@"))
        XCTAssertTrue(service.isSnippetTriggerContinuation("@@em"))
        XCTAssertFalse(service.isSnippetTriggerContinuation("@@email"))
        XCTAssertEqual(service.textSnippet(for: "@@email")?.replacement, "me@example.com")
        XCTAssertNil(service.textSnippet(for: "disabled"))
    }

    func testImmediateSnippetExpansionWinsOnExactMatch() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        service.textSnippetExpansionMode = .immediately
        service.textSnippets = [
            TextSnippet(trigger: ";a", replacement: "first"),
            TextSnippet(trigger: ";abc", replacement: "longer")
        ]

        let expansion = service.snippetExpansion(
            bufferedToken: ";",
            inputText: "a"
        )

        XCTAssertEqual(expansion?.snippet.replacement, "first")
        XCTAssertEqual(expansion?.original, ";a")
        XCTAssertEqual(expansion?.replacingToken, ";")
        XCTAssertEqual(expansion?.boundary, "")
    }

    func testAfterSpaceSnippetExpansionWaitsForLiteralSpace() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        service.textSnippetExpansionMode = .afterSpace
        service.textSnippets = [TextSnippet(trigger: "brb.", replacement: "be right back")]

        XCTAssertNil(service.snippetExpansion(bufferedToken: "brb", inputText: "."))
        XCTAssertTrue(service.shouldBufferSnippetInput("brb."))
        XCTAssertNil(service.snippetExpansion(bufferedToken: "brb.", inputText: ","))

        let expansion = service.snippetExpansion(bufferedToken: "brb.", inputText: " ")
        XCTAssertEqual(expansion?.original, "brb.")
        XCTAssertEqual(expansion?.replacingToken, "brb.")
        XCTAssertEqual(expansion?.boundary, " ")
    }

    func testRemoteSnippetExpansionPreservesRussianAndEnglishTypedCaseAtBoundary() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        service.textSnippetExpansionMode = .immediately
        service.textSnippets = [
            TextSnippet(
                trigger: "бля",
                replacement: "б** (бля)",
                isCaseSensitive: false,
                preservesTypedCase: true,
                requiresWordBoundary: true
            ),
            TextSnippet(
                trigger: "fucking",
                replacement: "f****** (fucking)",
                isCaseSensitive: false,
                preservesTypedCase: true,
                requiresWordBoundary: true
            )
        ]

        let cases = [
            ("бля", " ", "б** (бля)"),
            ("Бля", ".", "Б** (Бля)"),
            ("БЛЯ", ",", "Б** (БЛЯ)"),
            ("БЛя", "!", "Б** (БЛя)"),
            ("fucking", "?", "f****** (fucking)"),
            ("FUCKING", ")", "F****** (FUCKING)"),
            ("FuCkInG", "/", "F****** (FuCkInG)")
        ]

        for (typed, boundary, expected) in cases {
            let expansion = service.snippetExpansion(
                bufferedToken: typed,
                inputText: boundary
            )
            XCTAssertEqual(expansion?.replacement, expected, typed)
            XCTAssertEqual(expansion?.original, typed, typed)
            XCTAssertEqual(expansion?.boundary, boundary, typed)
        }
    }

    func testProbabilisticSnippetUsesPerMatchProbability() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let acceptedService = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL),
            probabilityRoll: { 0.049 },
            cooldownWordCount: { 15 }
        )
        let rejectedService = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL),
            probabilityRoll: { 0.05 },
            cooldownWordCount: { 15 }
        )
        let snippet = TextSnippet(
            trigger: "maybe",
            replacement: "the council will decide",
            isCaseSensitive: false,
            requiresWordBoundary: true,
            replacementProbability: 0.05
        )
        acceptedService.textSnippets = [snippet]
        rejectedService.textSnippets = [snippet]

        XCTAssertEqual(
            acceptedService.snippetExpansion(bufferedToken: "maybe", inputText: " ")?.replacement,
            "the council will decide"
        )
        XCTAssertNil(rejectedService.snippetExpansion(bufferedToken: "maybe", inputText: " "))
    }

    func testProbabilisticSnippetCooldownAllowsAtMostOneReplacementPerFifteenWords() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL),
            probabilityRoll: { 0 },
            cooldownWordCount: { 15 }
        )
        service.textSnippets = [
            TextSnippet(
                trigger: "hello",
                replacement: "Greetings, fellow citizen",
                isCaseSensitive: false,
                requiresWordBoundary: true,
                replacementProbability: 0.5
            )
        ]

        XCTAssertNotNil(service.snippetExpansion(bufferedToken: "hello", inputText: " "))
        for _ in 0..<15 {
            XCTAssertNil(service.snippetExpansion(bufferedToken: "hello", inputText: " "))
        }
        XCTAssertNotNil(service.snippetExpansion(bufferedToken: "hello", inputText: " "))
    }

    func testProbabilisticSnippetForcesEligibleMatchByTwentyFifthWord() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL),
            probabilityRoll: { 0.99 },
            cooldownWordCount: { 25 }
        )
        service.textSnippets = [
            TextSnippet(
                trigger: "ok",
                replacement: "your feedback has been noted",
                isCaseSensitive: false,
                requiresWordBoundary: true,
                replacementProbability: 0.05
            )
        ]

        for _ in 0..<24 {
            XCTAssertNil(service.snippetExpansion(bufferedToken: "ordinary", inputText: " "))
        }
        XCTAssertEqual(
            service.snippetExpansion(bufferedToken: "ok", inputText: " ")?.replacement,
            "your feedback has been noted"
        )
    }

    func testProbabilisticCooldownDoesNotBlockManualSnippets() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL),
            probabilityRoll: { 0 },
            cooldownWordCount: { 25 }
        )
        let probabilistic = TextSnippet(
            trigger: "hello",
            replacement: "Greetings, fellow citizen",
            isCaseSensitive: false,
            requiresWordBoundary: true,
            replacementProbability: 0.5
        )
        let manual = TextSnippet(
            trigger: "brb",
            replacement: "be right back",
            requiresWordBoundary: true
        )
        service.textSnippets = [probabilistic, manual]

        XCTAssertNotNil(service.snippetExpansion(bufferedToken: "hello", inputText: " "))
        XCTAssertEqual(
            service.snippetExpansion(bufferedToken: "brb", inputText: " ")?.replacement,
            "be right back"
        )
    }

    func testRemoteSnippetWaitsForWordBoundaryAndDoesNotExpandSharedPrefixEarly() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        service.textSnippetExpansionMode = .immediately
        service.textSnippets = [
            TextSnippet(
                trigger: "бля",
                replacement: "б** (бля)",
                isCaseSensitive: false,
                preservesTypedCase: true,
                requiresWordBoundary: true
            ),
            TextSnippet(
                trigger: "блядь",
                replacement: "б**** (блядь)",
                isCaseSensitive: false,
                preservesTypedCase: true,
                requiresWordBoundary: true
            )
        ]

        XCTAssertNil(service.snippetExpansion(bufferedToken: "бл", inputText: "я"))
        XCTAssertTrue(service.shouldBufferSnippetInput("бля"))
        XCTAssertNil(service.snippetExpansion(bufferedToken: "бля", inputText: "д"))
        XCTAssertTrue(service.shouldBufferSnippetInput("бляд"))
        XCTAssertNil(service.snippetExpansion(bufferedToken: "бляд", inputText: "ь"))
        XCTAssertTrue(service.shouldBufferSnippetInput("блядь"))

        let expansion = service.snippetExpansion(bufferedToken: "блядь", inputText: ".")
        XCTAssertEqual(expansion?.replacement, "б**** (блядь)")
        XCTAssertEqual(expansion?.boundary, ".")
    }

    func testSnippetReplacementUsesOneBackspaceUndo() {
        XCTAssertEqual(
            SmartInputService.replacementBackspaceAction(
                mode: "snippet",
                boundary: " ",
                boundaryBackspaceConsumed: false
            ),
            .undo(deleteBoundary: true)
        )
        XCTAssertEqual(
            SmartInputService.replacementBackspaceAction(
                mode: "snippet",
                boundary: "",
                boundaryBackspaceConsumed: false
            ),
            .undo(deleteBoundary: false)
        )
        XCTAssertEqual(
            SmartInputService.replacementBackspaceAction(
                mode: "bilingual",
                boundary: " ",
                boundaryBackspaceConsumed: false
            ),
            .deleteBoundary
        )
    }

    func testRemoteSnippetReplacementBackspaceDeletesNormallyInsteadOfUndoing() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(
            learningStore: SmartInputLearningStore(fileURL: storeURL)
        )
        let remoteSnippet = TextSnippet(trigger: "бля", replacement: "б** (бля)")
        let manualSnippet = TextSnippet(trigger: "brb", replacement: "be right back")
        service.remoteSnippetIDs = [remoteSnippet.id]

        XCTAssertFalse(service.shouldAllowBackspaceUndo(for: remoteSnippet))
        XCTAssertTrue(service.shouldAllowBackspaceUndo(for: manualSnippet))
        XCTAssertEqual(
            SmartInputService.replacementBackspaceAction(
                mode: "snippet",
                boundary: " ",
                boundaryBackspaceConsumed: false,
                allowsBackspaceUndo: false
            ),
            .deleteNormally
        )
    }

    func testSnippetLookupRespectsApplicationScope() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        let group = TextSnippetGroup(
            name: "Mail",
            applicationScope: SnippetApplicationScope(mode: .onlySelected, bundleIDs: ["com.apple.mail"])
        )
        service.textSnippetGroups = [group]
        service.textSnippets = [
            TextSnippet(name: "Signature", trigger: ";sig", replacement: "Regards", groupID: group.id)
        ]

        XCTAssertNotNil(service.textSnippet(for: ";sig", bundleID: "com.apple.mail"))
        XCTAssertNil(service.textSnippet(for: ";sig", bundleID: "com.apple.Notes"))
        XCTAssertTrue(service.isSnippetTriggerContinuation(";s", bundleID: "com.apple.mail"))
        XCTAssertFalse(service.isSnippetTriggerContinuation(";s", bundleID: "com.apple.Notes"))
    }

    func testWebsiteRulesMatchingAndAutoSwitching() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)
        let us = InputLayoutProfile(name: "U.S.", inputSourceID: "us")
        let russian = InputLayoutProfile(name: "Russian", inputSourceID: "ru")
        store.configuration = LayoutPilotConfiguration(
            automationEnabled: true,
            profiles: [us, russian],
            rules: [],
            websiteRules: [
                WebsiteLayoutRule(domain: "github.com", profileID: us.id, isEnabled: true),
                WebsiteLayoutRule(domain: "yandex.ru", profileID: russian.id, isEnabled: true)
            ]
        )

        let rule1 = store.configuration.websiteRules[0]
        XCTAssertTrue("github.com" == rule1.domain || "github.com".hasSuffix("." + rule1.domain))
        XCTAssertTrue("sub.github.com".hasSuffix("." + rule1.domain))
        XCTAssertFalse("othergithub.com".hasSuffix("." + rule1.domain))
    }

    func testCmdTInterception() {
        XCTAssertTrue(SmartInputService.shouldForceUSForBrowserNewTab(
            keyCode: 17,
            flags: [.maskCommand],
            bundleID: "com.google.Chrome"
        ))

        XCTAssertFalse(SmartInputService.shouldForceUSForBrowserNewTab(
            keyCode: 17,
            flags: [.maskCommand],
            bundleID: "com.apple.Terminal"
        ))

        XCTAssertFalse(SmartInputService.shouldForceUSForBrowserNewTab(
            keyCode: 49,
            flags: [.maskCommand],
            bundleID: "com.google.Chrome"
        ))
    }

    func testBrowserURLServiceDetection() {
        XCTAssertTrue(BrowserURLService.isBrowser(bundleID: "com.apple.Safari"))
        XCTAssertTrue(BrowserURLService.isBrowser(bundleID: "com.google.Chrome"))
        XCTAssertTrue(BrowserURLService.isBrowser(bundleID: "company.thebrowser.Browser"))
        XCTAssertFalse(BrowserURLService.isBrowser(bundleID: "com.apple.Terminal"))
    }

    func testWebsiteMonitorRunsOnlyForBrowsersWithEnabledRules() {
        XCTAssertTrue(LayoutAutomationEngine.shouldMonitorWebsite(
            bundleID: "com.apple.Safari",
            hasEnabledWebsiteRules: true
        ))
        XCTAssertFalse(LayoutAutomationEngine.shouldMonitorWebsite(
            bundleID: "com.apple.Safari",
            hasEnabledWebsiteRules: false
        ))
        XCTAssertFalse(LayoutAutomationEngine.shouldMonitorWebsite(
            bundleID: "com.apple.Terminal",
            hasEnabledWebsiteRules: true
        ))
    }

    func testVisibleSidebarSectionsHideDeveloperFeaturesAndIncludeSettings() {
        XCTAssertEqual(SidebarSection.visibleCases(for: Set(FeatureModule.allCases)), [
            .overview,
            .snippets,
            .smartDanish,
            .smartBilingual,
            .rules,
            .websites,
            .profiles,
            .settings
        ])
        let visible = SidebarSection.visibleCases(for: [.snippets])
        XCTAssertEqual(visible, [.overview, .snippets, .settings])
        XCTAssertFalse(visible.contains(.chat))
        XCTAssertFalse(visible.contains(.diagnostics))
    }

    func testBrowserURLServiceExtractsNormalizedDomain() {
        XCTAssertEqual(
            BrowserURLService.domain(from: "https://Sub.Example.com/path"),
            "sub.example.com"
        )
        XCTAssertNil(BrowserURLService.domain(from: "not a url"))
    }

    func testSpellingAutocorrectMisspelledCheck() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("learning.json")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)
        let service = SmartInputService(learningStore: learningStore)
        
        // Ensure spelling autocorrect is enabled
        service.spellingAutocorrectEnabled = true
        
        // "teh" is misspelled in English
        XCTAssertTrue(service.isMisspelled("teh", language: "en", layoutID: "com.apple.keylayout.US"))
        // "the" is correct in English
        XCTAssertFalse(service.isMisspelled("the", language: "en", layoutID: "com.apple.keylayout.US"))
        
        // Add "teh" to accepted words
        for _ in 0..<3 {
            _ = learningStore.recordAcceptedWord("teh", layoutID: "com.apple.keylayout.US", bundleID: "com.apple.Notes")
        }
        
        // Now "teh" should not be considered misspelled
        XCTAssertFalse(service.isMisspelled("teh", language: "en", layoutID: "com.apple.keylayout.US"))
    }

    func testAcceptedWordsAreScopedToLayoutAndIgnoreNonWords() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("learning.json")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)

        for _ in 0..<3 {
            learningStore.recordAcceptedWord("teh", layoutID: "com.apple.keylayout.US", bundleID: "com.apple.Notes")
            learningStore.recordAcceptedWord("123", layoutID: "com.apple.keylayout.US", bundleID: "com.apple.Notes")
            learningStore.recordAcceptedWord("abc123", layoutID: "com.apple.keylayout.US", bundleID: "com.apple.Notes")
        }

        XCTAssertTrue(learningStore.isWordAccepted("teh", layoutID: "com.apple.keylayout.US"))
        XCTAssertFalse(learningStore.isWordAccepted("teh", layoutID: "com.apple.keylayout.RussianWin"))
        XCTAssertFalse(learningStore.isWordAccepted("123", layoutID: "com.apple.keylayout.US"))
        XCTAssertFalse(learningStore.isWordAccepted("abc123", layoutID: "com.apple.keylayout.US"))

        learningStore.flushPendingWrites()
        let reloaded = SmartInputLearningStore(fileURL: learningURL)
        XCTAssertTrue(reloaded.isWordAccepted("teh", layoutID: "com.apple.keylayout.US"))
    }

    func testAcceptedWordsFollowConfiguredLearningScope() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("learning.json")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)
        let service = SmartInputService(learningStore: learningStore)

        for _ in 0..<3 {
            learningStore.recordAcceptedWord(
                "teh",
                layoutID: "com.apple.keylayout.US",
                bundleID: "com.apple.Notes"
            )
        }

        service.smartInputLearningScope = .global
        XCTAssertFalse(service.isMisspelled(
            "teh",
            language: "en",
            layoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Other"
        ))

        service.smartInputLearningScope = .perApplication
        XCTAssertFalse(service.isMisspelled(
            "teh",
            language: "en",
            layoutID: "com.apple.keylayout.US",
            bundleID: "com.apple.Notes"
        ))
        XCTAssertTrue(service.isMisspelled(
            "teh",
            language: "en",
            layoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Other"
        ))
        XCTAssertFalse(service.isMisspelled(
            "teh",
            language: "en",
            layoutID: "com.apple.keylayout.US",
            bundleID: nil
        ))
    }

    func testRejectedConversionsAreScopedToApplication() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("learning.json")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)

        learningStore.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        )
        learningStore.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Other"
        )

        XCTAssertNil(learningStore.suppressionReason(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        ))
        XCTAssertEqual(
            learningStore.suppressionReason(
                mode: "bilingual",
                original: "инпут",
                replacement: "bygen",
                sourceLayoutID: "com.apple.keylayout.RussianWin",
                targetLayoutID: "com.apple.keylayout.US"
            ),
            "user_rejected_conversion"
        )

        learningStore.recordRejectedConversion(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Editor"
        )

        XCTAssertEqual(
            learningStore.suppressionReason(
                mode: "bilingual",
                original: "инпут",
                replacement: "bygen",
                sourceLayoutID: "com.apple.keylayout.RussianWin",
                targetLayoutID: "com.apple.keylayout.US",
                bundleID: "com.example.Editor"
            ),
            "user_rejected_conversion"
        )
        XCTAssertNil(learningStore.suppressionReason(
            mode: "bilingual",
            original: "инпут",
            replacement: "bygen",
            sourceLayoutID: "com.apple.keylayout.RussianWin",
            targetLayoutID: "com.apple.keylayout.US",
            bundleID: "com.example.Other"
        ))
    }

    func testEventLogSkipsBackspaceBufferNoise() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logURL = tempDirectory.appendingPathComponent("events.jsonl")
        let eventLog = SmartInputEventLog(fileURL: logURL)

        eventLog.record(.init(kind: "backspace_buffer_update", bufferBefore: "word", bufferAfter: "wor"))
        eventLog.record(.init(kind: "replacement", original: "rfr", replacement: "как"))

        let lines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SmartInputEventLog.Event.self, from: Data(lines[0].utf8)).kind, "replacement")
    }
    
    func testSpellingSuggestions() {
        let service = SmartInputService.shared
        let suggestions = service.suggestionsForWord("teh", language: "en")
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.contains("the"))
    }

    func testBootstrapSpellingVocabularyFromLogs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("smart-input-learning.json")
        let logURL = tempDirectory.appendingPathComponent("smart-input-events.jsonl")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)

        let event = SmartInputEventLog.Event(
            kind: "replacement",
            mode: "bilingual",
            original: "ghbdtn",
            replacement: "привет"
        )
        let event2 = SmartInputEventLog.Event(
            kind: "accepted_word_promoted",
            original: "тестикслово"
        )
        let event3 = SmartInputEventLog.Event(
            kind: "backspace_buffer_update",
            bufferBefore: "adsfasdf",
            bufferAfter: "adsfasd"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        var line1 = try encoder.encode(event)
        line1.append(0x0A)
        var line2 = try encoder.encode(event2)
        line2.append(0x0A)
        var line3 = try encoder.encode(event3)
        line3.append(0x0A)

        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line1 + line2 + line3).write(to: logURL)

        learningStore.bootstrapSpellingVocabularyFromLogs(
            checker: NSSpellChecker.shared,
            logURLs: [logURL]
        )

        // "привет" is correct in Russian, so it shouldn't be added to acceptedWords
        XCTAssertFalse(learningStore.isWordAccepted("привет"))

        // "тестикслово" is misspelled, so it should be bootstrapped and accepted!
        XCTAssertTrue(learningStore.isWordAccepted("тестикслово"))
        XCTAssertFalse(learningStore.isWordAccepted("adsfasdf"))
    }
}

private final class FakeInputSourceClient: InputSourceClient {
    var currentSourceID: String
    private(set) var activatedSourceIDs: [String] = []

    init(currentSourceID: String) {
        self.currentSourceID = currentSourceID
    }

    func currentInputSourceID() -> String? {
        currentSourceID
    }

    func availableInputSources() -> [InputSourceInfo] {
        [
            InputSourceInfo(sourceID: "us", localizedName: "U.S."),
            InputSourceInfo(sourceID: "ru", localizedName: "Russian")
        ]
    }

    func activateInputSource(withID inputSourceID: String) throws {
        activatedSourceIDs.append(inputSourceID)
        currentSourceID = inputSourceID
    }
}
