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
    public init() {}

    public func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
    }

    public func availableInputSources() -> [InputSourceInfo] {
        guard let unmanaged = TISCreateInputSourceList(nil, false) else {
            return []
        }

        let array = unmanaged.takeRetainedValue() as NSArray
        return array.compactMap { element in
            let source = element as! TISInputSource
            
            // Only include actual keyboard input sources (layouts and input methods)
            guard let category = Self.stringProperty(source, key: kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String) else {
                return nil
            }
            
            guard let sourceID = Self.stringProperty(source, key: kTISPropertyInputSourceID),
                  let localizedName = Self.stringProperty(source, key: kTISPropertyLocalizedName) else {
                return nil
            }
            let languages = Self.arrayProperty(source, key: kTISPropertyInputSourceLanguages)
            let languageTag = languages?.first
            return InputSourceInfo(sourceID: sourceID, localizedName: localizedName, languageTag: languageTag)
        }
    }

    public func activateInputSource(withID inputSourceID: String) throws {
        guard let match = availableInputSources().first(where: { $0.sourceID == inputSourceID }) else {
            throw InputSourceClientError.sourceNotFound(inputSourceID)
        }

        guard let unmanaged = TISCreateInputSourceList(nil, false) else {
            throw InputSourceClientError.sourceNotFound(match.sourceID)
        }

        let array = unmanaged.takeRetainedValue() as NSArray
        for element in array {
            let source = element as! TISInputSource
            guard let sourceID = Self.stringProperty(source, key: kTISPropertyInputSourceID),
                  sourceID == inputSourceID else {
                continue
            }

            let status = TISSelectInputSource(source)
            guard status == noErr else {
                throw InputSourceClientError.activationFailed(inputSourceID, status)
            }
            return
        }

        throw InputSourceClientError.sourceNotFound(inputSourceID)
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
}
