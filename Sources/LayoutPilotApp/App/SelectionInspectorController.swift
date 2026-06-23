import AppKit
import LayoutPilotCore
import SwiftUI

/// Floating panel that shows what we can actually read as the user's *selection*
/// in the frontmost app — live via Accessibility, and on-demand via a ⌘C probe.
/// Same non-activating floating-panel pattern as the focus inspector so the
/// target app keeps keyboard focus.
@MainActor
@Observable
final class SelectionInspectorController {
    static let shared = SelectionInspectorController()

    private(set) var isVisible = false
    var snapshot = AXFocusSnapshot()
    var probeResult: String?
    var probeRunning = false
    var wakeStatus: String?

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private lazy var windowObserver = WindowObserver(controller: self)

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        isVisible = true
        startPolling()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        isVisible = false
    }

    /// On-demand ⌘C probe: copy the selection, read it, then restore the
    /// pasteboard. Manual (not polled) so we never trash the clipboard in the
    /// background. Note: only the string representation is restored.
    func runClipboardProbe() {
        guard !probeRunning else { return }
        probeRunning = true
        Task { @MainActor in
            let pasteboard = NSPasteboard.general
            let saved = pasteboard.string(forType: .string)
            let beforeChange = pasteboard.changeCount

            AXFocusInspector.pressCommandC()
            try? await Task.sleep(for: .milliseconds(160))

            if pasteboard.changeCount != beforeChange {
                probeResult = pasteboard.string(forType: .string) ?? "(copied non-text)"
            } else {
                probeResult = "(nothing copied — no selection, or app ignored ⌘C)"
            }

            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
            probeRunning = false
        }
    }

    func wakeTree() {
        guard let pid = snapshot.appPID else {
            wakeStatus = "No focused app to wake"
            return
        }
        AXFocusInspector.wakeAccessibilityTree(pid: pid)
        wakeStatus = "Sent to \(snapshot.appName) — now interact there and watch the live readout"
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Selection Inspector"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = windowObserver
        panel.contentView = NSHostingView(rootView: SelectionInspectorView(controller: self))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 400, y: frame.maxY - 540))
        } else {
            panel.center()
        }
        return panel
    }

    private final class WindowObserver: NSObject, NSWindowDelegate {
        weak var controller: SelectionInspectorController?
        init(controller: SelectionInspectorController) { self.controller = controller }

        func windowWillClose(_ notification: Notification) {
            controller?.hide()
        }
    }
}
