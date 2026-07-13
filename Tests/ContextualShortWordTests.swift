@testable import LayoutPilotCore
import XCTest

@MainActor
final class ContextualShortWordTests: XCTestCase {
    func testSingleLetterIsRecoveredWhenFollowingWordConfirmsRussianLayout() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        let conversion = service.contextualPhraseConversion(
            precedingToken: "f",
            separator: " ",
            precedingSourceLayoutID: "com.apple.keylayout.US",
            followingOriginal: "rfr",
            followingReplacement: "как",
            followingTargetLayoutID: "com.apple.keylayout.RussianWin"
        )

        XCTAssertEqual(conversion?.original, "f rfr")
        XCTAssertEqual(conversion?.replacement, "а как")
        XCTAssertEqual(conversion?.precedingReplacement, "а")
    }

    func testValidEnglishSingleLetterIsNotRewrittenByRussianFollowingWord() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        XCTAssertNil(service.contextualPhraseConversion(
            precedingToken: "a",
            separator: " ",
            precedingSourceLayoutID: "com.apple.keylayout.US",
            followingOriginal: "rfr",
            followingReplacement: "как",
            followingTargetLayoutID: "com.apple.keylayout.RussianWin"
        ))
    }

    func testTwoAndThreeLetterTokensUseTheSameFollowingWordContext() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        let cases = [
            (original: "nj", expected: "то как"),
            (original: "xnj", expected: "что как"),
        ]

        for item in cases {
            let conversion = service.contextualPhraseConversion(
                precedingToken: item.original,
                separator: " ",
                precedingSourceLayoutID: "com.apple.keylayout.US",
                followingOriginal: "rfr",
                followingReplacement: "как",
                followingTargetLayoutID: "com.apple.keylayout.RussianWin"
            )
            XCTAssertEqual(conversion?.replacement, item.expected)
        }
    }

    func testSingleLetterIsNotRewrittenWithoutMatchingFollowingLanguage() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        XCTAssertNil(service.contextualPhraseConversion(
            precedingToken: "f",
            separator: " ",
            precedingSourceLayoutID: "com.apple.keylayout.US",
            followingOriginal: "hello",
            followingReplacement: "hello",
            followingTargetLayoutID: nil
        ))
    }

    func testContextualRecoveryAlsoWorksFromRussianLayoutToEnglish() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))

        let conversion = service.contextualPhraseConversion(
            precedingToken: "ш",
            separator: " ",
            precedingSourceLayoutID: "com.apple.keylayout.RussianWin",
            followingOriginal: "цщкдв",
            followingReplacement: "world",
            followingTargetLayoutID: "com.apple.keylayout.US"
        )

        XCTAssertEqual(conversion?.replacement, "i world")
    }

    func testRepeatedUndoSuppressesTheSameContextualPhrase() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("smart-input-learning.json")
        let store = SmartInputLearningStore(fileURL: storeURL)
        let service = SmartInputService(learningStore: store)

        for _ in 0..<2 {
            store.recordRejectedConversion(
                mode: "bilingual_context",
                original: "f rfr",
                replacement: "а как",
                sourceLayoutID: "com.apple.keylayout.US",
                targetLayoutID: "com.apple.keylayout.RussianWin",
                bundleID: "com.example.Editor"
            )
        }

        XCTAssertNil(service.contextualPhraseConversion(
            precedingToken: "f",
            separator: " ",
            precedingSourceLayoutID: "com.apple.keylayout.US",
            followingOriginal: "rfr",
            followingReplacement: "как",
            followingTargetLayoutID: "com.apple.keylayout.RussianWin"
        ))
    }
}
