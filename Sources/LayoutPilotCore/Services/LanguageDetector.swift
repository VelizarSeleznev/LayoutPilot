import Foundation
import NaturalLanguage

/// Language detection built on Apple's `NLLanguageRecognizer`.
///
/// This is intentionally language-agnostic: callers pass the set of languages
/// the user actually types (`constraints`) instead of the detector hard-coding a
/// Russian/English assumption. That lets the same engine generalize to any pair
/// of layouts a user configures.
///
/// Empirically (see `LanguageDetectorTests`), `NLLanguageRecognizer` is unreliable
/// on a single short token — Cyrillic gibberish can score as confidently Bulgarian,
/// Latin gibberish as confidently Croatian. It becomes accurate on a *run of words*.
/// So the intended use is to feed it the recent typing context, not one token in
/// isolation, and to constrain it to the candidate languages.
public struct LanguageDetector: Sendable {
    /// Languages the recognizer is allowed to choose from. Empty = no constraint
    /// (recognizer considers every language it knows).
    public var constraints: [NLLanguage]

    /// Prior probabilities to bias detection, e.g. the user's primary language.
    public var hints: [NLLanguage: Double]

    public init(constraints: [NLLanguage] = [], hints: [NLLanguage: Double] = [:]) {
        self.constraints = constraints
        self.hints = hints
    }

    public struct Guess: Equatable, Sendable {
        public let language: NLLanguage
        public let confidence: Double

        public init(language: NLLanguage, confidence: Double) {
            self.language = language
            self.confidence = confidence
        }
    }

    private func makeRecognizer() -> NLLanguageRecognizer {
        let recognizer = NLLanguageRecognizer()
        if !constraints.isEmpty {
            recognizer.languageConstraints = constraints
        }
        if !hints.isEmpty {
            recognizer.languageHints = hints
        }
        return recognizer
    }

    /// Ranked language hypotheses for `text`, most likely first is not guaranteed by
    /// the dictionary; callers should read `dominantLanguage`/`bestGuess` for the top pick.
    public func hypotheses(for text: String, maximum: Int = 3) -> [NLLanguage: Double] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        let recognizer = makeRecognizer()
        recognizer.processString(trimmed)
        return recognizer.languageHypotheses(withMaximum: maximum)
    }

    public func dominantLanguage(of text: String) -> NLLanguage? {
        bestGuess(for: text)?.language
    }

    /// Best single guess for `text` with its confidence (0...1), or nil for empty input.
    public func bestGuess(for text: String) -> Guess? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = makeRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return nil
        }
        let confidence = recognizer.languageHypotheses(withMaximum: 5)[dominant] ?? 0
        return Guess(language: dominant, confidence: confidence)
    }

    /// Detect the dominant language of a run of recent words.
    ///
    /// This is the reliable entry point: joining the words into a phrase gives the
    /// recognizer enough signal to be accurate, unlike a single token.
    public func dominantLanguage(ofContext words: [String]) -> Guess? {
        let phrase = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return bestGuess(for: phrase)
    }
}
