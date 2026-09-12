import SwiftUI

struct LayerPanelView: View {
    @EnvironmentObject private var gathering: GatheringStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Gathering") {
                    ForEach(GatheringCategory.allCases) { category in
                        Toggle(isOn: membership(category, in: $gathering.categories)) {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                }
                Section("Spawn reliability") {
                    ForEach(GatheringReliability.allCases) { reliability in
                        Toggle(reliability.title, isOn: membership(reliability, in: $gathering.reliabilities))
                    }
                    Toggle("Hide visited", isOn: $gathering.hideVisited)
                }
                Section {
                    Button("Reset visited nodes", role: .destructive) { gathering.resetVisited() }
                } footer: {
                    Text("Sample locations demonstrate the feature and are not verified active spawns. Visited does not mean harvested.")
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
