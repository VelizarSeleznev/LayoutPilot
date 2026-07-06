import AppKit
import ApplicationServices
import Foundation

public enum BrowserURLService {
    public static func activeURL(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return nil
        }
        let window = windowRef as! AXUIElement
        
        if app.bundleIdentifier == "com.apple.Safari" {
            return getSafariURL(window)
        } else if isChromiumOrFirefox(app.bundleIdentifier) {
            return getChromiumOrFirefoxURL(window)
        }
        
        return nil
    }
    
    public static func isBrowser(bundleID: String) -> Bool {
        let browsers = Set([
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser", // Arc
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser"
        ])
        return browsers.contains(bundleID)
    }
    
    private static func isChromiumOrFirefox(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return isBrowser(bundleID: bundleID) && bundleID != "com.apple.Safari"
    }
    
    private static func getSafariURL(_ window: AXUIElement) -> String? {
        // In Safari, the window's AXDocument attribute directly contains the URL of the active tab.
        var docRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef) == .success,
           let docURLString = docRef as? String {
            return docURLString
        }
        
        // Fallback: Traverse window elements
        return findAddressBarURL(window)
    }
    
    private static func getChromiumOrFirefoxURL(_ window: AXUIElement) -> String? {
        return findAddressBarURL(window)
    }
    
    private static func findAddressBarURL(_ element: AXUIElement, depth: Int = 0) -> String? {
        if depth > 30 { return nil } // Prevent too deep recursion
        
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return nil
        }
        
        // CRITICAL PERFORMANCE OPTIMIZATION:
        // Skip traversing the web content hierarchy entirely.
        // Web pages contain thousands of elements; traversing them will freeze the main thread.
        if role == "AXWebArea" || role == "AXWebView" {
            return nil
        }
        
        if role == "AXTextField" || role == "AXTextArea" {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let valStr = valueRef as? String {
                let trimmed = valStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.starts(with: "http://") || trimmed.starts(with: "https://") {
                    return trimmed
                }
                // Check if it looks like a domain name (e.g. github.com, google.com)
                if trimmed.contains("."), !trimmed.contains(" "), !trimmed.contains("@"), !trimmed.contains("/") {
                    return "https://" + trimmed
                }
            }
        }
        
        // Traverse children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let url = findAddressBarURL(child, depth: depth + 1) {
                    return url
                }
            }
        }
        
        return nil
    }
}
