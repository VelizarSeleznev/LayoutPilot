import Carbon
import Foundation

public struct InputSourceInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { sourceID }
    public let sourceID: String
    public let localizedName: String
    public let languageTag: String?

    public init(sourceID: String, localizedName: String, languageTag: String? = nil) {
        self.sourceID = sourceID
        self.localizedName = localizedName
        self.languageTag = languageTag
    }
}

public protocol InputSourceClient {
    func currentInputSourceID() -> String?
    func availableInputSources() -> [InputSourceInfo]
    func activateInputSource(withID inputSourceID: String) throws
}

public enum InputSourceClientError: Error, LocalizedError {
    case sourceNotFound(String)
    case activationFailed(String, OSStatus)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let sourceID):
            return "Input source not found: \(sourceID)"
        case .activationFailed(let sourceID, let status):
            return "Could not activate input source \(sourceID) (OSStatus \(status))."
        }
    }
}

public final class SystemInputSourceClient: InputSourceClient {
    private struct CachedInputSource {
        let info: InputSourceInfo
        let source: TISInputSource
    }

    private var cachedSources: [CachedInputSource] = []

    public init() {}

    public func currentInputSourceID() -> String? {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.currentInputSourceID()
            }
        }

        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
    }

    public func availableInputSources() -> [InputSourceInfo] {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.availableInputSources()
            }
        }

        guard let unmanaged = TISCreateInputSourceList(nil, false) else {
            return []
        }

        let array = unmanaged.takeRetainedValue() as NSArray
        let sources: [CachedInputSource] = array.compactMap { element in
            let source = element as! TISInputSource

            // Only include actual keyboard input sources (layouts and input methods)
            guard let category = Self.stringProperty(source, key: kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String),
                  Self.boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable) != false else {
                return nil
            }

            guard let sourceID = Self.stringProperty(source, key: kTISPropertyInputSourceID),
                  let localizedName = Self.stringProperty(source, key: kTISPropertyLocalizedName) else {
                return nil
            }
            let languages = Self.arrayProperty(source, key: kTISPropertyInputSourceLanguages)
            let languageTag = languages?.first
            return CachedInputSource(
                info: InputSourceInfo(
                    sourceID: sourceID,
                    localizedName: localizedName,
                    languageTag: languageTag
                ),
                source: source
            )
        }
        cachedSources = sources
        return sources.map(\.info)
    }

    public func activateInputSource(withID inputSourceID: String) throws {
        guard Thread.isMainThread else {
            let result = DispatchQueue.main.sync {
                Result {
                    try self.activateInputSource(withID: inputSourceID)
                }
            }
            try result.get()
            return
        }

        var match = cachedSources.first { $0.info.sourceID == inputSourceID }
        if match == nil {
            _ = availableInputSources()
            match = cachedSources.first { $0.info.sourceID == inputSourceID }
        }

        guard let match else {
            throw InputSourceClientError.sourceNotFound(inputSourceID)
        }

        let status = TISSelectInputSource(match.source)
        guard status == noErr else {
            throw InputSourceClientError.activationFailed(inputSourceID, status)
        }
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func arrayProperty(_ source: TISInputSource, key: CFString) -> [String]? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let array = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as NSArray
        return array.compactMap { $0 as? String }
    }

    private static func boolProperty(_ source: TISInputSource, key: CFString) -> Bool? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
