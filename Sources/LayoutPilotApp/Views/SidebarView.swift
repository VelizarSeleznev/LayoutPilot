import LayoutPilotCore
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        List(selection: $selection) {
            sidebarRow(.overview)

            Section("Rules") {
                sidebarRow(.rules)
                sidebarRow(.websites)
            }

            Section("Tools") {
                sidebarRow(.profiles)
                sidebarRow(.snippets)
            }

            Section {
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LayoutPilot")
        .frame(minWidth: 190)
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}
