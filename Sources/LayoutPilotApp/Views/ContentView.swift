import LayoutPilotCore
import SwiftUI

struct ContentView: View {
    @Bindable var appState: LayoutPilotAppState
    @SceneStorage("layoutpilot.sidebar.selection")
    private var sidebarSelectionRaw = SidebarSection.overview.rawValue

    private var sidebarSelection: SidebarSection {
        get {
            SidebarSection(rawValue: sidebarSelectionRaw) ?? .overview
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
                .padding(20)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var sidebarSelectionBinding: Binding<SidebarSection> {
        Binding(
            get: { SidebarSection(rawValue: sidebarSelectionRaw) ?? .overview },
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
        case .chat:
            ChatView()
        case .diagnostics:
            DiagnosticsView(appState: appState)
        }
    }
}
