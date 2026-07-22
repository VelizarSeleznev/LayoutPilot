import AppKit
import Foundation
import OSLog

public final class SmartInputLearningStore: @unchecked Sendable {
    public static let shared = SmartInputLearningStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let persistenceQueue = DispatchQueue(
        label: "com.velizard.LayoutPilot.smart-input-learning-persistence",
        qos: .utility
    )
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "SmartInputLearning"
    )

    private var state: State
    private var saveScheduled = false
    private let acceptedWordPromotionCount = 3
    private let rejectedConversionSuppressionCount = 2
    private let acceptedWordLimit = 2_000
    private let persistenceDelay = 2.0

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
        guard Self.isLearnableWord(normalized, layoutID: layoutID) else {
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
            bundleIDs: [],
            countsByBundleID: [:]
        )
        entry.count += 1
        entry.lastSeen = Date()
        if let bundleID, !bundleID.isEmpty {
            entry.bundleIDs.insert(bundleID)
            var counts = entry.countsByBundleID ?? [:]
            counts[bundleID, default: 0] += 1
            entry.countsByBundleID = counts
        }
        state.acceptedWords[key] = entry
        scheduleSaveLocked()

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
            rejectedCountsByBundleID: [:],
            firstSeen: Date(),
            lastSeen: Date(),
            bundleIDs: []
        )
        entry.rejectedCount += 1
        entry.lastSeen = Date()
        if let bundleID, !bundleID.isEmpty {
            entry.bundleIDs.insert(bundleID)
            var counts = entry.rejectedCountsByBundleID ?? [:]
            counts[bundleID, default: 0] += 1
            entry.rejectedCountsByBundleID = counts
        }
        state.conversions[key] = entry

        if Self.isLearnableWord(original, layoutID: sourceLayoutID) {
            let wordKey = Self.wordKey(word: original, layoutID: sourceLayoutID)
            var wordEntry = state.acceptedWords[wordKey] ?? AcceptedWordEntry(
                word: original,
                layoutID: sourceLayoutID,
                count: 0,
                firstSeen: Date(),
                lastSeen: Date(),
                bundleIDs: [],
                countsByBundleID: [:]
            )
            wordEntry.count += 1
            wordEntry.lastSeen = Date()
            if let bundleID, !bundleID.isEmpty {
                wordEntry.bundleIDs.insert(bundleID)
                var counts = wordEntry.countsByBundleID ?? [:]
                counts[bundleID, default: 0] += 1
                wordEntry.countsByBundleID = counts
            }
            state.acceptedWords[wordKey] = wordEntry
        }

        saveLocked()
        logger.info("Rejected smart-input conversion mode=\(mode, privacy: .public) originalLength=\(original.count, privacy: .public) replacementLength=\(replacement.count, privacy: .public)")
    }

    public func suppressionReason(
        mode: String,
        original: String,
        replacement: String,
        sourceLayoutID: String?,
        targetLayoutID: String?,
        bundleID: String? = nil
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
            let rejectedCount = bundleID.flatMap {
                conversion.rejectedCountsByBundleID?[$0]
            } ?? (bundleID == nil ? conversion.rejectedCount : 0)
            if rejectedCount >= rejectedConversionSuppressionCount {
                return "user_rejected_conversion"
            }
        }

        let wordKey = Self.wordKey(word: original, layoutID: sourceLayoutID)
        if let accepted = state.acceptedWords[wordKey], original.count >= 2 {
            let acceptedCount = bundleID.flatMap {
                accepted.countsByBundleID?[$0]
            } ?? (bundleID == nil ? accepted.count : 0)
            if acceptedCount >= acceptedWordPromotionCount {
                return "accepted_word_dictionary"
            }
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
                  event.kind == "replacement_undo",
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

    public func isWordAccepted(
        _ word: String,
        layoutID: String? = nil,
        bundleID: String? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let normalized = Self.normalizedWord(word)
        if let layoutID {
            let key = Self.wordKey(word: normalized, layoutID: layoutID)
            guard let entry = state.acceptedWords[key] else { return false }
            let count = bundleID.flatMap {
                entry.countsByBundleID?[$0]
            } ?? (bundleID == nil ? entry.count : 0)
            return count >= acceptedWordPromotionCount
        }
        return state.acceptedWords.values.contains { entry in
            guard entry.word == normalized else { return false }
            let count = bundleID.flatMap {
                entry.countsByBundleID?[$0]
            } ?? (bundleID == nil ? entry.count : 0)
            return count >= acceptedWordPromotionCount
        }
    }

    public func bootstrapSpellingVocabularyFromLogs(
        checker: NSSpellChecker,
        logURLs suppliedLogURLs: [URL]? = nil
    ) {
        lock.lock()
        let shouldBootstrap = !(state.bootstrappedSpellingVocabulary ?? false)
        lock.unlock()

        guard shouldBootstrap else { return }

        // Read both log files
        let logURLs: [URL]
        if let suppliedLogURLs {
            logURLs = suppliedLogURLs
        } else {
            do {
                let primaryLog = try LayoutPilotPaths.smartInputEventLogURL()
                let rotatedLog = primaryLog.deletingLastPathComponent().appendingPathComponent(primaryLog.lastPathComponent + ".1")
                logURLs = [rotatedLog, primaryLog]
            } catch {
                return
            }
        }

        var uniqueWords = Set<String>()

        for url in logURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            
            let lines = text.split(separator: "\n")
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let event = try? decoder.decode(SmartInputEventLog.Event.self, from: data),
                      event.kind == "accepted_word_promoted",
                      let word = event.original else {
                    continue
                }
                uniqueWords.insert(Self.normalizedWord(word))
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
                    bundleIDs: [],
                    countsByBundleID: [:]
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

    func flushPendingWrites() {
        lock.lock()
        saveScheduled = false
        saveLocked()
        lock.unlock()
    }

    private func scheduleSaveLocked() {
        guard !saveScheduled else { return }
        saveScheduled = true
        persistenceQueue.asyncAfter(deadline: .now() + persistenceDelay) { [weak self] in
            self?.flushPendingWrites()
        }
    }

    private func saveLocked() {
        do {
            pruneAcceptedWordsLocked()
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

    private func pruneAcceptedWordsLocked() {
        guard state.acceptedWords.count > acceptedWordLimit else { return }
        let retained = state.acceptedWords
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.value.lastSeen > rhs.value.lastSeen
            }
            .prefix(acceptedWordLimit)
        state.acceptedWords = Dictionary(
            uniqueKeysWithValues: retained.map { ($0.key, $0.value) }
        )
    }

    private static func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isLearnableWord(_ word: String, layoutID: String?) -> Bool {
        guard word.count >= 2 else { return false }
        let characters = Array(word)
        guard characters.first?.unicodeScalars.allSatisfy(CharacterSet.letters.contains) == true,
              characters.last?.unicodeScalars.allSatisfy(CharacterSet.letters.contains) == true else {
            return false
        }

        for character in characters {
            if character == "'" || character == "’" { continue }
            guard character.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
                return false
            }
        }

        let letters = word.unicodeScalars.filter(CharacterSet.letters.contains)
        if layoutID == "com.apple.keylayout.US" || layoutID == "com.apple.keylayout.ABC" {
            return letters.allSatisfy { (65...90).contains($0.value) || (97...122).contains($0.value) }
        }
        if layoutID?.localizedCaseInsensitiveContains("Russian") == true {
            return letters.allSatisfy { (0x0400...0x04FF).contains($0.value) }
        }
        return true
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
        var countsByBundleID: [String: Int]?
    }

    private struct ConversionEntry: Codable {
        var mode: String
        var original: String
        var replacement: String
        var sourceLayoutID: String?
        var targetLayoutID: String?
        var acceptedCount: Int
        var rejectedCount: Int
        var rejectedCountsByBundleID: [String: Int]?
        var firstSeen: Date
        var lastSeen: Date
        var bundleIDs: Set<String>
    }
}
