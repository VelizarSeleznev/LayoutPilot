import SwiftUI
import LayoutPilotCore

struct SuggestionsView: View {
    let context: SpellingSuggestionContext
    let onDismiss: () -> Void

    @State private var hoveredIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header hint
            Text("AUTO-CORRECTION ALTERNATIVES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()
                .background(.white.opacity(0.15))

            // Suggestions List
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(context.suggestions.enumerated()), id: \.offset) { index, word in
                    Button(action: {
                        context.selectCallback(word)
                        onDismiss()
                    }) {
                        HStack(spacing: 8) {
                            // Indicate if it's the original word (revert option)
                            if word == context.originalWord {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 11))
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 11))
                            }

                            Text(word)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(word == context.originalWord ? .orange : .primary)
                            
                            Spacer()
                            
                            // Badge with shortcut
                            if index < 5 {
                                Text("⌥\(index + 1)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        hoveredIndex == index
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onHover { isHovered in
                        hoveredIndex = isHovered ? index : nil
                    }
                }
            }
            .padding(4)

            Divider()
                .background(.white.opacity(0.15))

            // Footer hint
            HStack {
                Text("Esc to close")
                Spacer()
                Text("Mouse click or hotkey")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}
