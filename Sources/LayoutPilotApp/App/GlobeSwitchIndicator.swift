import AppKit
import LayoutPilotCore
import Observation
import SwiftUI

@MainActor
@Observable
final class GlobeSwitchIndicator {
    static let shared = GlobeSwitchIndicator()

    var source = InputSourceInfo(sourceID: "", localizedName: "")

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    var languageCode: String {
        if let languageTag = source.languageTag,
           let language = languageTag.split(separator: "-").first,
           !language.isEmpty {
            return language.uppercased()
        }

        let lowercasedID = source.sourceID.lowercased()
        if lowercasedID.contains("russian") || lowercasedID.contains(".ru") {
            return "RU"
        }
        if lowercasedID.contains(".us") || lowercasedID.contains(".abc") {
            return "EN"
        }
        return String(source.localizedName.prefix(2)).uppercased()
    }

    func show(source: InputSourceInfo) {
        hideTask?.cancel()
        self.source = source

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let panel else { return }

            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            self?.hideTask = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.contentView = NSHostingView(rootView: GlobeSwitchIndicatorView(indicator: self))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 20,
            y: visibleFrame.maxY - panel.frame.height - 16
        ))
    }
}

private struct GlobeSwitchIndicatorView: View {
    @Bindable var indicator: GlobeSwitchIndicator

    var body: some View {
        HStack(spacing: 10) {
            Text(indicator.languageCode)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))

            Text(indicator.source.localizedName)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12)))
        .padding(5)
    }
}
