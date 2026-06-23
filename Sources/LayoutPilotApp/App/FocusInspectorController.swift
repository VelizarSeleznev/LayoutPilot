import AppKit
import LayoutPilotCore
import SwiftUI

/// Owns the always-on-top inspector panel. The panel is a non-activating
/// floating `NSPanel` so it never steals keyboard focus — the field you're
/// actually typing in stays focused, which is exactly what we want to inspect.
@MainActor
@Observable
final class FocusInspectorController {
    static let shared = FocusInspectorController()

    private(set) var isVisible = false
    var snapshot = AXFocusSnapshot()

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private lazy var windowObserver = WindowObserver(controller: self)

    func toggle() {
        NSLog("[Inspector] toggle, isVisible=\(isVisible)")
        isVisible ? hide() : show()
    }

    func show() {
        NSLog("[Inspector] show: enter (existing panel=\(panel != nil))")
        let panel = panel ?? makePanel()
        NSLog("[Inspector] show: panel ready")
        self.panel = panel
        panel.orderFrontRegardless()
        NSLog("[Inspector] show: ordered front, visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame))")
        isVisible = true
        startPolling()
        NSLog("[Inspector] show: done, isVisible=\(isVisible)")
    }

    func hide() {
        NSLog("[Inspector] hide")
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        isVisible = false
    }

    private func startPolling() {
        timer?.invalidate()
        capture()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func capture() {
        snapshot = AXFocusInspector.capture()
    }

    private func makePanel() -> NSPanel {
        NSLog("[Inspector] makePanel: creating NSPanel")
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        NSLog("[Inspector] makePanel: NSPanel created")
        panel.title = "AX Inspector"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // NOTE: canJoinAllSpaces and moveToActiveSpace are mutually exclusive —
        // combining them throws NSInvalidArgumentException.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSLog("[Inspector] makePanel: collectionBehavior set")
        panel.delegate = windowObserver
        NSLog("[Inspector] makePanel: setting hosting view")
        panel.contentView = NSHostingView(rootView: FocusInspectorView(controller: self))
        NSLog("[Inspector] makePanel: hosting view set")

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 400, y: frame.maxY - 20))
        } else {
            panel.center()
        }
        return panel
    }

    /// Bridges the panel's close button back into our visibility state.
    private final class WindowObserver: NSObject, NSWindowDelegate {
        weak var controller: FocusInspectorController?
        init(controller: FocusInspectorController) { self.controller = controller }

        func windowWillClose(_ notification: Notification) {
            NSLog("[Inspector] windowWillClose")
            controller?.hide()
        }
    }
}
