import SwiftUI

struct LayerPanelView: View {
    @EnvironmentObject private var gathering: GatheringStore
    @EnvironmentObject private var overlays: MapOverlayStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Map landmarks") {
                    ForEach(MapLandmarkKind.allCases) { kind in
                        Toggle(isOn: membership(kind, in: $overlays.visibleKinds)) {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                    switch overlays.state {
                    case .loading: Label("Loading landmarks", systemImage: "arrow.triangle.2.circlepath")
                    case .loaded: Text("\(overlays.landmarks.count) landmarks on this map").foregroundStyle(.secondary)
                    case .unavailable: Text("Landmarks are currently unavailable.").foregroundStyle(.secondary)
                    case .idle: EmptyView()
                    }
                }
                Section("Gathering") {
                    ForEach(GatheringCategory.allCases) { category in
                        Toggle(isOn: membership(category, in: $gathering.categories)) {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                    switch gathering.availability {
                    case .available(let count): Text("\(count) possible locations here; snapshot coverage: \(gathering.coveredMapIDs.count) maps.").foregroundStyle(.secondary)
                    case .unavailable: Text("This map is outside the snapshot's \(gathering.coveredMapIDs.count)-map coverage.").foregroundStyle(.secondary)
                    case .failed: Text("Gathering data could not be loaded.").foregroundStyle(.secondary)
                    case .idle, .loading: EmptyView()
                    }
                }
                Section("Spawn reliability") {
                    ForEach(GatheringReliability.allCases) { reliability in
                        Toggle(reliability.title, isOn: membership(reliability, in: $gathering.reliabilities))
                    }
                    Toggle("Hide marked harvested", isOn: $gathering.hideHarvested)
                }
                Section {
                    Button("Reset harvested markers", role: .destructive) { gathering.resetHarvested() }
                } footer: {
                    Text("Gathering markers are possible spawn locations from a CC0 community snapshot. A yellow outline means you came near one; tapping it marks it harvested.")
                }
            }
            .navigationTitle("Layers")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func membership<Element: Hashable>(_ element: Element, in set: Binding<Set<Element>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(element) },
            set: { enabled in
                if enabled { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
            })
    }
}
