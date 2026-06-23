import AppKit
import LayoutPilotCore
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rewrites the user's current selection in place via Apple's on-device model.
///
/// Flow (single hotkey, ⌥⇧R):
///   1. back up the pasteboard
///   2. ⌘C to capture the selection (safety copy)
///   3. Backspace to delete it immediately — locks in the spot before the
///      selection can drift during generation
///   4. show a HUD so the user sees work in progress
///   5. generate, then ⌘V the result at the cursor; restore the pasteboard
///   On error the original text is pasted back so nothing is lost.
@MainActor
final class RewriteService {
    static let shared = RewriteService()

    private let hud = RewriteHUD()
    private var busy = false

    private static let instructions = """
    You are a writing assistant. Rewrite the user's text so it is clear, \
    grammatically correct and well structured. Preserve the original language, \
    meaning and intent. Do not add commentary. Reply with ONLY the rewritten \
    text — no preamble, no quotes, no explanations.
    """

    func run() {
        guard !busy else { return }
        busy = true

        let pasteboard = NSPasteboard.general
        let backup = pasteboard.string(forType: .string)
        let beforeChange = pasteboard.changeCount

        AXFocusInspector.pressCommandC()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))

            guard pasteboard.changeCount != beforeChange,
                  let original = pasteboard.string(forType: .string),
                  !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                restore(pasteboard, backup)
                busy = false
                return
            }

            // Selection is still active right after ⌘C — delete it now.
            AXFocusInspector.pressBackspace()
            hud.showWorking()

            do {
                let rewritten = try await Self.rewrite(original)
                await paste(rewritten, into: pasteboard)
                restore(pasteboard, backup)
                hud.showDone()
            } catch {
                // Put the original back so the user never loses their text.
                await paste(original, into: pasteboard)
                restore(pasteboard, backup)
                hud.showError(Self.message(for: error))
            }

            busy = false
        }
    }

    private func paste(_ text: String, into pasteboard: NSPasteboard) async {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(60))
        AXFocusInspector.pressCommandV()
        try? await Task.sleep(for: .milliseconds(150))
    }

    private func restore(_ pasteboard: NSPasteboard, _ backup: String?) {
        pasteboard.clearContents()
        if let backup { pasteboard.setString(backup, forType: .string) }
    }

    static func rewrite(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw RewriteError.unavailable
    }

    private static func message(for error: Error) -> String {
        if let error = error as? RewriteError { return error.text }
        return error.localizedDescription
    }
}

enum RewriteError: Error {
    case unavailable
    var text: String {
        switch self {
        case .unavailable: return "Apple-модель недоступна (нужен macOS 26 и Apple Intelligence)"
        }
    }
}

// MARK: - HUD

/// A small borderless, click-through floating HUD shown while rewriting.
@MainActor
@Observable
final class RewriteHUD {
    enum Phase: Equatable {
        case working
        case done
        case error(String)
    }

    var phase: Phase = .working

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func showWorking() {
        hideTask?.cancel()
        phase = .working
        present()
    }

    func showDone() {
        phase = .done
        present()
        scheduleHide(after: 0.8)
    }

    func showError(_ message: String) {
        phase = .error(message)
        present()
        scheduleHide(after: 2.5)
    }

    private func present() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RewriteHUDView(hud: self))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 110, y: frame.maxY - 120))
        } else {
            panel.center()
        }
        return panel
    }
}

private struct RewriteHUDView: View {
    @Bindable var hud: RewriteHUD

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(label)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .padding(6)
    }

    @ViewBuilder private var icon: some View {
        switch hud.phase {
        case .working: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var label: String {
        switch hud.phase {
        case .working: return "Переписываю…"
        case .done: return "Готово"
        case .error(let message): return message
        }
    }
}
