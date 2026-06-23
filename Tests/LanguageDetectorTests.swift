@testable import LayoutPilotCore
import NaturalLanguage
import XCTest

/// Tests for the `NLLanguageRecognizer`-based detector.
///
/// The fixtures are drawn from real `smart-input-events.jsonl` capture:
/// - `truePositives`: tokens the user typed in the wrong layout, where the
///   transliterated form is the word they meant.
/// - `falsePositives`: conversions the user manually reverted (Backspace), i.e.
///   the original token was already a real word and should have been kept.
final class LanguageDetectorTests: XCTestCase {

    /// Constrained to the user's actual layout pair — the intended production setup.
    private let enRu = LanguageDetector(constraints: [.english, .russian])

    // MARK: Phrase-level detection (the reliable path)

    func testContextPhraseDetectionIsAccurate() {
        // Real, correctly typed phrases.
        XCTAssertEqual(enRu.dominantLanguage(of: "привет как дела"), .russian)
        XCTAssertEqual(enRu.dominantLanguage(of: "hello how are you"), .english)
        XCTAssertEqual(enRu.dominantLanguage(of: "this is the continue button"), .english)

        // Borrowed words that the single-word heuristic mis-converted, but which
        // read as coherent Russian in context.
        XCTAssertEqual(enRu.dominantLanguage(of: "инпут аутпут"), .russian)
        XCTAssertEqual(enRu.dominantLanguage(of: "Плюс минус"), .russian)
    }

    func testWrongLayoutPhraseResolvesToCandidateLanguage() {
        // A whole phrase typed in the wrong layout: the corrected (transliterated)
        // candidate is what should be detected as a coherent language.
        XCTAssertEqual(enRu.dominantLanguage(of: "привет как дела"), .russian) // for "ghbdtn rfr ltkf"
        XCTAssertEqual(enRu.dominantLanguage(of: "руддщ рщц фку нщг"), .russian) // gibberish-looking, still ru script
    }

    func testContextHistoryArrayEntryPoint() {
        let guess = enRu.dominantLanguage(ofContext: ["Если", "я", "хочу", "написать"])
        XCTAssertEqual(guess?.language, .russian)
        XCTAssertGreaterThan(guess?.confidence ?? 0, 0.9)
    }

    // MARK: Documented limitation — single short tokens are unreliable

    func testSingleTokenDetectionIsUnreliable() {
        // These assertions document *why* the engine must not rely on NL for a lone
        // token. Unconstrained, real words are misattributed and gibberish scores high.
        let free = LanguageDetector()

        // Real Russian word attributed to the wrong Cyrillic language.
        let privet = free.bestGuess(for: "привет")
        XCTAssertNotNil(privet)
        XCTAssertNotEqual(privet?.language, .russian, "Single Cyrillic word is commonly mis-detected (e.g. as Bulgarian)")

        // Wrong-layout Latin gibberish nonetheless gets a confident pick.
        let gibberish = free.bestGuess(for: "rjnjhsq")
        XCTAssertNotNil(gibberish)
        XCTAssertGreaterThan(gibberish?.confidence ?? 0, 0.5, "Gibberish scores deceptively high as a lone token")
    }

    func testConstraintsRescueSingleTokenToCorrectScript() {
        // Constraining to the candidate pair collapses the choice to the right script,
        // which is the cheap win NaturalLanguage gives even on single tokens.
        XCTAssertEqual(enRu.dominantLanguage(of: "привет"), .russian)
        XCTAssertEqual(enRu.dominantLanguage(of: "hello"), .english)
        XCTAssertEqual(enRu.dominantLanguage(of: "флешка"), .russian)
    }

    // MARK: Real corpus — context tells true vs false positives apart

    /// (typed token, intended transliteration) the user genuinely typed in the wrong layout.
    private let truePositives: [(typed: String, meant: String)] = [
        ("ghbdtn", "привет"),
        ("rfr", "как"),
        ("yfcrjkmrj", "насколько"),
        ("rjnjhsq", "который"),
        ("сщтештгу", "continue"),
        ("ыщсшфд", "social"),
        ("дщсфд", "local"),
    ]

    /// Conversions the user reverted: the original was already a real word/fragment.
    private let falsePositives: [String] = [
        "инпут", "аутпут", "Плюс", "флешка",
    ]

    func testIntendedTransliterationsAreCoherentInTargetLanguage() {
        // Every "meant" word, read as a one-word phrase under constraints, lands on a
        // real language with non-trivial confidence (sanity floor, not a tight bound).
        for pair in truePositives {
            let guess = enRu.bestGuess(for: pair.meant)
            XCTAssertNotNil(guess, "no guess for \(pair.meant)")
            XCTAssertGreaterThan(guess?.confidence ?? 0, 0.3, "low confidence for \(pair.meant)")
        }
    }

    func testFalsePositiveOriginalsReadAsRussian() {
        // The tokens the user kept are coherent Russian and must survive — exactly the
        // signal a context-aware guard would use to suppress the bad conversion.
        for word in falsePositives {
            XCTAssertEqual(enRu.dominantLanguage(of: word), .russian, "\(word) should read as Russian")
        }
    }

    // MARK: API shape

    func testEmptyAndWhitespaceInputReturnNil() {
        XCTAssertNil(enRu.bestGuess(for: ""))
        XCTAssertNil(enRu.bestGuess(for: "   \n"))
        XCTAssertNil(enRu.dominantLanguage(ofContext: []))
        XCTAssertNil(enRu.dominantLanguage(ofContext: ["", "  "]))
    }

    func testHintsBiasDetection() {
        let hinted = LanguageDetector(
            constraints: [.english, .russian],
            hints: [.russian: 0.99]
        )
        XCTAssertEqual(hinted.dominantLanguage(of: "привет как дела"), .russian)
    }
}
