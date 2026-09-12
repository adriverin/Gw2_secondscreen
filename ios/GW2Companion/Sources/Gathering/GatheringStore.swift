import Foundation

@MainActor
final class GatheringStore: ObservableObject {
    @Published private(set) var nodes: [GatheringNode] = []
    @Published private(set) var visited: Set<String> = []
    @Published var categories: Set<GatheringCategory> { didSet { persistFilters() } }
    @Published var reliabilities: Set<GatheringReliability> { didSet { persistFilters() } }
    @Published var hideVisited = false
    var visitRadius = 45.0

    private let provider: MarkerDataProvider
    private let defaults: UserDefaults

    init(provider: MarkerDataProvider = BundledGatheringProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        let savedCategories = defaults.stringArray(forKey: "visibleGatheringCategories")?.compactMap(GatheringCategory.init(rawValue:))
        let savedReliabilities = defaults.stringArray(forKey: "visibleGatheringReliabilities")?.compactMap(GatheringReliability.init(rawValue:))
        categories = Set(savedCategories?.isEmpty == false ? savedCategories! : GatheringCategory.allCases)
        reliabilities = Set(savedReliabilities?.isEmpty == false ? savedReliabilities! : GatheringReliability.allCases)
    }

    var visibleNodes: [GatheringNode] {
        nodes.filter { categories.contains($0.category) && reliabilities.contains($0.reliability) && (!hideVisited || !visited.contains($0.id)) }
    }

    func load(mapId: Int) async {
        nodes = (try? await provider.markers(for: mapId)) ?? []
        visited = visited.intersection(Set(nodes.map(\.id)))
    }

    func updatePlayer(_ point: ContinentPoint) {
        visited.formUnion(GatheringGeometry.nodesWithin(radius: visitRadius, of: point, among: nodes))
    }

    func toggleVisited(_ id: String) {
        if visited.contains(id) { visited.remove(id) } else { visited.insert(id) }
    }

    func resetVisited() { visited.removeAll() }

    private func persistFilters() {
        defaults.set(categories.map(\.rawValue), forKey: "visibleGatheringCategories")
        defaults.set(reliabilities.map(\.rawValue), forKey: "visibleGatheringReliabilities")
    }
}
