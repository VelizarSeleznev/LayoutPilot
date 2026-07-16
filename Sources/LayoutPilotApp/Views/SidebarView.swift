import LayoutPilotCore
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection
    let addedModules: Set<FeatureModule>

    var body: some View {
        List(selection: $selection) {
            sidebarRow(.overview)

            if addedModules.contains(.snippets) {
                Section("Writing") {
                    sidebarRow(.snippets)
                }
            }

            if addedModules.contains(.smartDanish) || addedModules.contains(.smartBilingual) {
                Section("Smart Input") {
                    if addedModules.contains(.smartDanish) {
                        sidebarRow(.smartDanish)
                    }
                    if addedModules.contains(.smartBilingual) {
                        sidebarRow(.smartBilingual)
                    }
                }
            }

            if addedModules.contains(.layoutSwitching) {
                Section("Layout Switching") {
                    sidebarRow(.rules)
                    sidebarRow(.websites)
                    sidebarRow(.profiles)
                }
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
