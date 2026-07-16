import LayoutPilotCore
import SwiftUI

struct OverviewView: View {
    @Bindable var appState: LayoutPilotAppState

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !appState.store.configuration.moduleSelectionCompleted {
                    firstRunBanner
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(FeatureModule.allCases) { module in
                        ModuleCard(
                            module: module,
                            isAdded: appState.store.configuration.isModuleAdded(module)
                        ) {
                            appState.store.setModuleAdded(
                                module,
                                isAdded: !appState.store.configuration.isModuleAdded(module)
                            )
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("My Modules")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appState.store.configuration.moduleSelectionCompleted ? "MY MODULES" : "WELCOME TO LAYOUTPILOT")
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text(appState.store.configuration.moduleSelectionCompleted ? "Make LayoutPilot yours" : "What should LayoutPilot help with?")
                .font(.largeTitle.weight(.semibold))
            Text("Add only the tools you need. You can change this selection at any time.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var firstRunBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Choose any combination")
                    .font(.headline)
                Text("Nothing is forced on. Start with one module or build your complete setup.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Continue") {
                appState.store.completeModuleSelection()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ModuleCard: View {
    let module: FeatureModule
    let isAdded: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: module.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isAdded ? Color.white : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(isAdded ? Color.accentColor : Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                Label(isAdded ? "Added" : "Not added", systemImage: isAdded ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isAdded ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(module.title)
                    .font(.title2.weight(.semibold))
                Text(module.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAdded {
                Button("Remove Module", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            } else {
                Button("Add Module", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isAdded ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.09), lineWidth: 1)
        }
    }
}
