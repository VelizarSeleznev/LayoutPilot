import Foundation
import LayoutPilotCore
import OSLog

actor AnonymousUsageReporter {
    static let shared = AnonymousUsageReporter()

    private let endpoint = URL(string: "https://layoutpilot-telemetry.vercel.app/api/events")!
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "AnonymousUsage"
    )

    func submit(_ event: SmartInputEventLog.Event) async {
        guard let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let sanitized = AnonymousUsageEventPolicy.sanitizedEvent(
                  from: event,
                  appVersion: appVersion,
                  osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
              ) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(sanitized)

            let session = URLSession(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false
                configuration.httpCookieAcceptPolicy = .never
                configuration.urlCache = nil
                configuration.urlCredentialStorage = nil
                configuration.timeoutIntervalForRequest = 6
                configuration.timeoutIntervalForResource = 8
                return configuration
            }())

            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                logger.error("Anonymous usage response was not HTTP")
                return
            }

            if response.statusCode != 202 {
                logger.error("Anonymous usage endpoint returned HTTP \(response.statusCode)")
            }
        } catch {
            logger.debug("Failed to send anonymous usage event: \(error.localizedDescription, privacy: .public)")
        }
    }
}
