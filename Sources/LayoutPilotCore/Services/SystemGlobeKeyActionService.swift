import Foundation

protocol SystemGlobeKeyActionPreferences: AnyObject {
    func currentAction() -> Int?
    @discardableResult func setAction(_ action: Int) -> Bool
}

final class HIToolboxGlobeKeyActionPreferences: SystemGlobeKeyActionPreferences {
    private let applicationID = "com.apple.HIToolbox" as CFString
    private let actionKey = "AppleFnUsageType" as CFString

    func currentAction() -> Int? {
        let value = CFPreferencesCopyValue(
            actionKey,
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return (value as? NSNumber)?.intValue
    }

    @discardableResult
    func setAction(_ action: Int) -> Bool {
        CFPreferencesSetValue(
            actionKey,
            NSNumber(value: action),
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return CFPreferencesSynchronize(
            applicationID,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}

public final class SystemGlobeKeyActionService: @unchecked Sendable {
    public static let shared = SystemGlobeKeyActionService()

    static let doNothingAction = 0
    private let previousActionKey = "instantGlobePreviousSystemAction"
    private let preferences: SystemGlobeKeyActionPreferences
    private let restorationDefaults: UserDefaults
    private let lock = NSLock()

    public convenience init() {
        self.init(
            preferences: HIToolboxGlobeKeyActionPreferences(),
            restorationDefaults: .standard
        )
    }

    init(
        preferences: SystemGlobeKeyActionPreferences,
        restorationDefaults: UserDefaults
    ) {
        self.preferences = preferences
        self.restorationDefaults = restorationDefaults
    }

    /// Gives LayoutPilot exclusive ownership of Globe while enabled and restores the
    /// user's former macOS action when the feature is disabled.
    @discardableResult
    public func setLayoutPilotControlEnabled(_ isEnabled: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isEnabled {
            let currentAction = preferences.currentAction()
            if restorationDefaults.object(forKey: previousActionKey) == nil,
               let currentAction,
               currentAction != Self.doNothingAction {
                restorationDefaults.set(currentAction, forKey: previousActionKey)
            }
            return preferences.setAction(Self.doNothingAction)
        }

        guard let previousAction = restorationDefaults.object(forKey: previousActionKey) as? NSNumber else {
            return true
        }
        guard preferences.setAction(previousAction.intValue) else {
            return false
        }
        restorationDefaults.removeObject(forKey: previousActionKey)
        return true
    }
}
