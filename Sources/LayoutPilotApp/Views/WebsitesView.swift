import LayoutPilotCore
import SwiftUI

struct WebsitesView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var draft = WebsiteLayoutRule(domain: "", profileID: UUID())

    private var websiteRules: [WebsiteLayoutRule] {
        let sorted = appState.store.configuration.websiteRules.sorted {
            $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending
        }
        guard !searchText.isEmpty else {
            return sorted
        }
        return sorted.filter {
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        let _ = appState.store.configuration.websiteRules
        let _ = appState.store.configuration.profiles

        HStack(spacing: 0) {
            websiteList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)

            Divider()

            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
        .navigationTitle("Websites")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: appState.store.configuration.websiteRules) { _, _ in
            ensureSelection()
        }
        .onChange(of: selection) { _, newValue in
            loadDraft(for: newValue)
        }
    }

    private var websiteList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Website Rules")
                    .font(.headline)
                Spacer()

                Button {
                    addWebsiteRule()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Website Rule")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter domains...", text: $searchText)
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
                ForEach(websiteRules) { rule in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(rule.domain)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if !rule.isEnabled {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        let profileName = appState.store.profile(for: rule.profileID)?.name ?? "Unknown Layout"
                        Text(profileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(Optional(rule.id))
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPanel: some View {
        Group {
            if selectedRule != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.domain.isEmpty ? "website.com" : draft.domain)
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
                            Text("Website Domain")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. github.com", text: Binding(
                                get: { draft.domain },
                                set: { newValue in
                                    draft.domain = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                    saveDraftIfValid()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target Layout Profile")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            Picker("", selection: Binding(
                                get: { draft.profileID },
                                set: { newValue in
                                    draft.profileID = newValue
                                    saveDraftIfValid()
                                }
                            )) {
                                ForEach(appState.store.configuration.profiles) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button(role: .destructive) {
                            if let selection {
                                appState.store.deleteWebsiteRule(id: selection)
                            }
                            selection = websiteRules.first?.id
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "trash")
                                Text("Delete Website Rule")
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
                    "No Website Rule Selected",
                    systemImage: "globe",
                    description: Text("Add a website domain layout rule to automatically switch input layout.")
                )
            }
        }
    }

    private var selectedRule: WebsiteLayoutRule? {
        guard let selection else {
            return nil
        }
        return appState.store.configuration.websiteRules.first { $0.id == selection }
    }

    private func ensureSelection() {
        if let selection,
           appState.store.configuration.websiteRules.contains(where: { $0.id == selection }) {
            loadDraft(for: selection)
            return
        }
        selection = websiteRules.first?.id
        loadDraft(for: selection)
    }

    private func loadDraft(for selection: UUID?) {
        guard let selection,
              let rule = appState.store.configuration.websiteRules.first(where: { $0.id == selection }) else {
            let defaultProfileID = appState.store.configuration.profiles.first?.id ?? UUID()
            draft = WebsiteLayoutRule(domain: "", profileID: defaultProfileID)
            return
        }
        draft = rule
    }

    private func addWebsiteRule() {
        var base = "example.com"
        var index = 1
        let existingDomains = Set(appState.store.configuration.websiteRules.map(\.domain))
        while existingDomains.contains(base) {
            index += 1
            base = "example\(index).com"
        }

        let defaultProfileID = appState.store.configuration.profiles.first?.id ?? UUID()
        let rule = WebsiteLayoutRule(domain: base, profileID: defaultProfileID)
        appState.store.upsertWebsiteRule(rule)
        selection = rule.id
        draft = rule
    }

    private func saveDraftIfValid() {
        let domain = draft.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            return
        }
        appState.store.upsertWebsiteRule(draft)
    }
}
