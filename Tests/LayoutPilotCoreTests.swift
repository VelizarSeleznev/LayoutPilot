import LayoutPilotCore
import XCTest

@MainActor
final class LayoutPilotCoreTests: XCTestCase {
    func testDefaultConfigurationIncludesSeedProfilesAndRules() {
        let configuration = LayoutPilotConfiguration.default()

        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertGreaterThanOrEqual(configuration.rules.count, 3)
        XCTAssertEqual(configuration.rules.first?.applicationBundleID, "com.microsoft.Word")
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
}
