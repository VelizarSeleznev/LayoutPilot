import LayoutPilotCore
import SwiftUI

/// Live view of what Accessibility currently exposes for the focused field.
/// Rendered inside the floating inspector panel.
struct FocusInspectorView: View {
    @Bindable var controller: FocusInspectorController

    private var snap: AXFocusSnapshot { controller.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appHeader
                capabilityBadges
                identitySection
                cursorSection
                valueSection

                if let note = snap.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 360)
    }

    private var appHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(snap.hasFocus ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.appName).font(.headline).lineLimit(1)
                if let bundleID = snap.appBundleID {
                    Text(bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var capabilityBadges: some View {
        HStack(spacing: 6) {
            badge("Value", on: snap.canReadValue)
            badge("Cursor", on: snap.canReadSelection)
            badge("Writable", on: snap.canSetSelectedText)
            if snap.isSecure {
                Text("Secure")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.18)))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ label: String, on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill((on ? Color.green : Color.gray).opacity(0.18)))
        .foregroundStyle(on ? .green : .secondary)
    }

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                row("Role", snap.role)
                row("Subrole", snap.subrole)
                row("Description", snap.roleDescription)
                row("Title", snap.title)
                row("Identifier", snap.identifier)
                row("Placeholder", snap.placeholder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Field", systemImage: "character.cursor.ibeam")
        }
    }

    private var cursorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                row("Characters", snap.charCount.map(String.init))
                row("Cursor at", snap.selectionLocation.map(String.init))
                row("Selection len", snap.selectionLength.map(String.init))
                if let selected = snap.selectedText, !selected.isEmpty {
                    row("Selected", "\"\(selected)\"")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Cursor", systemImage: "selection.pin.in.out")
        }
    }

    private var valueSection: some View {
        GroupBox {
            Group {
                if snap.isSecure {
                    Text("Hidden (secure field)").foregroundStyle(.secondary)
                } else if let preview = valueWithCursor {
                    Text(preview)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Not exposed by this app").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Content (▏ = cursor, ⟦ ⟧ = selection)", systemImage: "text.alignleft")
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value ?? "—")
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Reconstructs the field's text with a visible marker where the cursor /
    /// selection sits — the whole point of "show me what it sees".
    private var valueWithCursor: String? {
        guard let value = snap.value else { return nil }
        let text = value as NSString
        guard let location = snap.selectionLocation,
              location >= 0, location <= text.length else { return value }

        let length = snap.selectionLength ?? 0
        let before = text.substring(to: location)

        guard length > 0, location + length <= text.length else {
            let after = text.substring(from: location)
            return before + "▏" + after
        }

        let selected = text.substring(with: NSRange(location: location, length: length))
        let after = text.substring(from: location + length)
        return before + "⟦" + selected + "⟧" + after
    }
}
