import Foundation

struct MapObjectiveID: RawRepresentable, Codable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    let rawValue: String
    var id: String { rawValue }
    var description: String { rawValue }

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

enum MapObjectiveType: String, Codable, CaseIterable, Identifiable, Sendable {
    case waypoint
    case vista
    case landmark
    case renownHeart
    case heroChallenge
    case masteryInsight
    case adventure
    case gatheringOre
    case gatheringWood
    case gatheringPlant
    case custom

    var id: Self { self }
    var isGathering: Bool { [.gatheringOre, .gatheringWood, .gatheringPlant].contains(self) }
    var isWorld: Bool { !isGathering && self != .custom }

    var title: String {
        switch self {
        case .waypoint: "Waypoint"
        case .vista: "Vista"
        case .landmark: "Point of Interest"
        case .renownHeart: "Renown Heart"
        case .heroChallenge: "Hero Challenge"
        case .masteryInsight: "Mastery Insight"
        case .adventure: "Adventure"
        case .gatheringOre: "Ore"
        case .gatheringWood: "Wood"
        case .gatheringPlant: "Plant"
        case .custom: "Custom Marker"
        }
    }

    var pluralTitle: String {
        switch self {
        case .landmark: "Points of Interest"
        case .renownHeart: "Renown Hearts"
        case .heroChallenge: "Hero Challenges"
        case .masteryInsight: "Mastery Insights"
        case .gatheringOre: "Ore"
        case .gatheringWood: "Wood"
        case .gatheringPlant: "Plants"
        default: title + "s"
        }
    }

    var symbol: String {
        switch self {
        case .waypoint: "diamond.circle.fill"
        case .vista: "binoculars.fill"
        case .landmark: "mappin.circle.fill"
        case .renownHeart: "heart.fill"
        case .heroChallenge: "figure.strengthtraining.traditional"
        case .masteryInsight: "sparkles"
        case .adventure: "flag.checkered"
        case .gatheringOre: "diamond.fill"
        case .gatheringWood: "tree.fill"
        case .gatheringPlant: "leaf.fill"
        case .custom: "star.fill"
        }
    }

    var officialIconURL: URL? {
        let value: String? = switch self {
        case .waypoint: "https://render.guildwars2.com/file/32633AF8ADEA696A1EF56D3AE32D617B10D3AC57/157353.png"
        case .landmark: "https://render.guildwars2.com/file/25B230711176AB5728E86F5FC5F0BFAE48B32F6E/97461.png"
        case .vista: "https://render.guildwars2.com/file/A2C16AF497BA3A0903A0499FFBAF531477566F10/358415.png"
        case .renownHeart: "https://render.guildwars2.com/file/09ACBA53B7412CC3C76E7FEF39929843C20CB0E4/102440.png"
        case .heroChallenge: "https://render.guildwars2.com/file/B4EC6BB3FDBC42557C3CAE0CAA9E57EBF9E462E3/156626.png"
        case .gatheringOre: "https://render.guildwars2.com/file/A89EB66C39C7C006A4A6CBEDA28061F16847E9BC/157334.png"
        case .gatheringWood: "https://render.guildwars2.com/file/FC01BB452D5327A0E5B2E4A3F5EFDF03F8264A7B/157333.png"
        case .gatheringPlant: "https://render.guildwars2.com/file/995534EBE5D26804AE605E205E50539821C0CBCB/157332.png"
        case .masteryInsight, .adventure, .custom: nil
        }
        return value.flatMap(URL.init(string:))
    }

    var arrivalRadius: Double {
        switch self {
        case .waypoint, .vista, .landmark, .renownHeart: 45
        case .heroChallenge, .masteryInsight, .adventure: 55
        case .gatheringOre, .gatheringWood, .gatheringPlant: 35
        case .custom: 40
        }
    }
}

enum MapObjectiveSource: String, Codable, Sendable {
    case arenaNet
    case bundledGathering
    case user
}

/// Local companion state. None of these values claim official in-game completion.
enum MapObjectiveState: String, Codable, Sendable {
    case unknown
    case visited
    case manuallyCompleted
    case skipped

    var label: String {
        switch self {
        case .unknown: "Not visited by Companion"
        case .visited: "Visited by Companion"
        case .manuallyCompleted: "Marked complete"
        case .skipped: "Skipped"
        }
    }
}

struct MapObjective: Identifiable, Codable, Hashable, Sendable {
    let id: MapObjectiveID
    let mapId: Int
    let name: String
    let type: MapObjectiveType
    let continentX: Double
    let continentY: Double
    let source: MapObjectiveSource
    let chatLink: String?
    let level: Int?
    let description: String?
    var state: MapObjectiveState

    var coordinate: ContinentPoint { ContinentPoint(x: continentX, y: continentY) }

    func withState(_ state: MapObjectiveState) -> Self {
        var copy = self
        copy.state = state
        return copy
    }
}

extension GatheringNode {
    var mapObjective: MapObjective {
        let type: MapObjectiveType = switch category {
        case .ore: .gatheringOre
        case .wood: .gatheringWood
        case .plant: .gatheringPlant
        case .other: .custom
        }
        return MapObjective(
            id: MapObjectiveID("gathering:\(id)"), mapId: mapId, name: name, type: type,
            continentX: continentX, continentY: continentY, source: .bundledGathering,
            chatLink: nil, level: nil, description: notes, state: .unknown)
    }
}

enum ObjectiveFilterPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case explore, gather, heroPoints, mastery, everything
    var id: Self { self }
    var title: String {
        switch self {
        case .explore: "Explore"
        case .gather: "Gather"
        case .heroPoints: "Hero Points"
        case .mastery: "Mastery"
        case .everything: "Everything"
        }
    }
    var types: Set<MapObjectiveType> {
        switch self {
        case .explore: [.waypoint, .vista, .landmark, .heroChallenge]
        case .gather: [.gatheringOre, .gatheringWood, .gatheringPlant]
        case .heroPoints: [.heroChallenge]
        case .mastery: [.masteryInsight]
        case .everything: Set(MapObjectiveType.allCases)
        }
    }
}
