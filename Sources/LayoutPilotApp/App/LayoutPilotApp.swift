import LayoutPilotCore
import SwiftUI

@main
struct LayoutPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = LayoutPilotAppState()

    var body: some Scene {
        Window("Layout Pilot", id: "main") {
            ContentView(appState: appState)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            LayoutPilotCommands(appState: appState)
        }

        MenuBarExtra("LayoutPilot", systemImage: "keyboard") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct LayoutPilotCommands: Commands {
    @Bindable var appState: LayoutPilotAppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appState.selectedSidebarSection = .settings
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
