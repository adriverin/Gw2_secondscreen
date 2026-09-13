import Foundation

@MainActor
final class GatheringStore: ObservableObject {
    enum Availability: Equatable { case idle, loading, available(Int), unavailable, failed }

    @Published private(set) var nodes: [GatheringNode] = []
    @Published private(set) var visibleNodes: [GatheringNode] = []
    @Published private(set) var visited: Set<String> = []
    @Published private(set) var harvested: Set<String>
    @Published private(set) var nearestVisibleNode: GatheringNode?
    @Published private(set) var sceneRevision = 0
    @Published private(set) var availability: Availability = .idle
    @Published private(set) var coveredMapIDs: Set<Int> = []
    @Published var categories: Set<GatheringCategory> { didSet { filtersChanged() } }
    @Published var reliabilities: Set<GatheringReliability> { didSet { filtersChanged() } }
    @Published var hideHarvested: Bool { didSet { filtersChanged() } }
    var visitRadius = 45.0

    private let provider: MarkerDataProvider
    private let sampleProvider: MarkerDataProvider
    private let defaults: UserDefaults
    private var requestedMapId: Int?
    private var lastPlayer: ContinentPoint?

    init(provider: MarkerDataProvider = BundledGatheringProvider(),
         sampleProvider: MarkerDataProvider = BundledSampleGatheringProvider(),
         defaults: UserDefaults = .standard) {
        self.provider = provider
        self.sampleProvider = sampleProvider
        self.defaults = defaults
        let savedCategories = defaults.stringArray(forKey: "visibleGatheringCategories")?.compactMap(GatheringCategory.init(rawValue:))
        let savedReliabilities = defaults.stringArray(forKey: "visibleGatheringReliabilities")?.compactMap(GatheringReliability.init(rawValue:))
        categories = defaults.object(forKey: "visibleGatheringCategories") == nil ? Set(GatheringCategory.allCases) : Set(savedCategories ?? [])
        reliabilities = defaults.object(forKey: "visibleGatheringReliabilities") == nil ? Set(GatheringReliability.allCases) : Set(savedReliabilities ?? [])
        hideHarvested = defaults.bool(forKey: "hideHarvestedGatheringNodes")
        harvested = Set(defaults.stringArray(forKey: "harvestedGatheringNodes") ?? [])
    }

    func load(mapId: Int, metadata: GW2MapMetadata, simulation: Bool) async {
        requestedMapId = mapId
        availability = .loading
        let selectedProvider = simulation ? sampleProvider : provider
        do {
            let covered = try await selectedProvider.coveredMapIDs()
            guard requestedMapId == mapId else { return }
            coveredMapIDs = covered
            guard covered.contains(mapId) else {
                nodes = []
                visited = []
                refreshVisibleNodes()
                availability = .unavailable
                return
            }
            let loaded = try await selectedProvider.markers(for: mapId, metadata: metadata)
            guard requestedMapId == mapId else { return }
            nodes = loaded
            refreshVisibleNodes()
            availability = .available(nodes.count)
        } catch {
            guard requestedMapId == mapId else { return }
            nodes = []
            refreshVisibleNodes()
            availability = .failed
        }
        let currentVisited = visited.intersection(Set(nodes.map(\.id)))
        if currentVisited != visited { visited = currentVisited }
        updateNearest()
    }

    func updatePlayer(_ point: ContinentPoint) {
        lastPlayer = point
        let nearby = GatheringGeometry.nodesWithin(radius: visitRadius, of: point, among: nodes)
        let updated = visited.union(nearby)
        if updated != visited { visited = updated }
        updateNearest()
    }

    func toggleHarvested(_ id: String) {
        if harvested.contains(id) { harvested.remove(id) } else { harvested.insert(id) }
        defaults.set(harvested.sorted(), forKey: "harvestedGatheringNodes")
        if hideHarvested { refreshVisibleNodes() } else { updateNearest() }
    }

    func resetHarvested() {
        harvested.removeAll()
        defaults.set([], forKey: "harvestedGatheringNodes")
        if hideHarvested { refreshVisibleNodes() } else { updateNearest() }
    }

    func clear() {
        requestedMapId = nil
        nodes = []
        visited = []
        lastPlayer = nil
        refreshVisibleNodes()
        coveredMapIDs = []
        availability = .idle
    }

    private func filtersChanged() {
        persistFilters()
        refreshVisibleNodes()
    }

    private func refreshVisibleNodes() {
        let filtered = nodes.filter {
            categories.contains($0.category) && reliabilities.contains($0.reliability) &&
                (!hideHarvested || !harvested.contains($0.id))
        }
        if filtered != visibleNodes {
            visibleNodes = filtered
            sceneRevision &+= 1
        }
        updateNearest()
    }

    private func updateNearest() {
        let nearest = lastPlayer.flatMap { player in
            GatheringGeometry.nearest(
                to: player,
                among: visibleNodes.filter { !harvested.contains($0.id) })
        }
        if nearestVisibleNode != nearest { nearestVisibleNode = nearest }
    }

    private func persistFilters() {
        defaults.set(categories.map(\.rawValue), forKey: "visibleGatheringCategories")
        defaults.set(reliabilities.map(\.rawValue), forKey: "visibleGatheringReliabilities")
        defaults.set(hideHarvested, forKey: "hideHarvestedGatheringNodes")
    }
}
