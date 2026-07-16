import LayoutPilotCore
import SwiftUI

struct SnippetsView: View {
    @Bindable var appState: LayoutPilotAppState

    @State private var selection: UUID?
    @State private var draft = TextSnippet(name: "", trigger: "", replacement: "")
    @State private var searchText = ""
    @State private var listFilter = SnippetListFilter.all
    @State private var validationMessage: String?
    @State private var pendingSelection: UUID?
    @State private var showsUnsavedChanges = false
    @State private var showsNewSnippet = false
    @State private var showsFolderEditor = false
    @State private var folderToEdit: TextSnippetGroup?
    @State private var snippetPendingDeletion: TextSnippet?
    @State private var folderPendingDeletion: TextSnippetGroup?

    private var configuration: LayoutPilotConfiguration {
        appState.store.configuration
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .frame(minWidth: 270, idealWidth: 320, maxWidth: 350)

            Divider()

            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Snippets")
        .onAppear { ensureSelection() }
        .onChange(of: configuration.textSnippets) { _, _ in ensureSelection() }
        .onChange(of: configuration.textSnippetGroups) { _, groups in
            if case .group(let id) = listFilter, !groups.contains(where: { $0.id == id }) {
                listFilter = .all
            }
        }
        .sheet(isPresented: $showsNewSnippet) {
            NewSnippetSheet(
                store: appState.store,
                groups: configuration.textSnippetGroups,
                applications: availableApplications
            ) { snippet in
                selection = snippet.id
                draft = snippet
                validationMessage = nil
            }
        }
        .sheet(isPresented: $showsFolderEditor, onDismiss: { folderToEdit = nil }) {
            FolderEditorSheet(
                store: appState.store,
                group: folderToEdit,
                applications: availableApplications
            )
        }
        .confirmationDialog(
            "Save changes to \(draft.name.isEmpty ? "this snippet" : draft.name)?",
            isPresented: $showsUnsavedChanges,
            titleVisibility: .visible
        ) {
            Button("Save Changes") {
                if saveDraft(), let pendingSelection {
                    selectImmediately(pendingSelection)
                }
            }
            Button("Discard Changes", role: .destructive) {
                if let pendingSelection {
                    selectImmediately(pendingSelection)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text("Your edits have not been saved yet.")
        }
        .alert(
            "Delete snippet?",
            isPresented: Binding(
                get: { snippetPendingDeletion != nil },
                set: { if !$0 { snippetPendingDeletion = nil } }
            ),
            presenting: snippetPendingDeletion
        ) { snippet in
            Button("Delete \(snippet.name)", role: .destructive) {
                deleteSnippet(snippet)
            }
            Button("Cancel", role: .cancel) {}
        } message: { snippet in
            Text("The trigger \(snippet.trigger) will stop expanding immediately.")
        }
        .alert(
            "Delete folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            presenting: folderPendingDeletion
        ) { group in
            Button("Delete \(group.name)", role: .destructive) {
                appState.store.deleteTextSnippetGroup(id: group.id)
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("Snippets in \(group.name) will become ungrouped. They will not be deleted.")
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text Snippets").font(.headline)
                    Text("\(configuration.textSnippets.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Active", isOn: Binding(
                    get: { configuration.textSnippetsEnabled },
                    set: { appState.store.setTextSnippetsEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(configuration.textSnippetsEnabled ? "Pause text expansion" : "Activate text expansion")

                Menu {
                    Button("New Snippet", systemImage: "text.badge.plus") {
                        showsNewSnippet = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        folderToEdit = nil
                        showsFolderEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Create a snippet or folder")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Expand snippets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Expand snippets", selection: Binding(
                    get: { configuration.textSnippetExpansionMode },
                    set: { appState.store.setTextSnippetExpansionMode($0) }
                )) {
                    Text("Immediately").tag(TextSnippetExpansionMode.immediately)
                    Text("After Space").tag(TextSnippetExpansionMode.afterSpace)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .help(expansionModeHelp)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            searchField

            Picker("Folder", selection: $listFilter) {
                Text("All Snippets").tag(SnippetListFilter.all)
                Text("Ungrouped").tag(SnippetListFilter.ungrouped)
                if !configuration.textSnippetGroups.isEmpty {
                    Divider()
                    ForEach(configuration.textSnippetGroups) { group in
                        Text(group.name).tag(SnippetListFilter.group(group.id))
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            if snippetSections.isEmpty {
                listEmptyState
            } else {
                List {
                    ForEach(snippetSections) { section in
                        Section {
                            ForEach(section.snippets) { snippet in
                                snippetRow(snippet)
                            }
                        } header: {
                            folderHeader(section)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search snippets", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var expansionModeHelp: String {
        switch configuration.textSnippetExpansionMode {
        case .immediately:
            return "Replace a trigger as soon as its final character is typed."
        case .afterSpace:
            return "Replace a trigger only when Space is pressed after it."
        }
    }

    private var listEmptyState: some View {
        ContentUnavailableView {
            Label(
                configuration.textSnippets.isEmpty ? "No Snippets Yet" : "No Matching Snippets",
                systemImage: configuration.textSnippets.isEmpty ? "text.badge.plus" : "magnifyingglass"
            )
        } description: {
            Text(configuration.textSnippets.isEmpty
                 ? "Create one snippet now. Folders are optional."
                 : "Try another search or folder.")
        } actions: {
            if configuration.textSnippets.isEmpty {
                Button("Create Snippet") { showsNewSnippet = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Clear Filters") {
                    searchText = ""
                    listFilter = .all
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func folderHeader(_ section: SnippetSection) -> some View {
        HStack {
            Label(section.title, systemImage: section.group == nil ? "tray" : "folder")
            Spacer()
            if let group = section.group {
                Menu {
                    Button("Edit Folder") {
                        folderToEdit = group
                        showsFolderEditor = true
                    }
                    Button("Delete Folder", role: .destructive) {
                        folderPendingDeletion = group
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Folder actions for \(group.name)")
            }
        }
    }

    private func snippetRow(_ snippet: TextSnippet) -> some View {
        Button {
            requestSelection(snippet.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snippet.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !snippet.isEnabled {
                        Image(systemName: "pause.circle")
                            .foregroundStyle(.secondary)
                            .help("Snippet paused")
                    }
                }
                Text(snippet.trigger)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                Text(snippet.replacement.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selection == snippet.id ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(snippet.isEnabled ? "Pause Snippet" : "Activate Snippet") {
                var updated = snippet
                updated.isEnabled.toggle()
                _ = appState.store.saveTextSnippet(updated)
            }
            Divider()
            Button("Delete Snippet", role: .destructive) {
                snippetPendingDeletion = snippet
            }
        }
    }

    private var editorPane: some View {
        Group {
            if selectedStoredSnippet != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        editorHeader

                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Name").font(.headline)
                            TextField("e.g. Work signature", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Trigger").font(.headline)
                            TextField("e.g. ;sig", text: $draft.trigger)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Text").font(.headline)
                            TextEditor(text: $draft.replacement)
                                .font(.body)
                                .frame(minHeight: 190)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                        }

                        GroupBox("Organization & Apps") {
                            VStack(alignment: .leading, spacing: 14) {
                                Picker("Folder", selection: $draft.groupID) {
                                    Text("None").tag(Optional<UUID>.none)
                                    ForEach(configuration.textSnippetGroups) { group in
                                        Text(group.name).tag(Optional(group.id))
                                    }
                                }
                                .pickerStyle(.menu)

                                Divider()

                                SnippetScopeEditor(
                                    scope: $draft.applicationScopeOverride,
                                    group: configuration.textSnippetGroups.first { $0.id == draft.groupID },
                                    applications: availableApplications
                                )
                            }
                            .padding(8)
                        }

                        HStack {
                            Button("Delete Snippet", role: .destructive) {
                                snippetPendingDeletion = selectedStoredSnippet
                            }
                            Spacer()
                            Button("Cancel") { loadDraft(for: selection) }
                                .disabled(!isDirty)
                            Button("Save Changes") { _ = saveDraft() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut("s", modifiers: .command)
                                .disabled(!isDirty)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "Select a Snippet",
                    systemImage: "text.badge.plus",
                    description: Text("Choose a snippet from the list or create a new one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? "Snippet" : draft.name)
                    .font(.largeTitle.weight(.semibold))
                Text(draft.trigger.isEmpty ? "Add a trigger" : "Expands when you type \(draft.trigger)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Active", isOn: $draft.isEnabled)
                .toggleStyle(.switch)
        }
    }

    private var selectedStoredSnippet: TextSnippet? {
        guard let selection else { return nil }
        return configuration.textSnippets.first { $0.id == selection }
    }

    private var isDirty: Bool {
        guard let stored = selectedStoredSnippet else { return false }
        return draft != stored
    }

    private var filteredSnippets: [TextSnippet] {
        configuration.textSnippets.filter { snippet in
            let matchesFilter: Bool
            switch listFilter {
            case .all:
                matchesFilter = true
            case .ungrouped:
                matchesFilter = snippet.groupID == nil
            case .group(let groupID):
                matchesFilter = snippet.groupID == groupID
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let groupName = configuration.textSnippetGroups.first { $0.id == snippet.groupID }?.name ?? ""
            return snippet.name.localizedCaseInsensitiveContains(searchText)
                || snippet.trigger.localizedCaseInsensitiveContains(searchText)
                || snippet.replacement.localizedCaseInsensitiveContains(searchText)
                || groupName.localizedCaseInsensitiveContains(searchText)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var snippetSections: [SnippetSection] {
        let grouped = Dictionary(grouping: filteredSnippets, by: \.groupID)
        var sections: [SnippetSection] = []
        if let ungrouped = grouped[nil], !ungrouped.isEmpty {
            sections.append(SnippetSection(id: "ungrouped", title: "Ungrouped", group: nil, snippets: ungrouped))
        }
        for group in configuration.textSnippetGroups {
            if let snippets = grouped[group.id], !snippets.isEmpty {
                sections.append(SnippetSection(id: group.id.uuidString, title: group.name, group: group, snippets: snippets))
            }
        }
        return sections
    }

    private var availableApplications: [SnippetApplicationChoice] {
        var names: [String: String] = [:]
        for app in appState.engine.recentApplications {
            names[app.bundleID] = app.applicationName
        }
        if let app = appState.engine.lastExternalApplication {
            names[app.bundleID] = app.applicationName
        }
        for rule in configuration.rules {
            names[rule.applicationBundleID] = rule.applicationName
        }
        let configuredIDs = configuration.smartDanishInputAllowedBundleIDs
            + configuration.smartBilingualAllowedBundleIDs
            + configuration.textSnippetGroups.flatMap(\.applicationScope.bundleIDs)
            + configuration.textSnippets.compactMap(\.applicationScopeOverride).flatMap(\.bundleIDs)
        for bundleID in configuredIDs where names[bundleID] == nil {
            names[bundleID] = bundleID
        }
        return names.compactMap { bundleID, name in
            guard !TextSnippetPolicy.securityExcludedBundleIDs.contains(bundleID) else { return nil }
            return SnippetApplicationChoice(name: name, bundleID: bundleID)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func ensureSelection() {
        if let selection, configuration.textSnippets.contains(where: { $0.id == selection }) {
            if !isDirty { loadDraft(for: selection) }
            return
        }
        selection = filteredSnippets.first?.id ?? configuration.textSnippets.first?.id
        loadDraft(for: selection)
    }

    private func requestSelection(_ id: UUID) {
        guard selection != id else { return }
        if isDirty {
            pendingSelection = id
            showsUnsavedChanges = true
        } else {
            selectImmediately(id)
        }
    }

    private func selectImmediately(_ id: UUID) {
        pendingSelection = nil
        selection = id
        loadDraft(for: id)
    }

    private func loadDraft(for id: UUID?) {
        guard let id, let snippet = configuration.textSnippets.first(where: { $0.id == id }) else {
            draft = TextSnippet(name: "", trigger: "", replacement: "")
            validationMessage = nil
            return
        }
        draft = snippet
        validationMessage = nil
    }

    @discardableResult
    private func saveDraft() -> Bool {
        switch appState.store.saveTextSnippet(draft) {
        case .success(let saved):
            draft = saved
            validationMessage = nil
            return true
        case .failure(let error):
            validationMessage = error.localizedDescription
            return false
        }
    }

    private func deleteSnippet(_ snippet: TextSnippet) {
        let visibleIDs = filteredSnippets.map(\.id)
        let index = visibleIDs.firstIndex(of: snippet.id)
        appState.store.deleteTextSnippet(id: snippet.id)
        snippetPendingDeletion = nil
        let remaining = visibleIDs.filter { $0 != snippet.id }
        if let index, !remaining.isEmpty {
            let nextIndex = min(index, remaining.count - 1)
            selectImmediately(remaining[nextIndex])
        } else {
            selection = configuration.textSnippets.first?.id
            loadDraft(for: selection)
        }
    }
}

private enum SnippetListFilter: Hashable {
    case all
    case ungrouped
    case group(UUID)
}

private struct SnippetSection: Identifiable {
    let id: String
    let title: String
    let group: TextSnippetGroup?
    let snippets: [TextSnippet]
}

private struct SnippetApplicationChoice: Identifiable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
}

private struct NewSnippetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: LayoutPilotStore
    let groups: [TextSnippetGroup]
    let applications: [SnippetApplicationChoice]
    let onCreated: (TextSnippet) -> Void

    @State private var draft = TextSnippet(name: "", trigger: "", replacement: "")
    @State private var showsOptions = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Snippet").font(.title2.weight(.semibold))
                    Text("Type a short trigger and LayoutPilot will replace it with your text.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                TextField("Name", text: $draft.name, prompt: Text("Work signature"))
                    .textFieldStyle(.roundedBorder)
                TextField("Trigger", text: $draft.trigger, prompt: Text(";sig"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text").font(.headline)
                    TextEditor(text: $draft.replacement)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }

                DisclosureGroup("Organization & Apps", isExpanded: $showsOptions) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Folder", selection: $draft.groupID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .pickerStyle(.menu)

                        SnippetScopeEditor(
                            scope: $draft.applicationScopeOverride,
                            group: groups.first { $0.id == draft.groupID },
                            applications: applications
                        )
                    }
                    .padding(.top, 10)
                }
            }
            .padding(22)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasRequiredFields)
            }
            .padding(14)
        }
        .frame(width: 560)
    }

    private var hasRequiredFields: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        switch store.saveTextSnippet(draft) {
        case .success(let snippet):
            onCreated(snippet)
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

private struct FolderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: LayoutPilotStore
    let applications: [SnippetApplicationChoice]

    @State private var draft: TextSnippetGroup
    @State private var optionalScope: SnippetApplicationScope?
    @State private var showsError = false

    init(
        store: LayoutPilotStore,
        group: TextSnippetGroup?,
        applications: [SnippetApplicationChoice]
    ) {
        self.store = store
        self.applications = applications
        let value = group ?? TextSnippetGroup(name: "")
        _draft = State(initialValue: value)
        _optionalScope = State(initialValue: value.applicationScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(draft.name.isEmpty ? "New Folder" : "Edit Folder")
                    .font(.title2.weight(.semibold))

                if showsError {
                    Text("Enter a folder name.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                TextField("Folder name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                ScopeEditor(
                    scope: $optionalScope,
                    inheritanceLabel: nil,
                    applications: applications
                )
            }
            .padding(22)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Folder") {
                    draft.applicationScope = optionalScope ?? SnippetApplicationScope()
                    if store.saveTextSnippetGroup(draft) != nil {
                        dismiss()
                    } else {
                        showsError = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520)
    }
}

private struct SnippetScopeEditor: View {
    @Binding var scope: SnippetApplicationScope?
    let group: TextSnippetGroup?
    let applications: [SnippetApplicationChoice]

    var body: some View {
        ScopeEditor(
            scope: $scope,
            inheritanceLabel: group.map { "Inherit from \($0.name)" } ?? "All applications (default)",
            applications: applications
        )
    }
}

private struct ScopeEditor: View {
    @Binding var scope: SnippetApplicationScope?
    let inheritanceLabel: String?
    let applications: [SnippetApplicationChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Availability", selection: modeBinding) {
                if let inheritanceLabel {
                    Text(inheritanceLabel).tag(ScopeEditorMode.inherit)
                }
                Text("All applications").tag(ScopeEditorMode.all)
                Text("Only selected applications").tag(ScopeEditorMode.only)
                Text("All except selected applications").tag(ScopeEditorMode.allExcept)
            }
            .pickerStyle(.menu)

            if modeBinding.wrappedValue == .only || modeBinding.wrappedValue == .allExcept {
                if applications.isEmpty {
                    Text("Applications appear here after you use them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(applications) { application in
                            Toggle(isOn: bundleBinding(application.bundleID)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(application.name)
                                    Text(application.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    private var modeBinding: Binding<ScopeEditorMode> {
        Binding(
            get: {
                guard let scope else { return inheritanceLabel == nil ? .all : .inherit }
                switch scope.mode {
                case .allApplications: return .all
                case .onlySelected: return .only
                case .allExceptSelected: return .allExcept
                }
            },
            set: { mode in
                let currentIDs = scope?.bundleIDs ?? []
                switch mode {
                case .inherit:
                    scope = nil
                case .all:
                    scope = SnippetApplicationScope(mode: .allApplications)
                case .only:
                    scope = SnippetApplicationScope(mode: .onlySelected, bundleIDs: currentIDs)
                case .allExcept:
                    scope = SnippetApplicationScope(mode: .allExceptSelected, bundleIDs: currentIDs)
                }
            }
        )
    }

    private func bundleBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { scope?.bundleIDs.contains(bundleID) ?? false },
            set: { enabled in
                guard let current = scope else { return }
                var bundleIDs = current.bundleIDs.filter { $0 != bundleID }
                if enabled { bundleIDs.append(bundleID) }
                scope = SnippetApplicationScope(mode: current.mode, bundleIDs: bundleIDs)
            }
        )
    }
}

private enum ScopeEditorMode: String, Hashable {
    case inherit
    case all
    case only
    case allExcept
}
