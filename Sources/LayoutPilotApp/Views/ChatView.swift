import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A throwaway test surface for Apple's on-device Foundation Models LLM.
/// Lets you chat with `SystemLanguageModel.default` to gauge quality/latency
/// before deciding whether to wire it into the detection pipeline.
struct ChatView: View {
    @State private var model = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            availabilityBanner

            messagesList

            Divider()

            inputBar
        }
        .navigationTitle("LLM Chat (Test)")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.reset()
                } label: {
                    Label("Reset conversation", systemImage: "trash")
                }
                .help("Clear the transcript and start a fresh session")
            }
        }
    }

    private var availabilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.isAvailable ? .green : .orange)
            Text(model.availabilityText)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if !model.isAvailable {
                Button("Re-check") { model.checkAvailability() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        Text("Send a message to start testing the on-device model.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    ForEach(model.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.last?.text) {
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                .onSubmit { model.send() }
                .disabled(!model.isAvailable)

            Button {
                model.send()
            } label: {
                if model.isResponding {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.isAvailable || model.isResponding || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                )
                .frame(maxWidth: 460, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var input: String = ""
    var isResponding = false
    var availabilityText = "Checking availability…"
    var isAvailable = false

    // Held as `Any?` so the stored property doesn't reference a type that only
    // exists on macOS 26+ / when the FoundationModels SDK is present.
    private var session: Any?

    init() {
        checkAvailability()
    }

    func checkAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                isAvailable = true
                availabilityText = "On-device model available"
                session = LanguageModelSession()
            case .unavailable(let reason):
                isAvailable = false
                session = nil
                availabilityText = "Unavailable — \(String(describing: reason)). "
                    + "Apple Intelligence must be enabled and the system language set to a supported one (Russian is not supported)."
            @unknown default:
                isAvailable = false
                availabilityText = "Unavailable (unknown state)"
            }
        } else {
            isAvailable = false
            availabilityText = "Requires macOS 26 or later (you're on an older macOS)."
        }
        #else
        isAvailable = false
        availabilityText = "Built without the FoundationModels SDK — rebuild with Xcode 26 or later."
        #endif
    }

    func reset() {
        messages.removeAll()
        input = ""
        isResponding = false
        checkAvailability()
    }

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding, isAvailable else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let session = session as? LanguageModelSession {
            messages.append(ChatMessage(role: .assistant, text: ""))
            let replyIndex = messages.count - 1
            isResponding = true
            let started = Date()

            Task {
                do {
                    let response = try await session.respond(to: trimmed)
                    let elapsed = Date().timeIntervalSince(started)
                    messages[replyIndex].text = response.content
                        + String(format: "\n\n⏱ %.2fs", elapsed)
                } catch {
                    messages[replyIndex].text = "⚠️ \(error.localizedDescription)"
                }
                isResponding = false
            }
        }
        #endif
    }
}
