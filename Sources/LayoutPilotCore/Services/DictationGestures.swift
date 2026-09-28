import Foundation

public enum DictationCommand: Equatable, Sendable {
    case holdStart
    case holdStop
    case toggle
}

enum DictationGestureEffect: Equatable {
    case switchLayout
    case revertLayout
    case command(DictationCommand)
    case armHold(UUID)
    /// Swallow this Option event so Claude's double-tap quick entry does not see it.
    case consume
}

/// Single Fn switches layout on release, with no wait after the key is up.
/// A second Fn inside the double window undoes that switch and starts dictation.
/// Holding Fn never switches layout: dictation runs until the key comes up.
/// Double Option starts and stops dictation. Option chords are left alone.
struct DictationGestureMachine {
    var dictationEnabled: Bool

    init(dictationEnabled: Bool = true) {
        self.dictationEnabled = dictationEnabled
    }
    var holdThreshold: TimeInterval = 0.34
    var doubleWindow: TimeInterval = 0.32

    private enum Phase: Equatable {
        case idle
        case fnDown(since: TimeInterval, token: UUID)
        case fnHolding
        case fnAwaitingSecond(releasedAt: TimeInterval)
        case fnSecondDown
        case optionDown(since: TimeInterval, code: Int64)
        case optionAwaitingSecond(releasedAt: TimeInterval)
        case swallowingOptionUp(code: Int64)
    }

    private var phase = Phase.idle
    private var holdToken: UUID?

    mutating func handleFn(isDown: Bool, at time: TimeInterval) -> [DictationGestureEffect] {
        cancelOptionTracking()
        if !dictationEnabled {
            if isDown {
                phase = .fnDown(since: time, token: UUID())
                return []
            }
            defer { phase = .idle }
            if case .fnDown(let since, _) = phase, time - since < holdThreshold {
                return [.switchLayout]
            }
            return []
        }
        if isDown {
            switch phase {
            case .fnAwaitingSecond(let releasedAt) where time - releasedAt <= doubleWindow:
                phase = .fnSecondDown
                holdToken = nil
                return [.revertLayout, .command(.toggle)]
            case .fnDown, .fnHolding, .fnSecondDown:
                return []
            default:
                let token = UUID()
                phase = .fnDown(since: time, token: token)
                holdToken = token
                return [.armHold(token)]
            }
        }

        switch phase {
        case .fnDown(let since, _):
            holdToken = nil
            if time - since >= holdThreshold {
                phase = .idle
                return [.command(.holdStart), .command(.holdStop)]
            }
            phase = .fnAwaitingSecond(releasedAt: time)
            return [.switchLayout]
        case .fnHolding:
            phase = .idle
            holdToken = nil
            return [.command(.holdStop)]
        case .fnSecondDown:
            phase = .idle
            return []
        default:
            phase = .idle
            return []
        }
    }

    mutating func holdFired(token: UUID, at time: TimeInterval) -> [DictationGestureEffect] {
        guard dictationEnabled else { return [] }
        guard case .fnDown(let since, let armed) = phase, armed == token, holdToken == token else {
            return []
        }
        guard time - since >= holdThreshold - 0.02 else { return [] }
        phase = .fnHolding
        return [.command(.holdStart)]
    }

    mutating func handleOption(
        keyCode: Int64,
        isDown: Bool,
        isAlone: Bool,
        at time: TimeInterval
    ) -> [DictationGestureEffect] {
        guard dictationEnabled else { return [] }
        if isDown {
            if case .swallowingOptionUp = phase {
                return [.consume]
            }
            guard isAlone else {
                cancelOptionTracking()
                return []
            }
            if case .optionAwaitingSecond(let releasedAt) = phase, time - releasedAt <= doubleWindow {
                phase = .swallowingOptionUp(code: keyCode)
                return [.command(.toggle), .consume]
            }
            phase = .optionDown(since: time, code: keyCode)
            return []
        }

        switch phase {
        case .swallowingOptionUp(let code) where code == keyCode:
            phase = .idle
            return [.consume]
        case .optionDown(let since, let code) where code == keyCode && isAlone && time - since < 0.45:
            phase = .optionAwaitingSecond(releasedAt: time)
            return []
        default:
            if case .optionDown = phase {
                phase = .idle
            }
            return []
        }
    }

    mutating func foreignKey() {
        switch phase {
        case .optionDown, .optionAwaitingSecond:
            phase = .idle
        default:
            break
        }
    }

    mutating func reset() {
        phase = .idle
        holdToken = nil
    }

    private mutating func cancelOptionTracking() {
        switch phase {
        case .optionDown, .optionAwaitingSecond, .swallowingOptionUp:
            phase = .idle
        default:
            break
        }
    }
}
