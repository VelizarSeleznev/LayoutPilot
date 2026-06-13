import Foundation
import ServiceManagement
import OSLog

public final class LaunchAtLoginService {
    private static let logger = Logger(subsystem: "com.velizard.LayoutPilot", category: "LaunchAtLoginService")

    public struct State: Equatable, Sendable {
        public var statusDescription: String
        public var isEnabled: Bool
        public var requiresApproval: Bool
        public var errorMessage: String?

        public init(
            statusDescription: String,
            isEnabled: Bool,
            requiresApproval: Bool,
            errorMessage: String? = nil
        ) {
            self.statusDescription = statusDescription
            self.isEnabled = isEnabled
            self.requiresApproval = requiresApproval
            self.errorMessage = errorMessage
        }
    }

    public static func currentState() -> State {
        state(for: SMAppService.mainApp.status)
    }

    @discardableResult
    public static func sync(enabled: Bool) -> State {
        let service = SMAppService.mainApp
        let status = service.status
        
        logger.info("Syncing launch at login: enabled=\(enabled), current status=\(Self.describe(status))")
        
        if enabled {
            if status == .enabled {
                logger.info("LaunchAtLoginService: Service is already enabled.")
                return state(for: status)
            }
            if status == .requiresApproval {
                logger.info("LaunchAtLoginService: Service requires user approval in System Settings.")
                return state(for: status)
            }
            do {
                try service.register()
                let updatedStatus = service.status
                logger.info("LaunchAtLoginService: Register finished with status=\(Self.describe(updatedStatus)).")
                return state(for: updatedStatus)
            } catch {
                logger.error("LaunchAtLoginService: Failed to register: \(error.localizedDescription)")
                return state(for: service.status, errorMessage: error.localizedDescription)
            }
        } else {
            if status == .notRegistered || status == .notFound {
                logger.info("LaunchAtLoginService: Service is already not registered.")
                return state(for: status)
            }
            do {
                try service.unregister()
                let updatedStatus = service.status
                logger.info("LaunchAtLoginService: Unregister finished with status=\(Self.describe(updatedStatus)).")
                return state(for: updatedStatus)
            } catch {
                logger.error("LaunchAtLoginService: Failed to unregister: \(error.localizedDescription)")
                return state(for: service.status, errorMessage: error.localizedDescription)
            }
        }
    }

    private static func state(for status: SMAppService.Status, errorMessage: String? = nil) -> State {
        State(
            statusDescription: describe(status),
            isEnabled: status == .enabled,
            requiresApproval: status == .requiresApproval,
            errorMessage: errorMessage
        )
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        case .notRegistered: return "notRegistered"
        @unknown default: return "unknown"
        }
    }
}
