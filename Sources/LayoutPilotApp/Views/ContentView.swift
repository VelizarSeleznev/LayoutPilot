import LayoutPilotCore
import SwiftUI

struct ContentView: View {
    @Bindable var appState: LayoutPilotAppState
    @SceneStorage("layoutpilot.sidebar.selection")
    private var sidebarSelectionRaw = SidebarSection.overview.rawValue

    private var sidebarSelection: SidebarSection {
        get {
            guard let section = SidebarSection(rawValue: sidebarSelectionRaw),
                  SidebarSection.visibleCases.contains(section) else {
                return .overview
            }
            return section
        }
        set {
            sidebarSelectionRaw = newValue.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: sidebarSelectionBinding)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if let storedSection = SidebarSection(rawValue: sidebarSelectionRaw),
               !SidebarSection.visibleCases.contains(storedSection) {
                sidebarSelectionRaw = SidebarSection.overview.rawValue
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: appState.selectedSidebarSection) { _, newValue in
            if let newValue {
                sidebarSelectionRaw = newValue.rawValue
                appState.selectedSidebarSection = nil
            }
        }
    }

    private var sidebarSelectionBinding: Binding<SidebarSection> {
        Binding(
            get: { sidebarSelection },
            set: { newValue in
                sidebarSelectionRaw = newValue.rawValue
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch sidebarSelection {
        case .overview:
            OverviewView(appState: appState)
        case .rules:
            RulesView(appState: appState)
        case .websites:
            WebsitesView(appState: appState)
        case .profiles:
            ProfilesView(appState: appState)
        case .snippets:
            SnippetsView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        case .chat:
            ChatView()
        case .diagnostics:
            DiagnosticsView(appState: appState)
        }
    }
}
