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

        Settings {
            SettingsView(appState: appState)
        }

        MenuBarExtra("LayoutPilot", systemImage: "keyboard") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
