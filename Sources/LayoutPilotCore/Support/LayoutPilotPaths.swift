import Foundation

public enum LayoutPilotPaths {
    public static let configurationFolderName = "LayoutPilot"
    public static let configurationFileName = "configuration.json"
    public static let smartInputEventLogFileName = "smart-input-events.jsonl"

    public static func applicationSupportDirectory() throws -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url.appendingPathComponent(configurationFolderName, isDirectory: true)
    }

    public static func configurationURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(configurationFileName)
    }

    public static func smartInputEventLogURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(smartInputEventLogFileName)
    }
}
