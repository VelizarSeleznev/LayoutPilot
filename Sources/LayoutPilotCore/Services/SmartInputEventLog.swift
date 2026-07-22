import Foundation
import OSLog

public final class SmartInputEventLog: @unchecked Sendable {
    public static let shared = SmartInputEventLog()

    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let fileURL: URL?
    private let maxLogSizeBytes: UInt64 = 2 * 1024 * 1024
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "SmartInput"
    )

    public init(fileURL: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.fileURL = fileURL
    }

    public static func logURL() throws -> URL {
        try LayoutPilotPaths.smartInputEventLogURL()
    }

    public func record(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }

        if event.kind != "backspace_buffer_update" {
            do {
                let url = try fileURL ?? Self.logURL()
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try rotateLogIfNeeded(at: url)

                let data = try encoder.encode(event)
                var line = data
                line.append(0x0A)

                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: url, options: [.atomic])
                }

                logger.info("Smart input event: \(event.summary ?? event.kind, privacy: .public)")
            } catch {
                logger.error("Failed to write smart input event: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func rotateLogIfNeeded(at url: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxLogSizeBytes else {
            return
        }

        let rotatedURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".1")
        try? FileManager.default.removeItem(at: rotatedURL)
        try FileManager.default.moveItem(at: url, to: rotatedURL)
    }

    public struct Event: Codable, Sendable {
        public var timestamp: Date
        public var kind: String
        public var mode: String?
        public var reason: String?
        public var bundleID: String?
        public var sourceLayoutID: String?
        public var targetLayoutID: String?
        public var original: String?
        public var replacement: String?
        public var boundary: String?
        public var keyCode: Int64?
        public var bufferBefore: String?
        public var bufferAfter: String?
        public var elapsedSinceReplacement: Double?
        public var replacementAgeLimit: Double?
        public var contextBefore: [String]?
        public var suppressionReason: String?
        public var learnedWordCount: Int?
        public var summary: String?

        public init(
            timestamp: Date = Date(),
            kind: String,
            mode: String? = nil,
            reason: String? = nil,
            bundleID: String? = nil,
            sourceLayoutID: String? = nil,
            targetLayoutID: String? = nil,
            original: String? = nil,
            replacement: String? = nil,
            boundary: String? = nil,
            keyCode: Int64? = nil,
            bufferBefore: String? = nil,
            bufferAfter: String? = nil,
            elapsedSinceReplacement: Double? = nil,
            replacementAgeLimit: Double? = nil,
            contextBefore: [String]? = nil,
            suppressionReason: String? = nil,
            learnedWordCount: Int? = nil,
            summary: String? = nil
        ) {
            self.timestamp = timestamp
            self.kind = kind
            self.mode = mode
            self.reason = reason
            self.bundleID = bundleID
            self.sourceLayoutID = sourceLayoutID
            self.targetLayoutID = targetLayoutID
            self.original = original
            self.replacement = replacement
            self.boundary = boundary
            self.keyCode = keyCode
            self.bufferBefore = bufferBefore
            self.bufferAfter = bufferAfter
            self.elapsedSinceReplacement = elapsedSinceReplacement
            self.replacementAgeLimit = replacementAgeLimit
            self.contextBefore = contextBefore
            self.suppressionReason = suppressionReason
            self.learnedWordCount = learnedWordCount
            self.summary = summary ?? Self.makeSummary(
                kind: kind,
                mode: mode,
                reason: reason,
                bundleID: bundleID,
                sourceLayoutID: sourceLayoutID,
                targetLayoutID: targetLayoutID,
                original: original,
                replacement: replacement,
                boundary: boundary,
                elapsedSinceReplacement: elapsedSinceReplacement,
                replacementAgeLimit: replacementAgeLimit,
                suppressionReason: suppressionReason,
                learnedWordCount: learnedWordCount
            )
        }

        private static func makeSummary(
            kind: String,
            mode: String?,
            reason: String?,
            bundleID: String?,
            sourceLayoutID: String?,
            targetLayoutID: String?,
            original: String?,
            replacement: String?,
            boundary: String?,
            elapsedSinceReplacement: Double?,
            replacementAgeLimit: Double?,
            suppressionReason: String?,
            learnedWordCount: Int?
        ) -> String {
            var parts = [kind]
            if let mode { parts.append("mode=\(mode)") }
            if let bundleID { parts.append("app=\(bundleID)") }
            if let sourceLayoutID { parts.append("source=\(sourceLayoutID)") }
            if let targetLayoutID { parts.append("target=\(targetLayoutID)") }
            if let original, let replacement {
                parts.append("'\(original)' -> '\(replacement)'")
            } else if let original {
                parts.append("word='\(original)'")
            }
            if let boundary, !boundary.isEmpty {
                parts.append("boundary='\(boundary)'")
            }
            if let suppressionReason {
                parts.append("suppressed=\(suppressionReason)")
            }
            if let learnedWordCount {
                parts.append("learnedCount=\(learnedWordCount)")
            }
            if let elapsedSinceReplacement {
                let formatted = String(format: "%.2fs", elapsedSinceReplacement)
                parts.append("elapsed=\(formatted)")
            }
            if let replacementAgeLimit {
                let formatted = String(format: "%.2fs", replacementAgeLimit)
                parts.append("undoLimit=\(formatted)")
            }
            if let reason {
                parts.append("reason=\(reason)")
            }
            return parts.joined(separator: " | ")
        }
    }
}
