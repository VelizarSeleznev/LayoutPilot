import AppKit
import Foundation
import OSLog

public final class SmartInputLearningStore: @unchecked Sendable {
    public static let shared = SmartInputLearningStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "SmartInputLearning"
    )

    private var state: State
    private let acceptedWordPromotionCount = 3
    private let rejectedConversionSuppressionCount = 2

    public convenience init() {
        let url = (try? LayoutPilotPaths.smartInputLearningURL()) ??
            FileManager.default.temporaryDirectory.appendingPathComponent(LayoutPilotPaths.smartInputLearningFileName)
        self.init(fileURL: url)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    @discardableResult
    public func recordAcceptedWord(_ word: String, layoutID: String?, bundleID: String?) -> WordLearningOutcome {
        let normalized = Self.normalizedWord(word)
        guard !normalized.isEmpty else {
            return WordLearningOutcome(count: 0, wasPromoted: false)
        }

        lock.lock()
        defer { lock.unlock() }

        let key = Self.wordKey(word: normalized, layoutID: layoutID)
        let previousCount = state.acceptedWords[key]?.count ?? 0
        var entry = state.acceptedWords[key] ?? AcceptedWordEntry(
            word: normalized,
            layoutID: layoutID,
            count: 0,
            firstSeen: Date(),
            lastSeen: Date(),
            bundleIDs: []
        )
        entry.count += 1
        entry.lastSeen = Date()
        if let bundleID, !bundleID.isEmpty {
            entry.bundleIDs.insert(bundleID)
        }
        state.acceptedWords[key] = entry
        saveLocked()

        let wasPromoted = previousCount < acceptedWordPromotionCount &&
            entry.count >= acceptedWordPromotionCount
        if wasPromoted {
            logger.info("Promoted accepted smart-input word length=\(normalized.count, privacy: .public) layout=\(layoutID ?? "unknown", privacy: .public)")
        }
        return WordLearningOutcome(count: entry.count, wasPromoted: wasPromoted)
    }

    public func recordRejectedConversion(
        mode: String,
        original: String,
        replacement: String,
        sourceLayoutID: String?,
        targetLayoutID: String?,
        bundleID: String?
    ) {
        let original = Self.normalizedWord(original)
        let replacement = Self.normalizedWord(replacement)
        guard !original.isEmpty, !replacement.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let key = Self.conversionKey(
            mode: mode,
            original: original,
            replacement: replacement,
            sourceLayoutID: sourceLayoutID,
            targetLayoutID: targetLayoutID
        )
        var entry = state.conversions[key] ?? ConversionEntry(
            mode: mode,
            original: original,
            replacement: replacement,
            sourceLayoutID: sourceLayoutID,
            targetLayoutID: targetLayoutID,
            acceptedCount: 0,
            rejectedCount: 0,
            firstSeen: Date(),
            lastSeen: Date(),
            bundleIDs: []
        )
        entry.rejectedCount += 1
        entry.lastSeen = Date()
        if let bundleID, !bundleID.isEmpty {
            entry.bundleIDs.insert(bundleID)
        }
        state.conversions[key] = entry

        let wordKey = Self.wordKey(word: original, layoutID: sourceLayoutID)
        var wordEntry = state.acceptedWords[wordKey] ?? AcceptedWordEntry(
            word: original,
            layoutID: sourceLayoutID,
            count: 0,
            firstSeen: Date(),
            lastSeen: Date(),
            bundleIDs: []
        )
        wordEntry.count += 1
        wordEntry.lastSeen = Date()
        if let bundleID, !bundleID.isEmpty {
            wordEntry.bundleIDs.insert(bundleID)
        }
        state.acceptedWords[wordKey] = wordEntry

        saveLocked()
        logger.info("Rejected smart-input conversion mode=\(mode, privacy: .public) originalLength=\(original.count, privacy: .public) replacementLength=\(replacement.count, privacy: .public)")
    }

    public func suppressionReason(
        mode: String,
        original: String,
        replacement: String,
        sourceLayoutID: String?,
        targetLayoutID: String?
    ) -> String? {
        let original = Self.normalizedWord(original)
        let replacement = Self.normalizedWord(replacement)
        guard !original.isEmpty, !replacement.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let key = Self.conversionKey(
            mode: mode,
            original: original,
            replacement: replacement,
            sourceLayoutID: sourceLayoutID,
            targetLayoutID: targetLayoutID
        )
        if let conversion = state.conversions[key] {
            return conversion.rejectedCount >= rejectedConversionSuppressionCount
                ? "user_rejected_conversion"
                : nil
        }

        let wordKey = Self.wordKey(word: original, layoutID: sourceLayoutID)
        if let accepted = state.acceptedWords[wordKey],
           accepted.count >= acceptedWordPromotionCount,
           original.count >= 2 {
            return "accepted_word_dictionary"
        }

        return nil
    }

    public func bootstrapFromEventLogIfNeeded() {
        lock.lock()
        let shouldBootstrap = !state.bootstrappedFromEventLog
        lock.unlock()

        guard shouldBootstrap,
              let logURL = try? LayoutPilotPaths.smartInputEventLogURL(),
              let handle = try? FileHandle(forReadingFrom: logURL) else {
            return
        }
        defer { try? handle.close() }

        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        var imported = 0
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(SmartInputEventLog.Event.self, from: data),
                  event.kind == "replacement_undo" || event.kind == "backspace_after_replacement_window",
                  let mode = event.mode,
                  let original = event.original,
                  let replacement = event.replacement else {
                continue
            }

            recordRejectedConversion(
                mode: mode,
                original: original,
                replacement: replacement,
                sourceLayoutID: event.sourceLayoutID,
                targetLayoutID: event.targetLayoutID,
                bundleID: event.bundleID
            )
            imported += 1
        }

        lock.lock()
        state.bootstrappedFromEventLog = true
        saveLocked()
        lock.unlock()

        if imported > 0 {
            logger.info("Bootstrapped smart-input learning from event log: imported=\(imported, privacy: .public)")
        }
    }

    public func isWordAccepted(_ word: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let normalized = Self.normalizedWord(word)
        return state.acceptedWords.values.contains { $0.word == normalized && $0.count >= acceptedWordPromotionCount }
    }

    public func bootstrapSpellingVocabularyFromLogs(checker: NSSpellChecker) {
        lock.lock()
        let shouldBootstrap = !(state.bootstrappedSpellingVocabulary ?? false)
        lock.unlock()

        guard shouldBootstrap else { return }

        // Read both log files
        let logURLs: [URL]
        do {
            let primaryLog = try LayoutPilotPaths.smartInputEventLogURL()
            let rotatedLog = primaryLog.deletingLastPathComponent().appendingPathComponent(primaryLog.lastPathComponent + ".1")
            logURLs = [rotatedLog, primaryLog] // Read older rotated log first
        } catch {
            return
        }

        var uniqueWords = Set<String>()
        let letterSet = CharacterSet.letters

        for url in logURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            
            let lines = text.split(separator: "\n")
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                let fields = ["original", "replacement", "bufferBefore", "bufferAfter"]
                for field in fields {
                    if let val = dict[field] as? String {
                        extractWords(from: val, into: &uniqueWords, letterSet: letterSet)
                    }
                }
                if let val = dict["summary"] as? String {
                    extractWords(from: val, into: &uniqueWords, letterSet: letterSet)
                }
            }
        }

        logger.info("Extracted \(uniqueWords.count) candidate words from logs. Verifying spelling...")

        var addedCount = 0
        
        lock.lock()
        for word in uniqueWords {
            let normalized = Self.normalizedWord(word)
            guard normalized.count >= 2 else { continue }
            
            let hasCyrillic = normalized.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            let hasLatin = normalized.unicodeScalars.contains { (97...122).contains($0.value) }
            
            let language: String
            let layoutID: String?
            if hasCyrillic && !hasLatin {
                language = "ru"
                layoutID = "com.apple.keylayout.RussianWin"
            } else if hasLatin && !hasCyrillic {
                language = "en"
                layoutID = "com.apple.keylayout.US"
            } else {
                continue
            }
            
            // Check if it's already accepted in our store with count >= 3
            let key = Self.wordKey(word: normalized, layoutID: layoutID)
            if let entry = state.acceptedWords[key], entry.count >= acceptedWordPromotionCount {
                continue
            }
            
            // Check if it is spelled correctly in macOS
            var wordCount = 0
            let range = checker.checkSpelling(
                of: normalized,
                startingAt: 0,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            
            let isMisspelled = range.location != NSNotFound
            if isMisspelled {
                var entry = state.acceptedWords[key] ?? AcceptedWordEntry(
                    word: normalized,
                    layoutID: layoutID,
                    count: 0,
                    firstSeen: Date(),
                    lastSeen: Date(),
                    bundleIDs: []
                )
                entry.count = max(entry.count, acceptedWordPromotionCount)
                entry.lastSeen = Date()
                state.acceptedWords[key] = entry
                addedCount += 1
            }
        }
        
        state.bootstrappedSpellingVocabulary = true
        saveLocked()
        lock.unlock()

        logger.info("Completed spelling bootstrap. Added \(addedCount) misspelled-but-user-approved words to local dictionary.")
    }

    private func extractWords(from text: String, into uniqueWords: inout Set<String>, letterSet: CharacterSet) {
        let scanner = Scanner(string: text)
        while !scanner.isAtEnd {
            if let word = scanner.scanCharacters(from: letterSet) {
                if word.count >= 2 {
                    uniqueWords.insert(word.lowercased())
                }
            } else {
                _ = scanner.scanUpToCharacters(from: letterSet)
            }
        }
    }

    private func saveLocked() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Failed to save smart-input learning store: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func wordKey(word: String, layoutID: String?) -> String {
        [layoutID ?? "", word].joined(separator: "\u{1F}")
    }

    private static func conversionKey(
        mode: String,
        original: String,
        replacement: String,
        sourceLayoutID: String?,
        targetLayoutID: String?
    ) -> String {
        [mode, sourceLayoutID ?? "", targetLayoutID ?? "", original, replacement]
            .joined(separator: "\u{1F}")
    }

    public struct WordLearningOutcome: Sendable {
        public let count: Int
        public let wasPromoted: Bool
    }

    private struct State: Codable {
        var version = 1
        var bootstrappedFromEventLog = false
        var bootstrappedSpellingVocabulary: Bool? = false
        var acceptedWords: [String: AcceptedWordEntry] = [:]
        var conversions: [String: ConversionEntry] = [:]
    }

    private struct AcceptedWordEntry: Codable {
        var word: String
        var layoutID: String?
        var count: Int
        var firstSeen: Date
        var lastSeen: Date
        var bundleIDs: Set<String>
    }

    private struct ConversionEntry: Codable {
        var mode: String
        var original: String
        var replacement: String
        var sourceLayoutID: String?
        var targetLayoutID: String?
        var acceptedCount: Int
        var rejectedCount: Int
        var firstSeen: Date
        var lastSeen: Date
        var bundleIDs: Set<String>
    }
}
