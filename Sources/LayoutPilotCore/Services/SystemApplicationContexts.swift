import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum SystemApplicationContexts {
    public static let spotlight = RecentApplicationContext(
        applicationName: "Spotlight",
        bundleID: "com.apple.Spotlight"
    )

    private static let spotlightOwnerNames = Set(["Spotlight", "Siri"])
    private static let spotlightSearchIdentifier = "SpotlightSearchField"
    private static let spotlightSearchPlaceholder = "Spotlight Search"

    public static func activeContext(frontmostApplication: NSRunningApplication?) -> RecentApplicationContext {
        if isSpotlight(frontmostApplication) ||
            hasFocusedSpotlightSearchField() ||
            hasVisibleSpotlightWindow() {
            return spotlight
        }

        return RecentApplicationContext(
            applicationName: frontmostApplication?.localizedName ?? "Unknown",
            bundleID: frontmostApplication?.bundleIdentifier ?? "Unknown"
        )
    }

    private static func isSpotlight(_ application: NSRunningApplication?) -> Bool {
        application?.bundleIdentifier == spotlight.bundleID ||
            application?.localizedName == spotlight.applicationName
    }

    private static func hasVisibleSpotlightWindow() -> Bool {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return false
        }

        return windowInfo.contains { info in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  spotlightOwnerNames.contains(ownerName),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = dimension("Width", in: bounds),
                  let height = dimension("Height", in: bounds) else {
                return false
            }

            return width > 0 && height > 0
        }
    }

    private static func hasFocusedSpotlightSearchField() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = focusedRef as! AXUIElement
        if copyString(focusedElement, kAXIdentifierAttribute) == spotlightSearchIdentifier {
            return true
        }
        if copyString(focusedElement, kAXPlaceholderValueAttribute) == spotlightSearchPlaceholder {
            return true
        }

        return false
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func dimension(_ key: String, in bounds: [String: Any]) -> CGFloat? {
        if let value = bounds[key] as? CGFloat {
            return value
        }
        if let value = bounds[key] as? NSNumber {
            return CGFloat(truncating: value)
        }
        if let value = bounds[key] as? Double {
            return CGFloat(value)
        }
        return nil
    }
}
