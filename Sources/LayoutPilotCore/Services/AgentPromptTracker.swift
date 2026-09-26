import CoreGraphics
import Foundation

/// Tracks, per herdr pane, whether a coding agent's prompt is empty, from the keys typed into it.
///
/// Agent commands start with `/`, and on a Russian layout that key types `.`. When the prompt
/// is known to be empty, that key types `/` instead and the command is typed on U.S.; the pane's
/// layout comes back once the command word ends. Emptiness is only claimed when the tracker has
/// seen every edit since the last submit: anything it cannot follow (history recall, paste, word
/// deletion, cursor movement) makes the prompt unknown, and an unknown prompt keeps `.`.
struct AgentPromptTracker {
    enum PromptState: Equatable {
        case empty
        case typed(count: Int)
        case unknown
    }

    enum Key: Equatable {
        case text
        case space
        case submit
        case newline
        case backspace
        /// Clears a single-line prompt: Control-U, Command-Delete.
        case clearLine
        /// Control-C: agents discard the prompt.
        case interrupt
        /// herdr's prefix chord. The key after it is a herdr command, not prompt text.
        case herdrPrefix
        /// Changes the prompt in a way the tracker cannot follow.
        case untrackedEdit
        /// Leaves the prompt alone: app shortcuts, Escape, scrolling.
        case ignored
    }

    enum Action: Equatable {
        case none
        /// Type `/` for this key and switch to U.S.
        case insertSlash
        /// The command word ended; select the pane's layout again.
        case restoreLayout(sourceID: String)
    }

    static let slashKeyCode: Int64 = 44

    private var states: [String: PromptState] = [:]
    private var herdrPrefixPending = false
    private var pendingRestore: (paneID: String, sourceID: String)?

    func state(for paneID: String) -> PromptState {
        states[paneID] ?? .unknown
    }

    mutating func markEmpty(paneID: String) {
        states[paneID] = .empty
    }

    mutating func markUnknown(paneID: String) {
        states[paneID] = .unknown
    }

    /// The pane that owns the keyboard changed. A command in flight there stays on U.S.;
    /// the layout engine owns what the next pane gets.
    mutating func focusChanged() {
        herdrPrefixPending = false
        pendingRestore = nil
    }

    mutating func handle(
        _ key: Key,
        keyCode: Int64,
        flags: CGEventFlags,
        paneID: String,
        sourceID: String?,
        usSourceIDs: Set<String>
    ) -> Action {
        if herdrPrefixPending {
            herdrPrefixPending = false
            return .none
        }
        if key == .herdrPrefix {
            herdrPrefixPending = true
            return .none
        }

        let before = state(for: paneID)
        if Self.shouldInsertSlash(
            state: before,
            keyCode: keyCode,
            flags: flags,
            sourceID: sourceID,
            usSourceIDs: usSourceIDs
        ), let sourceID {
            states[paneID] = .typed(count: 1)
            pendingRestore = (paneID, sourceID)
            return .insertSlash
        }

        let after = Self.state(before, after: key)
        states[paneID] = after

        guard let restore = pendingRestore, restore.paneID == paneID else { return .none }
        let commandEnded: Bool
        switch key {
        case .space, .submit, .interrupt:
            commandEnded = true
        case .backspace, .clearLine:
            commandEnded = after == .empty
        case .text, .newline, .herdrPrefix, .untrackedEdit, .ignored:
            commandEnded = false
        }
        guard commandEnded else { return .none }
        pendingRestore = nil
        return .restoreLayout(sourceID: restore.sourceID)
    }

    static func shouldInsertSlash(
        state: PromptState,
        keyCode: Int64,
        flags: CGEventFlags,
        sourceID: String?,
        usSourceIDs: Set<String>
    ) -> Bool {
        guard state == .empty,
              keyCode == slashKeyCode,
              flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              let sourceID else {
            return false
        }
        return !usSourceIDs.contains(sourceID)
    }

    static func state(_ state: PromptState, after key: Key) -> PromptState {
        switch key {
        case .text, .space:
            if case .typed(let count) = state { return .typed(count: count + 1) }
            return state == .empty ? .typed(count: 1) : .unknown
        case .submit, .interrupt:
            return .empty
        case .backspace:
            if case .typed(let count) = state { return count > 1 ? .typed(count: count - 1) : .empty }
            return state
        case .clearLine:
            // Typed characters never include a newline (that makes the prompt unknown), so a
            // tracked prompt is a single line and clearing the line empties it.
            if case .typed = state { return .empty }
            return state
        case .newline, .untrackedEdit:
            return .unknown
        case .herdrPrefix, .ignored:
            return state
        }
    }

    static func classify(keyCode: Int64, flags: CGEventFlags, text: String?) -> Key {
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)

        switch keyCode {
        case 36, 76: // Return, keypad Enter
            return shift || option || control ? .newline : .submit
        case 51: // Delete
            if command { return .clearLine }
            return option || control ? .untrackedEdit : .backspace
        case 117, 115, 119, 123, 124, 125, 126, 48: // Forward delete, Home, End, arrows, Tab
            return command ? .ignored : .untrackedEdit
        case 53, 116, 121: // Escape, Page Up, Page Down
            return .ignored
        default:
            break
        }

        if control {
            switch keyCode {
            case 11 where !command && !option && !shift: return .herdrPrefix // Control-B
            case 8: return .interrupt // Control-C
            case 32: return .clearLine // Control-U
            default: return .untrackedEdit
            }
        }
        if command {
            switch keyCode {
            case 9, 7, 6: return .untrackedEdit // Paste, cut, undo
            default: return .ignored
            }
        }
        if option {
            return .untrackedEdit
        }
        guard let text, text.count == 1, let scalar = text.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            return .ignored
        }
        return text == " " ? .space : .text
    }
}
