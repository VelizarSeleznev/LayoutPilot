import AppKit
import ApplicationServices
import Foundation

/// Watches a browser for the events that can change its active URL.
///
/// Resolving the active URL is expensive: it costs an Apple Event round trip that wakes the
/// browser process too. Polling for it on a timer meant paying that cost tens of thousands of
/// times a day to observe a value that only changes when the user navigates or switches tabs.
/// Both of those show up as accessibility notifications, so the lookup can be demand-driven
/// instead, with the caller keeping a slow timer purely as a safety net for in-page navigation
/// that never touches the window title.
@MainActor
final class BrowserActivityObserver {
    private let coalescingInterval: TimeInterval = 0.3

    private var observer: AXObserver?
    private var applicationElement: AXUIElement?
    private var windowElement: AXUIElement?
    private var handler: (() -> Void)?
    private var pendingNotification: DispatchWorkItem?

    private static let applicationNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification
    ]
    private static let windowNotifications = [
        kAXTitleChangedNotification,
        kAXFocusedUIElementChangedNotification
    ]

    var isObserving: Bool { observer != nil }

    // No `deinit` cleanup on purpose: `deinit` is nonisolated and can run off the main thread,
    // where touching this actor's state would trap. Every path that stops observing calls
    // `stop()`, and the owner outlives the run loop it registered with.

    /// - Returns: `true` when the observer was installed. A `false` result means the caller
    ///   should fall back to polling alone.
    @discardableResult
    func start(pid: pid_t, onChange: @escaping () -> Void) -> Bool {
        stop()

        guard AXIsProcessTrusted() else { return false }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<BrowserActivityObserver>.fromOpaque(refcon)
                .takeUnretainedValue()
            MainActor.assumeIsolated { observer.notificationFired() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            return false
        }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        var registered = false
        for name in Self.applicationNotifications {
            let result = AXObserverAddNotification(created, element, name as CFString, refcon)
            registered = registered || result == .success
        }
        guard registered else { return false }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )

        observer = created
        applicationElement = element
        handler = onChange
        attachToFocusedWindow()
        return true
    }

    func stop() {
        pendingNotification?.cancel()
        pendingNotification = nil
        handler = nil

        guard let observer else {
            applicationElement = nil
            windowElement = nil
            return
        }

        detachFromWindow(observer: observer)
        if let applicationElement {
            for name in Self.applicationNotifications {
                AXObserverRemoveNotification(observer, applicationElement, name as CFString)
            }
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        self.observer = nil
        applicationElement = nil
    }

    private func notificationFired() {
        // A single navigation emits several notifications as the page settles, and the title
        // changes more than once while loading. Coalesce them into one URL lookup.
        attachToFocusedWindow()

        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNotification = nil
            self.handler?()
        }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalescingInterval, execute: work)
    }

    private func attachToFocusedWindow() {
        guard let observer, let applicationElement else { return }

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focused
        ) == .success else {
            detachFromWindow(observer: observer)
            return
        }

        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            detachFromWindow(observer: observer)
            return
        }
        // swiftlint:disable:next force_cast
        let window = focused as! AXUIElement
        guard window != windowElement else { return }

        detachFromWindow(observer: observer)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
        windowElement = window
    }

    private func detachFromWindow(observer: AXObserver) {
        guard let windowElement else { return }
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, windowElement, name as CFString)
        }
        self.windowElement = nil
    }
}
