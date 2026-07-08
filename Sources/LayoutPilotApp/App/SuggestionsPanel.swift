import AppKit
import LayoutPilotCore
import SwiftUI

@MainActor
final class SuggestionsPanel {
    static let shared = SuggestionsPanel()

    private var panel: NSPanel?
    private(set) var isVisible = false

    func show(context: SpellingSuggestionContext) {
        let p = panel ?? makePanel()
        self.panel = p

        // Update content view with the new context
        p.contentView = NSHostingView(
            rootView: SuggestionsView(
                context: context,
                onDismiss: { [weak self] in
                    self?.hide()
                }
            )
        )

        // Calculate position: below caret, or fallback to mouse cursor
        let targetPoint: NSPoint
        if let caretPoint = AXFocusInspector.getCaretScreenPoint() {
            // Position slightly offset so it doesn't overlap the word directly
            targetPoint = NSPoint(x: caretPoint.x - 10, y: caretPoint.y - 4)
        } else {
            let mouseLoc = NSEvent.mouseLocation
            targetPoint = NSPoint(x: mouseLoc.x - 10, y: mouseLoc.y - 20)
        }

        p.setFrameTopLeftPoint(targetPoint)
        p.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .popUpMenu // Pop it above regular floating windows
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = false // Allow user to click suggestions
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}
