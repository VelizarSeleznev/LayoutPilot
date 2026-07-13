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

    func testStoreUpsertsAndDeduplicatesTextSnippets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        store.upsertTextSnippet(TextSnippet(trigger: " @@email ", replacement: "first@example.com"))
        store.upsertTextSnippet(TextSnippet(trigger: "@@email", replacement: "second@example.com"))
        store.upsertTextSnippet(TextSnippet(trigger: "", replacement: "ignored"))

        XCTAssertEqual(store.configuration.textSnippets.count, 1)
        XCTAssertEqual(store.configuration.textSnippets.first?.trigger, "@@email")
        XCTAssertEqual(store.configuration.textSnippets.first?.replacement, "second@example.com")
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

        // Record 2 rejections for 'rfr' -> 'как' conversion
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
        // Since it is explicitly rejected, it should be suppressed with 'user_rejected_conversion' which must NOT be bypassed!
        let rfrUSAfterRejected = service.checkBilingualConversion(for: "rfr", sourceLayoutID: "com.apple.keylayout.US")
        XCTAssertNil(rfrUSAfterRejected)
        
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
        XCTAssertEqual(SidebarSection.visibleCases, [
            .overview,
            .rules,
            .websites,
            .profiles,
            .snippets,
            .settings
        ])
        XCTAssertFalse(SidebarSection.visibleCases.contains(.chat))
        XCTAssertFalse(SidebarSection.visibleCases.contains(.diagnostics))
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
    
    func testSpellingSuggestions() {
        let service = SmartInputService.shared
        let suggestions = service.suggestionsForWord("teh", language: "en")
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.contains("the"))
    }

    func testBootstrapSpellingVocabularyFromLogs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let learningURL = tempDirectory.appendingPathComponent("smart-input-learning.json")
        let learningStore = SmartInputLearningStore(fileURL: learningURL)
        
        // Let's create a temporary event log
        let logURL = try LayoutPilotPaths.smartInputEventLogURL()
        try? FileManager.default.removeItem(at: logURL)
        
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
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        var line1 = try encoder.encode(event)
        line1.append(0x0A)
        var line2 = try encoder.encode(event2)
        line2.append(0x0A)
        
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line1 + line2).write(to: logURL)
        
        // Bootstrap
        learningStore.bootstrapSpellingVocabularyFromLogs(checker: NSSpellChecker.shared)
        
        // "привет" is correct in Russian, so it shouldn't be added to acceptedWords
        XCTAssertFalse(learningStore.isWordAccepted("привет"))
        
        // "тестикслово" is misspelled, so it should be bootstrapped and accepted!
        XCTAssertTrue(learningStore.isWordAccepted("тестикслово"))
        
        // Cleanup log
        try? FileManager.default.removeItem(at: logURL)
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
