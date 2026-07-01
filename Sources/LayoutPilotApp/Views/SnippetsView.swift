import LayoutPilotCore
import SwiftUI

struct SnippetsView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var draft = TextSnippet(trigger: "", replacement: "")

    private var snippets: [TextSnippet] {
        let sorted = appState.store.configuration.textSnippets.sorted {
            $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending
        }
        guard !searchText.isEmpty else {
            return sorted
        }
        return sorted.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.replacement.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        let _ = appState.store.configuration.textSnippets

        HStack(spacing: 0) {
            snippetList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)

            Divider()

            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
        .navigationTitle("Snippets")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: appState.store.configuration.textSnippets) { _, _ in
            ensureSelection()
        }
        .onChange(of: selection) { _, newValue in
            loadDraft(for: newValue)
        }
    }

    private var snippetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Text Snippets")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.store.configuration.textSnippetsEnabled },
                    set: { appState.store.setTextSnippetsEnabled($0) }
                ))
                .toggleStyle(.switch)
                .help(appState.store.configuration.textSnippetsEnabled ? "Disable snippets" : "Enable snippets")

                Button {
                    addSnippet()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add snippet")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter snippets...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: $selection) {
                ForEach(snippets) { snippet in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(snippet.trigger)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if !snippet.isEnabled {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(snippet.replacement.replacingOccurrences(of: "\n", with: " "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(Optional(snippet.id))
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPanel: some View {
        Group {
            if selectedSnippet != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.trigger.isEmpty ? "Snippet" : draft.trigger)
                                    .font(.title2.weight(.bold))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { draft.isEnabled },
                                set: { newValue in
                                    draft.isEnabled = newValue
                                    saveDraftIfValid()
                                }
                            ))
                            .toggleStyle(.switch)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Trigger")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Trigger", text: Binding(
                                get: { draft.trigger },
                                set: { newValue in
                                    draft.trigger = newValue
                                    saveDraftIfValid()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Replacement")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { draft.replacement },
                                set: { newValue in
                                    draft.replacement = newValue
                                    saveDraftIfValid()
                                }
                            ))
                            .font(.body)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        }

                        Button(role: .destructive) {
                            if let selection {
                                appState.store.deleteTextSnippet(id: selection)
                            }
                            selection = snippets.first?.id
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "trash")
                                Text("Delete Snippet")
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView(
                    "No Snippet Selected",
                    systemImage: "text.badge.plus",
                    description: Text("Add a snippet.")
                )
            }
        }
    }

    private var selectedSnippet: TextSnippet? {
        guard let selection else {
            return nil
        }
        return appState.store.configuration.textSnippets.first { $0.id == selection }
    }

    private func ensureSelection() {
        if let selection,
           appState.store.configuration.textSnippets.contains(where: { $0.id == selection }) {
            loadDraft(for: selection)
            return
        }
        selection = snippets.first?.id
        loadDraft(for: selection)
    }

    private func loadDraft(for selection: UUID?) {
        guard let selection,
              let snippet = appState.store.configuration.textSnippets.first(where: { $0.id == selection }) else {
            draft = TextSnippet(trigger: "", replacement: "")
            return
        }
        draft = snippet
    }

    private func addSnippet() {
        var base = "snippet"
        var index = 1
        let existingTriggers = Set(appState.store.configuration.textSnippets.map(\.trigger))
        while existingTriggers.contains(base) {
            index += 1
            base = "snippet\(index)"
        }

        let snippet = TextSnippet(trigger: base, replacement: "Expanded text")
        appState.store.upsertTextSnippet(snippet)
        selection = snippet.id
        draft = snippet
    }

    private func saveDraftIfValid() {
        guard !draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.replacement.isEmpty else {
            return
        }
        appState.store.upsertTextSnippet(draft)
    }
}
