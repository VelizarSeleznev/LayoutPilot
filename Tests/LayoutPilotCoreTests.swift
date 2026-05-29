import Carbon
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

    func testBilingualConversion() {
        let service = SmartInputService.shared
        
        // Assert that short words/abbreviations of length < 3 never trigger bilingual conversion
        XCTAssertNil(service.checkBilingualConversion(for: "дс"))
        XCTAssertNil(service.checkBilingualConversion(for: "lc"))
        XCTAssertNil(service.checkBilingualConversion(for: "a"))
        
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
            
            // "ghbdtn" is English layout for "привет", should trigger conversion to Russian
            let privetResult = service.checkBilingualConversion(for: "ghbdtn")
            XCTAssertNotNil(privetResult)
            XCTAssertEqual(privetResult?.replacement, "привет")
        } else if isRussian {
            // Under Russian layout, "привет" is valid Russian and should not trigger conversion
            XCTAssertNil(service.checkBilingualConversion(for: "привет"))
            
            // "цщкдв" is Russian layout for "world", should trigger conversion to English
            let worldResult = service.checkBilingualConversion(for: "цщкдв")
            XCTAssertNotNil(worldResult)
            XCTAssertEqual(worldResult?.replacement, "world")
        }
    }
}
