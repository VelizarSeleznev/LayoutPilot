import AppKit
import ApplicationServices

/// A read-only snapshot of whatever text element currently has keyboard focus,
/// system-wide. Captures both the content/context (value + cursor) and a set of
/// capability flags so you can see, per app, what Accessibility actually exposes.
public struct AXFocusSnapshot: Sendable {
    public var hasFocus = false
    public var appName = "—"
    public var appBundleID: String?
    public var appPID: pid_t?

    public var role: String?
    public var subrole: String?
    public var roleDescription: String?
    public var title: String?
    public var identifier: String?
    public var placeholder: String?
    public var isSecure = false

    public var value: String?
    public var charCount: Int?
    public var selectionLocation: Int?
    public var selectionLength: Int?
    public var selectedText: String?

    public var canReadValue = false
    public var canReadSelection = false
    public var canSetSelectedText = false

    public var note: String?

    public init() {}
}

@MainActor
public enum AXFocusInspector {
    /// Prevents snippets and layout correction from rewriting password input while
    /// allowing globally scoped snippets in every non-secure text field.
    nonisolated public static func focusedElementIsSecureTextField() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focusedRef,
        CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return false
        }

        let element = focusedRef as! AXUIElement
        return isSecureTextField(
            role: copyString(element, kAXRoleAttribute),
            subrole: copyString(element, kAXSubroleAttribute)
        )
    }

    /// Reads a small slice immediately before the insertion point. This is safe to
    /// call from the event-tap thread and avoids fetching an entire document when
    /// the focused control supports AXStringForRange.
    nonisolated public static func focusedTextBeforeCaret(maxUTF16Length: Int = 256) -> String? {
        guard AXIsProcessTrusted(), maxUTF16Length > 0 else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focusedRef,
        CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let element = focusedRef as! AXUIElement
        if isSecureTextField(
            role: copyString(element, kAXRoleAttribute),
            subrole: copyString(element, kAXSubroleAttribute)
        ) {
            return nil
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
        let rangeRef,
        CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }

        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection),
              selection.location >= 0,
              selection.length == 0 else {
            return nil
        }

        let start = max(0, selection.location - maxUTF16Length)
        var requestedRange = CFRange(
            location: start,
            length: selection.location - start
        )
        if let requestedValue = AXValueCreate(.cfRange, &requestedRange) {
            var textRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                requestedValue,
                &textRef
            ) == .success,
            let text = textRef as? String {
                return text
            }
        }

        guard let value = copyString(element, kAXValueAttribute) else { return nil }
        let nsValue = value as NSString
        guard selection.location <= nsValue.length else { return nil }
        let fallbackStart = max(0, selection.location - maxUTF16Length)
        return nsValue.substring(with: NSRange(
            location: fallbackStart,
            length: selection.location - fallbackStart
        ))
    }

    /// Reads the system-wide focused element and reports what it exposes.
    /// Never throws and never mutates anything — safe to poll on a timer.
    public static func capture() -> AXFocusSnapshot {
        var snap = AXFocusSnapshot()

        guard AXIsProcessTrusted() else {
            snap.note = "No Accessibility permission — grant it in System Settings › Privacy & Security › Accessibility."
            return snap
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )

        // Fall back to frontmost app identity even when no element is exposed
        // (e.g. Electron apps that don't build an AX tree) so "wake" can target it.
        if let app = NSWorkspace.shared.frontmostApplication {
            snap.appName = app.localizedName ?? "—"
            snap.appBundleID = app.bundleIdentifier
            snap.appPID = app.processIdentifier
        }

        guard err == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            snap.note = "No focused UI element reported (AX error \(err.rawValue)). " +
                "App likely doesn't expose the field — common in terminals and some Electron/web views."
            return snap
        }

        let element = focusedRef as! AXUIElement
        snap.hasFocus = true

        // Prefer the element's owning process for the app identity.
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success {
            snap.appPID = pid
            if let app = NSRunningApplication(processIdentifier: pid) {
                snap.appName = app.localizedName ?? snap.appName
                snap.appBundleID = app.bundleIdentifier ?? snap.appBundleID
            }
        }

        snap.role = copyString(element, kAXRoleAttribute)
        snap.subrole = copyString(element, kAXSubroleAttribute)
        snap.roleDescription = copyString(element, kAXRoleDescriptionAttribute)
        snap.title = copyString(element, kAXTitleAttribute)
        snap.identifier = copyString(element, kAXIdentifierAttribute)
        snap.placeholder = copyString(element, kAXPlaceholderValueAttribute)
        snap.isSecure = isSecureTextField(role: snap.role, subrole: snap.subrole)

        if let value = copyString(element, kAXValueAttribute) {
            snap.value = value
            snap.canReadValue = true
            snap.charCount = (value as NSString).length
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef,
           CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                snap.selectionLocation = range.location
                snap.selectionLength = range.length
                snap.canReadSelection = true
            }
        }

        snap.selectedText = copyString(element, kAXSelectedTextAttribute)

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success {
            snap.canSetSelectedText = settable.boolValue
        }

        return snap
    }

    /// Synthesizes ⌘C — the universal "give me the selection" primitive that
    /// works even where Accessibility exposes nothing (web content, Electron).
    /// The caller is responsible for reading/restoring the pasteboard.
    public static func pressCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) // 'c'
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    /// Synthesizes Backspace — deletes the current selection in place.
    public static func pressBackspace() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Synthesizes ⌘V — pastes the current pasteboard at the insertion point.
    public static func pressCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 'v'
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    /// Coaxes lazily-built accessibility trees (Chromium/Electron, some web
    /// views) into existing by setting the private "manual accessibility"
    /// attributes on the target app element. Best-effort, ignored if unsupported.
    public static func wakeAccessibilityTree(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    nonisolated private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        if let string = ref as? String { return string }
        if let number = ref as? NSNumber { return number.stringValue }
        return nil
    }

    nonisolated static func isSecureTextField(role: String?, subrole: String?) -> Bool {
        role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    public static func getCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement
        
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextBounds" as CFString, &boundsRef) == .success,
              let boundsRef,
              CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = boundsRef as! AXValue
        
        var rect = CGRect.zero
        if AXValueGetValue(axValue, .cgRect, &rect) {
            return rect
        }
        return nil
    }

    public static func getCaretScreenPoint() -> NSPoint? {
        guard let caretRect = getCaretRect() else { return nil }
        
        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        guard let screenHeight = primaryScreen?.frame.size.height else { return nil }
        
        let x = caretRect.origin.x
        let y = screenHeight - (caretRect.origin.y + caretRect.size.height)
        return NSPoint(x: x, y: y)
    }
}
