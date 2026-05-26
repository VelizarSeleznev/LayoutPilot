import LayoutPilotCore
import SwiftUI

struct ProfilesView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var selection: UUID?
    @State private var profileSearchText = ""
    @State private var draft = InputLayoutProfile(name: "", inputSourceID: "", notes: "")

    var filteredProfiles: [InputLayoutProfile] {
        if profileSearchText.isEmpty {
            return appState.store.configuration.profiles
        }
        return appState.store.configuration.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(profileSearchText) ||
            $0.inputSourceID.localizedCaseInsensitiveContains(profileSearchText)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            profileList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)

            Divider()

            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
        .navigationTitle("Input Profiles")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: appState.store.configuration.profiles) { _, _ in
            ensureSelection()
        }
        .onChange(of: selection) { _, newValue in
            loadDraft(for: newValue)
        }
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Profiles")
                    .font(.headline)
                Spacer()
                Button {
                    addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add profile")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter profiles...", text: $profileSearchText)
                    .textFieldStyle(.plain)
                if !profileSearchText.isEmpty {
                    Button {
                        profileSearchText = ""
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
                ForEach(filteredProfiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name.isEmpty ? "Untitled Profile" : profile.name)
                            .lineLimit(1)
                        Text(profile.inputSourceID.isEmpty ? "No input source" : profile.inputSourceID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPanel: some View {
        Group {
            if let selected = selection,
               let selectedProfile = appState.store.configuration.profiles.first(where: { $0.id == selected }) {
                ProfileEditorView(
                    profile: $draft,
                    onDelete: {
                        appState.store.deleteProfile(id: selected)
                        selection = appState.store.configuration.profiles.first?.id
                    }
                )
                .onChange(of: draft) { _, updatedProfile in
                    if updatedProfile.id == selectedProfile.id {
                        let original = appState.store.configuration.profiles.first(where: { $0.id == selectedProfile.id })
                        if original != updatedProfile {
                            appState.store.upsertProfile(updatedProfile)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "keyboard",
                    description: Text("Select an input profile or create a new one.")
                )
            }
        }
    }

    private func ensureSelection() {
        if selection == nil {
            selection = appState.store.configuration.profiles.first?.id
        }
        loadDraft(for: selection)
    }

    private func loadDraft(for selection: UUID?) {
        guard let selection,
              let profile = appState.store.configuration.profiles.first(where: { $0.id == selection }) else {
            return
        }
        draft = profile
    }

    private func addProfile() {
        let newProfile = InputLayoutProfile(
            name: "New Profile",
            inputSourceID: "com.apple.keylayout.US",
            notes: ""
        )
        appState.store.upsertProfile(newProfile)
        selection = newProfile.id
        draft = newProfile
    }
}

private struct ProfileEditorView: View {
    @Binding var profile: InputLayoutProfile
    let onDelete: () -> Void

    @State private var availableSources: [InputSourceInfo] = []
    @State private var selectedSourceID: String = ""
    @State private var showCustomField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name.isEmpty ? "Input Profile" : profile.name)
                            .font(.title2.weight(.bold))
                        Text(profile.inputSourceID.isEmpty ? "No layout specified" : profile.inputSourceID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

                Form {
                    Section("Profile Settings") {
                        TextField("Profile Name", text: $profile.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Section("Keyboard Layout") {
                        Picker("Input Source Layout", selection: $selectedSourceID) {
                            ForEach(availableSources) { source in
                                Text("\(source.localizedName) (\(source.sourceID))")
                                    .tag(source.sourceID)
                            }
                            
                            Text("Custom Layout ID...")
                                .tag("custom")
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedSourceID) { _, newValue in
                            if newValue == "custom" {
                                showCustomField = true
                            } else {
                                showCustomField = false
                                profile.inputSourceID = newValue
                            }
                        }
                        
                        if showCustomField {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Layout Source ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("e.g. com.apple.keylayout.US", text: $profile.inputSourceID)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.top, 4)
                        }
                    }

                    Section("Notes") {
                        TextField("Notes / Description", text: $profile.notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }
                }
                .formStyle(.grouped)

                // Delete Action
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Delete Profile")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            .padding(.trailing, 4)
        }
        .onAppear {
            loadAvailableSources()
        }
        .onChange(of: profile.id) { _, _ in
            syncPickerWithProfile()
        }
    }
    
    private func loadAvailableSources() {
        availableSources = SystemInputSourceClient().availableInputSources()
        syncPickerWithProfile()
    }
    
    private func syncPickerWithProfile() {
        if availableSources.contains(where: { $0.sourceID == profile.inputSourceID }) {
            selectedSourceID = profile.inputSourceID
            showCustomField = false
        } else {
            selectedSourceID = "custom"
            showCustomField = true
        }
    }
}
