import Foundation
import OSLog

/// A local-only, high-detail trace of the Event Tap pipeline.
///
/// `record` never performs JSON encoding or file I/O on the Event Tap thread. Events are
/// copied onto a utility queue, encoded there, and flushed in small batches. This trace has
/// no remote callback and is intentionally separate from `SmartInputEventLog`, whose events
/// may be sent as anonymous usage statistics when the user enables that setting.
public final class SmartInputTraceLog: @unchecked Sendable {
    public static let shared = SmartInputTraceLog()

    private let queue = DispatchQueue(
        label: "com.velizard.LayoutPilot.smart-input-trace",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let encoder: JSONEncoder
    private let explicitFileURL: URL?
    private let maxLogSizeBytes: UInt64
    private let archiveCount: Int
    private let flushDelay: TimeInterval
    private let flushThresholdBytes: Int
    private let isEnabled: Bool
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "SmartInputTrace"
    )

    private let sequenceLock = NSLock()
    private var sequence: UInt64 = 0

    private var pending = Data()
    private var flushScheduled = false
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0

    public init(
        fileURL: URL? = nil,
        maxLogSizeBytes: UInt64 = 16 * 1024 * 1024,
        archiveCount: Int = 4,
        flushDelay: TimeInterval = 0.1,
        flushThresholdBytes: Int = 64 * 1024,
        isEnabled: Bool? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.explicitFileURL = fileURL
        self.maxLogSizeBytes = max(1, maxLogSizeBytes)
        self.archiveCount = max(0, archiveCount)
        self.flushDelay = max(0, flushDelay)
        self.flushThresholdBytes = max(1, flushThresholdBytes)
        self.isEnabled = isEnabled ?? (
            fileURL != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )
        queue.setSpecific(key: queueKey, value: 1)
    }

    public func nextSequence() -> UInt64 {
        sequenceLock.lock()
        sequence &+= 1
        let value = sequence
        sequenceLock.unlock()
        return value
    }

    public func record(_ event: Event) {
        guard isEnabled else { return }
        queue.async { [self] in
            do {
                var line = try encoder.encode(event)
                line.append(0x0A)
                pending.append(line)

                if pending.count >= flushThresholdBytes {
                    flushPendingLocked()
                } else {
                    scheduleFlushLocked()
                }
            } catch {
                logger.error("Failed to encode smart-input trace: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func flushSynchronously() {
        guard isEnabled else { return }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            flushPendingLocked()
            return
        }
        queue.sync { [self] in
            flushPendingLocked()
        }
    }

    private func scheduleFlushLocked() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushDelay) { [self] in
            flushScheduled = false
            flushPendingLocked()
        }
    }

    private func flushPendingLocked() {
        guard !pending.isEmpty else { return }
        do {
            let url = try explicitFileURL ?? LayoutPilotPaths.smartInputTraceLogURL()
            if fileHandle == nil {
                try openFileLocked(at: url)
            }
            if currentFileSize + UInt64(pending.count) > maxLogSizeBytes {
                try rotateLocked(at: url)
                try openFileLocked(at: url)
            }
            guard let fileHandle else { return }
            try fileHandle.write(contentsOf: pending)
            currentFileSize += UInt64(pending.count)
            pending.removeAll(keepingCapacity: true)
        } catch {
            fileHandle = nil
            currentFileSize = 0
            // A persistent filesystem failure must not let per-key trace data grow without
            // bound in memory. The failure is still visible in unified logging.
            pending.removeAll(keepingCapacity: true)
            logger.error("Failed to write smart-input trace: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openFileLocked(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        currentFileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle?.seekToEnd()
    }

    private func rotateLocked(at url: URL) throws {
        try? fileHandle?.close()
        fileHandle = nil
        currentFileSize = 0

        guard archiveCount > 0 else {
            try Data().write(to: url, options: [.atomic])
            return
        }

        let fileManager = FileManager.default
        let oldest = archiveURL(for: url, index: archiveCount)
        try? fileManager.removeItem(at: oldest)

        if archiveCount > 1 {
            for index in stride(from: archiveCount - 1, through: 1, by: -1) {
                let source = archiveURL(for: url, index: index)
                let destination = archiveURL(for: url, index: index + 1)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: source, to: destination)
            }
        }

        if fileManager.fileExists(atPath: url.path) {
            let firstArchive = archiveURL(for: url, index: 1)
            try? fileManager.removeItem(at: firstArchive)
            try fileManager.moveItem(at: url, to: firstArchive)
        }
    }

    private func archiveURL(for url: URL, index: Int) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".\(index)")
    }

    public struct Event: Codable, Sendable {
        public var timestamp: Date
        public var sequence: UInt64
        public var phase: String
        public var eventType: String?
        public var decision: String?
        public var disposition: String?
        public var keyCode: Int64?
        public var text: String?
        public var textRedacted: Bool?
        public var flagsRaw: UInt64?
        public var flags: [String]?
        public var isAutoRepeat: Bool?
        public var isSynthetic: Bool?
        public var sourcePID: Int64?
        public var bundleID: String?
        public var processIdentifier: Int32?
        public var cachedSourceLayoutID: String?
        public var observedSourceLayoutID: String?
        public var focusedElementKind: String?
        public var bufferBefore: String?
        public var bufferAfter: String?
        public var lastReplacementMode: String?
        public var lastReplacementOriginal: String?
        public var lastReplacementText: String?
        public var lastReplacementBoundary: String?
        public var latencyMicroseconds: Double?
        public var details: [String: String]?

        public init(
            timestamp: Date = Date(),
            sequence: UInt64,
            phase: String,
            eventType: String? = nil,
            decision: String? = nil,
            disposition: String? = nil,
            keyCode: Int64? = nil,
            text: String? = nil,
            textRedacted: Bool? = nil,
            flagsRaw: UInt64? = nil,
            flags: [String]? = nil,
            isAutoRepeat: Bool? = nil,
            isSynthetic: Bool? = nil,
            sourcePID: Int64? = nil,
            bundleID: String? = nil,
            processIdentifier: Int32? = nil,
            cachedSourceLayoutID: String? = nil,
            observedSourceLayoutID: String? = nil,
            focusedElementKind: String? = nil,
            bufferBefore: String? = nil,
            bufferAfter: String? = nil,
            lastReplacementMode: String? = nil,
            lastReplacementOriginal: String? = nil,
            lastReplacementText: String? = nil,
            lastReplacementBoundary: String? = nil,
            latencyMicroseconds: Double? = nil,
            details: [String: String]? = nil
        ) {
            self.timestamp = timestamp
            self.sequence = sequence
            self.phase = phase
            self.eventType = eventType
            self.decision = decision
            self.disposition = disposition
            self.keyCode = keyCode
            self.text = text
            self.textRedacted = textRedacted
            self.flagsRaw = flagsRaw
            self.flags = flags
            self.isAutoRepeat = isAutoRepeat
            self.isSynthetic = isSynthetic
            self.sourcePID = sourcePID
            self.bundleID = bundleID
            self.processIdentifier = processIdentifier
            self.cachedSourceLayoutID = cachedSourceLayoutID
            self.observedSourceLayoutID = observedSourceLayoutID
            self.focusedElementKind = focusedElementKind
            self.bufferBefore = bufferBefore
            self.bufferAfter = bufferAfter
            self.lastReplacementMode = lastReplacementMode
            self.lastReplacementOriginal = lastReplacementOriginal
            self.lastReplacementText = lastReplacementText
            self.lastReplacementBoundary = lastReplacementBoundary
            self.latencyMicroseconds = latencyMicroseconds
            self.details = details
        }
    }
}
