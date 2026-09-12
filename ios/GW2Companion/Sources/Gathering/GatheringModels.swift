import Foundation

enum GatheringCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case ore, wood, plant, other
    var id: Self { self }
    var title: String { self == .plant ? "Plants" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .ore: "diamond.fill"
        case .wood: "tree.fill"
        case .plant: "leaf.fill"
        case .other: "mappin"
        }
    }
}

enum GatheringReliability: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed, likely, possible
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct GatheringNode: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let mapId: Int
    let continentX: Double
    let continentY: Double
    let category: GatheringCategory
    let name: String
    let reliability: GatheringReliability
    let source: String?
    let notes: String?
}

protocol MarkerDataProvider: Sendable {
    func markers(for mapId: Int, metadata: GW2MapMetadata) async throws -> [GatheringNode]
    func coveredMapIDs() async throws -> Set<Int>
}

struct BundledGatheringProvider: MarkerDataProvider {
    let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }

    func markers(for mapId: Int, metadata: GW2MapMetadata) async throws -> [GatheringNode] {
        let dataset = try load()
        let transformer = GW2CoordinateTransformer(metadata: metadata)
        return try dataset.markers.filter { $0.mapId == mapId }.map { marker in
            let coordinate = try transformer.continentPoint(worldX: marker.worldX, worldZ: marker.worldZ)
            return GatheringNode(
                id: marker.id, mapId: marker.mapId, continentX: coordinate.x, continentY: coordinate.y,
                category: marker.category, name: marker.name, reliability: marker.reliability,
                source: marker.source, notes: marker.notes)
        }
    }

    func coveredMapIDs() async throws -> Set<Int> { Set(try load().coveredMapIds) }

    private func load() throws -> BundledGatheringDataset {
        guard let url = bundle.url(forResource: "tyrian-gathering-v1", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(BundledGatheringDataset.self, from: Data(contentsOf: url))
    }
}

struct BundledSampleGatheringProvider: MarkerDataProvider {
    let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }

    func markers(for mapId: Int, metadata: GW2MapMetadata) async throws -> [GatheringNode] {
        guard let url = bundle.url(forResource: "sample-gathering-nodes", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([GatheringNode].self, from: Data(contentsOf: url)).filter { $0.mapId == mapId }
    }

    func coveredMapIDs() async throws -> Set<Int> { [15, 50] }
}

private struct BundledGatheringDataset: Codable {
    let version: Int
    let sourceURL: String
    let sourceRevision: String
    let license: String
    let coveredMapIds: [Int]
    let markers: [BundledWorldGatheringMarker]
}

private struct BundledWorldGatheringMarker: Codable {
    let id: String
    let mapId: Int
    let worldX: Double
    let worldZ: Double
    let category: GatheringCategory
    let name: String
    let reliability: GatheringReliability
    let source: String?
    let notes: String?
}

enum CompassDirection: String, Sendable {
    case n = "N", ne = "NE", e = "E", se = "SE", s = "S", sw = "SW", w = "W", nw = "NW"
}

enum GatheringGeometry {
    static func nearest(to player: ContinentPoint, among nodes: [GatheringNode]) -> GatheringNode? {
        nodes.min { squaredDistance(player, $0) < squaredDistance(player, $1) }
    }

    static func nodesWithin(radius: Double, of player: ContinentPoint, among nodes: [GatheringNode]) -> Set<String> {
        Set(nodes.filter { squaredDistance(player, $0) <= radius * radius }.map(\.id))
    }

    static func direction(from player: ContinentPoint, to node: GatheringNode) -> CompassDirection {
        let angle = atan2(node.continentY - player.y, node.continentX - player.x)
        let octant = Int(round(angle / (.pi / 4)))
        switch (octant + 8) % 8 {
        case 0: return .e
        case 1: return .se
        case 2: return .s
        case 3: return .sw
        case 4: return .w
        case 5: return .nw
        case 6: return .n
        default: return .ne
        }
    }

    private static func squaredDistance(_ player: ContinentPoint, _ node: GatheringNode) -> Double {
        pow(node.continentX - player.x, 2) + pow(node.continentY - player.y, 2)
    }
}
