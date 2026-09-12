import Foundation

enum MapLandmarkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case waypoint
    case pointOfInterest
    case vista
    case heart
    case heroChallenge

    var id: Self { self }
    var title: String {
        switch self {
        case .waypoint: "Waypoints"
        case .pointOfInterest: "Points of interest"
        case .vista: "Vistas"
        case .heart: "Renown hearts"
        case .heroChallenge: "Hero challenges"
        }
    }
    var symbol: String {
        switch self {
        case .waypoint: "diamond.circle.fill"
        case .pointOfInterest: "mappin.circle.fill"
        case .vista: "binoculars.fill"
        case .heart: "heart.fill"
        case .heroChallenge: "figure.strengthtraining.traditional"
        }
    }

    var officialIconURL: URL {
        let value = switch self {
        case .waypoint: "https://render.guildwars2.com/file/32633AF8ADEA696A1EF56D3AE32D617B10D3AC57/157353.png"
        case .pointOfInterest: "https://render.guildwars2.com/file/25B230711176AB5728E86F5FC5F0BFAE48B32F6E/97461.png"
        case .vista: "https://render.guildwars2.com/file/A2C16AF497BA3A0903A0499FFBAF531477566F10/358415.png"
        case .heart: "https://render.guildwars2.com/file/09ACBA53B7412CC3C76E7FEF39929843C20CB0E4/102440.png"
        case .heroChallenge: "https://render.guildwars2.com/file/B4EC6BB3FDBC42557C3CAE0CAA9E57EBF9E462E3/156626.png"
        }
        return URL(string: value)!
    }
}

struct MapLandmark: Identifiable, Equatable, Sendable {
    let id: String
    let kind: MapLandmarkKind
    let name: String
    let coordinate: ContinentPoint
    let chatLink: String?
}

protocol MapLandmarkDataProvider: Sendable {
    func landmarks(continentId: Int, floor: Int, mapId: Int) async throws -> [MapLandmark]
}

struct GW2FloorMetadata: Codable, Sendable {
    let regions: [String: GW2FloorRegion]
}

struct GW2FloorRegion: Codable, Sendable {
    let maps: [String: GW2FloorMap]
}

struct GW2FloorMap: Codable, Sendable {
    let id: Int
    let pointsOfInterest: [String: GW2FloorPointOfInterest]?
    let tasks: [String: GW2FloorTask]?
    let skillChallenges: [GW2FloorSkillChallenge]?

    enum CodingKeys: String, CodingKey {
        case id, tasks
        case pointsOfInterest = "points_of_interest"
        case skillChallenges = "skill_challenges"
    }

    func landmarks() -> [MapLandmark] {
        var result: [MapLandmark] = []
        for point in pointsOfInterest?.values ?? Dictionary<String, GW2FloorPointOfInterest>().values {
            guard point.coord.count == 2 else { continue }
            let kind: MapLandmarkKind
            switch point.type {
            case "waypoint": kind = .waypoint
            case "vista": kind = .vista
            default: kind = .pointOfInterest
            }
            let fallback = kind == .vista ? "Vista" : "Point of interest"
            result.append(MapLandmark(
                id: "poi-\(point.id)", kind: kind, name: point.name?.nonEmpty ?? fallback,
                coordinate: ContinentPoint(x: point.coord[0], y: point.coord[1]), chatLink: point.chatLink))
        }
        for task in tasks?.values ?? Dictionary<String, GW2FloorTask>().values where task.coord.count == 2 {
            result.append(MapLandmark(
                id: "task-\(task.id)", kind: .heart, name: task.objective,
                coordinate: ContinentPoint(x: task.coord[0], y: task.coord[1]), chatLink: task.chatLink))
        }
        for challenge in skillChallenges ?? [] where challenge.coord.count == 2 {
            let identifier = challenge.id ?? "\(challenge.coord[0])-\(challenge.coord[1])"
            result.append(MapLandmark(
                id: "hero-\(identifier)", kind: .heroChallenge, name: "Hero challenge",
                coordinate: ContinentPoint(x: challenge.coord[0], y: challenge.coord[1]), chatLink: nil))
        }
        return result.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }
}

struct GW2FloorPointOfInterest: Codable, Sendable {
    let name: String?
    let type: String
    let coord: [Double]
    let id: Int
    let chatLink: String?

    enum CodingKeys: String, CodingKey {
        case name, type, coord, id
        case chatLink = "chat_link"
    }
}

struct GW2FloorTask: Codable, Sendable {
    let objective: String
    let coord: [Double]
    let id: Int
    let chatLink: String?

    enum CodingKeys: String, CodingKey {
        case objective, coord, id
        case chatLink = "chat_link"
    }
}

struct GW2FloorSkillChallenge: Codable, Sendable {
    let coord: [Double]
    let id: String?
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

enum MapOverlayLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unavailable(String)
}

@MainActor
final class MapOverlayStore: ObservableObject {
    @Published private(set) var landmarks: [MapLandmark] = []
    @Published private(set) var state: MapOverlayLoadState = .idle
    @Published var visibleKinds: Set<MapLandmarkKind> { didSet { persistKinds() } }

    private let defaults: UserDefaults
    private var requestedMapId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: "visibleMapLandmarkKinds") != nil {
            visibleKinds = Set((defaults.stringArray(forKey: "visibleMapLandmarkKinds") ?? []).compactMap(MapLandmarkKind.init(rawValue:)))
        } else {
            visibleKinds = Set(MapLandmarkKind.allCases)
        }
    }

    var visibleLandmarks: [MapLandmark] { landmarks.filter { visibleKinds.contains($0.kind) } }

    func load(provider: any MapLandmarkDataProvider, metadata: GW2MapMetadata) async {
        requestedMapId = metadata.id
        state = .loading
        do {
            let loaded = try await provider.landmarks(
                continentId: metadata.continentId, floor: metadata.defaultFloor, mapId: metadata.id)
            guard requestedMapId == metadata.id else { return }
            landmarks = loaded
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestedMapId == metadata.id else { return }
            landmarks = []
            state = .unavailable(error.localizedDescription)
        }
    }

    func clear() {
        requestedMapId = nil
        landmarks = []
        state = .idle
    }

    private func persistKinds() {
        defaults.set(visibleKinds.map(\.rawValue).sorted(), forKey: "visibleMapLandmarkKinds")
    }
}
