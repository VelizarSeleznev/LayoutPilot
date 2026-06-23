import LayoutPilotCore
import SwiftUI

/// Live view of the current selection, read three ways so you can compare
/// coverage per app: AX selected-text, AX value+range slice, and a ⌘C probe.
struct SelectionInspectorView: View {
    @Bindable var controller: SelectionInspectorController

    private var snap: AXFocusSnapshot { controller.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appHeader

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        labeled("AX selected text", axSelectedText)
                        Divider()
                        labeled("AX value + range slice", valueRangeSlice)
                        Divider()
                        labeled("Range", rangeText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Live (read-only)", systemImage: "dot.radiowaves.left.and.right")
                }

                clipboardProbeSection
                wakeSection

                Text("Live readout polls Accessibility. The ⌘C probe is the universal fallback that also works in web/Electron — it runs only when you press it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 340)
    }

    private var appHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(snap.hasFocus ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(snap.appName).font(.headline).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var clipboardProbeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        controller.runClipboardProbe()
                    } label: {
                        Label("Probe via ⌘C", systemImage: "doc.on.clipboard")
                    }
                    .disabled(controller.probeRunning)
                    if controller.probeRunning {
                        ProgressView().controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
                if let result = controller.probeResult {
                    Text("Captured \(result.count) chars:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Select text in any app, then press the button.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Clipboard probe", systemImage: "clipboard")
        }
    }

    private var wakeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    controller.wakeTree()
                } label: {
                    Label("Wake AX tree", systemImage: "wand.and.stars")
                }
                if let status = controller.wakeStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Coax Electron / web", systemImage: "wand.and.stars")
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var axSelectedText: String {
        guard let text = snap.selectedText, !text.isEmpty else { return "—" }
        return "\"\(text)\""
    }

    private var rangeText: String {
        guard let location = snap.selectionLocation else { return "not exposed" }
        return "location \(location), length \(snap.selectionLength ?? 0)"
    }

    private var valueRangeSlice: String {
        guard let value = snap.value,
              let location = snap.selectionLocation,
              let length = snap.selectionLength, length > 0 else { return "—" }
        let text = value as NSString
        guard location >= 0, location + length <= text.length else { return "—" }
        return "\"\(text.substring(with: NSRange(location: location, length: length)))\""
    }
}
