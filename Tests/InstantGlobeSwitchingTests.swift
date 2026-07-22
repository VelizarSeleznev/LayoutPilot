@testable import LayoutPilotCore
import XCTest

@MainActor
final class InstantGlobeSwitchingTests: XCTestCase {
    func testConfigurationWithoutInstantGlobeSettingDefaultsToOff() throws {
        let data = Data(#"{"profiles":[],"rules":[]}"#.utf8)

        let configuration = try JSONDecoder().decode(LayoutPilotConfiguration.self, from: data)

        XCTAssertFalse(configuration.instantGlobeSwitchingEnabled)
    }

    func testStorePersistsInstantGlobeSetting() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("configuration.json")
        let store = LayoutPilotStore(fileURL: fileURL)

        store.setInstantGlobeSwitchingEnabled(true)

        XCTAssertTrue(store.configuration.instantGlobeSwitchingEnabled)
        XCTAssertTrue(LayoutPilotStore(fileURL: fileURL).configuration.instantGlobeSwitchingEnabled)
    }

    func testSystemGlobeActionIsDisabledAndRestored() {
        let preferences = FakeSystemGlobeKeyActionPreferences(action: 1)
        let defaults = isolatedDefaults()
        let service = SystemGlobeKeyActionService(
            preferences: preferences,
            restorationDefaults: defaults
        )

        XCTAssertTrue(service.setLayoutPilotControlEnabled(true))
        XCTAssertEqual(preferences.action, SystemGlobeKeyActionService.doNothingAction)

        // Repeated synchronization must not replace the original action with zero.
        XCTAssertTrue(service.setLayoutPilotControlEnabled(true))
        XCTAssertTrue(service.setLayoutPilotControlEnabled(false))
        XCTAssertEqual(preferences.action, 1)
    }

    func testExistingDoNothingActionIsLeftUnchangedWhenFeatureTurnsOff() {
        let preferences = FakeSystemGlobeKeyActionPreferences(action: 0)
        let defaults = isolatedDefaults()
        let service = SystemGlobeKeyActionService(
            preferences: preferences,
            restorationDefaults: defaults
        )

        XCTAssertTrue(service.setLayoutPilotControlEnabled(true))
        XCTAssertTrue(service.setLayoutPilotControlEnabled(false))
        XCTAssertEqual(preferences.action, 0)
    }

    func testDisabledStateMachinePassesGlobeThrough() {
        var state = GlobeKeyStateMachine()

        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: true, isEnabled: false),
            .passThrough
        )
        XCTAssertFalse(state.isGlobeDown)
    }

    func testStateMachineCyclesOncePerCompletePress() {
        var state = GlobeKeyStateMachine()

        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: true, isEnabled: true),
            .consumeAndCycle
        )
        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: true, isEnabled: true),
            .consume
        )
        XCTAssertEqual(
            state.handle(isGlobeEvent: false, isDown: true, isEnabled: true),
            .passThrough
        )
        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: false, isEnabled: true),
            .consume
        )
        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: true, isEnabled: true),
            .consumeAndCycle
        )
    }

    func testStateMachineResetAllowsNextPressToCycle() {
        var state = GlobeKeyStateMachine()
        _ = state.handle(isGlobeEvent: true, isDown: true, isEnabled: true)

        state.reset()

        XCTAssertEqual(
            state.handle(isGlobeEvent: true, isDown: true, isEnabled: true),
            .consumeAndCycle
        )
    }

    func testCyclerUsesSourceOrderAndWraps() throws {
        let client = FakeInstantInputSourceClient(
            currentSourceID: "en",
            sources: Self.sources
        )
        let cycler = InstantInputSourceCycler(client: client)
        cycler.refreshSources()

        XCTAssertEqual(try cycler.cycleToNextSource()?.sourceID, "ru")
        XCTAssertEqual(try cycler.cycleToNextSource()?.sourceID, "da")
        XCTAssertEqual(try cycler.cycleToNextSource()?.sourceID, "en")
        XCTAssertEqual(client.activatedSourceIDs, ["ru", "da", "en"])
    }

    func testCyclerSelectsFirstSourceWhenCurrentSourceIsUnknown() throws {
        let client = FakeInstantInputSourceClient(
            currentSourceID: "unknown",
            sources: Self.sources
        )
        let cycler = InstantInputSourceCycler(client: client)
        cycler.refreshSources()

        XCTAssertEqual(try cycler.cycleToNextSource()?.sourceID, "en")
        XCTAssertEqual(client.activatedSourceIDs, ["en"])
        XCTAssertEqual(client.availableInputSourcesCallCount, 2)
    }

    func testCyclerDoesNothingWithFewerThanTwoSources() throws {
        let client = FakeInstantInputSourceClient(
            currentSourceID: "en",
            sources: [Self.sources[0]]
        )
        let cycler = InstantInputSourceCycler(client: client)
        cycler.refreshSources()

        XCTAssertNil(try cycler.cycleToNextSource())
        XCTAssertTrue(client.activatedSourceIDs.isEmpty)
    }

    func testCyclerRefreshesAndRetriesAfterActivationFailure() throws {
        let client = FakeInstantInputSourceClient(
            currentSourceID: "en",
            sources: Self.sources,
            activationFailuresRemaining: 1
        )
        let cycler = InstantInputSourceCycler(client: client)
        cycler.refreshSources()

        XCTAssertEqual(try cycler.cycleToNextSource()?.sourceID, "ru")
        XCTAssertEqual(client.activationAttempts, ["ru", "ru"])
        XCTAssertEqual(client.availableInputSourcesCallCount, 2)
    }

    private static let sources = [
        InputSourceInfo(sourceID: "en", localizedName: "U.S.", languageTag: "en-US"),
        InputSourceInfo(sourceID: "ru", localizedName: "Russian", languageTag: "ru"),
        InputSourceInfo(sourceID: "da", localizedName: "Danish", languageTag: "da"),
    ]

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "InstantGlobeSwitchingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeInstantInputSourceClient: InputSourceClient {
    var currentSourceIDValue: String?
    var sources: [InputSourceInfo]
    var activationFailuresRemaining: Int
    private(set) var availableInputSourcesCallCount = 0
    private(set) var activationAttempts: [String] = []
    private(set) var activatedSourceIDs: [String] = []

    init(
        currentSourceID: String?,
        sources: [InputSourceInfo],
        activationFailuresRemaining: Int = 0
    ) {
        self.currentSourceIDValue = currentSourceID
        self.sources = sources
        self.activationFailuresRemaining = activationFailuresRemaining
    }

    func currentInputSourceID() -> String? {
        currentSourceIDValue
    }

    func availableInputSources() -> [InputSourceInfo] {
        availableInputSourcesCallCount += 1
        return sources
    }

    func activateInputSource(withID inputSourceID: String) throws {
        activationAttempts.append(inputSourceID)
        if activationFailuresRemaining > 0 {
            activationFailuresRemaining -= 1
            throw FakeActivationError.failed
        }
        activatedSourceIDs.append(inputSourceID)
        currentSourceIDValue = inputSourceID
    }
}

private enum FakeActivationError: Error {
    case failed
}

private final class FakeSystemGlobeKeyActionPreferences: SystemGlobeKeyActionPreferences {
    var action: Int?

    init(action: Int?) {
        self.action = action
    }

    func currentAction() -> Int? {
        action
    }

    func setAction(_ action: Int) -> Bool {
        self.action = action
        return true
    }
}
