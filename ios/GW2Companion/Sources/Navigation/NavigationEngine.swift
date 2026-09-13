import Foundation

enum CardinalDirection: String, Codable, CaseIterable, Sendable {
    case n = "N", ne = "NE", e = "E", se = "SE", s = "S", sw = "SW", w = "W", nw = "NW"
}

enum ObjectiveDistanceEngine {
    static func distance(from: ContinentPoint, to: ContinentPoint) -> Double {
        hypot(to.x - from.x, to.y - from.y)
    }

    /// Clockwise degrees from map north. Continent Y grows toward screen south.
    static func bearing(from: ContinentPoint, to: ContinentPoint) -> Double {
        let degrees = atan2(to.x - from.x, from.y - to.y) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    static func cardinalDirection(from: ContinentPoint, to: ContinentPoint) -> CardinalDirection {
        let index = Int((bearing(from: from, to: to) + 22.5) / 45) % 8
        return [.n, .ne, .e, .se, .s, .sw, .w, .nw][index]
    }

    static func relativeAngle(targetBearing: Double, playerHeadingRadians: Double) -> Double {
        let heading = playerHeadingRadians * 180 / .pi
        return (targetBearing - heading + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

struct NearbyObjective: Identifiable, Equatable, Sendable {
    let objective: MapObjective
    let distance: Double
    let direction: CardinalDirection
    var id: MapObjectiveID { objective.id }
}

struct ObjectiveProximityResult: Equatable, Sendable {
    let nearby: [NearbyObjective]
    let newlyVisited: Set<MapObjectiveID>
    let targetReached: Bool
}

/// Throttles repeated telemetry sorting while still allowing movement-triggered updates.
final class ObjectiveProximityEngine: @unchecked Sendable {
    private var lastEvaluation: Date?
    private var lastPosition: ContinentPoint?
    private var targetsInsideRadius: Set<MapObjectiveID> = []
    var minimumInterval: TimeInterval
    var minimumMovement: Double

    init(minimumInterval: TimeInterval = 0.25, minimumMovement: Double = 4) {
        self.minimumInterval = minimumInterval
        self.minimumMovement = minimumMovement
    }

    func evaluate(
        player: ContinentPoint,
        objectives: [MapObjective],
        targetID: MapObjectiveID?,
        now: Date = Date(),
        force: Bool = false,
        nearbyLimit: Int = 20
    ) -> ObjectiveProximityResult? {
        if !force, let lastEvaluation, let lastPosition,
           now.timeIntervalSince(lastEvaluation) < minimumInterval,
           ObjectiveDistanceEngine.distance(from: lastPosition, to: player) < minimumMovement {
            return nil
        }
        lastEvaluation = now
        lastPosition = player

        let measured = objectives.map {
            NearbyObjective(
                objective: $0,
                distance: ObjectiveDistanceEngine.distance(from: player, to: $0.coordinate),
                direction: ObjectiveDistanceEngine.cardinalDirection(from: player, to: $0.coordinate))
        }.sorted {
            if abs($0.distance - $1.distance) > 0.000_001 { return $0.distance < $1.distance }
            return $0.id.rawValue < $1.id.rawValue
        }

        let inside = Set(measured.filter { $0.distance <= $0.objective.type.arrivalRadius }.map(\.id))
        let newlyVisited = inside.subtracting(targetsInsideRadius)
        let targetReached = targetID.map(newlyVisited.contains) ?? false
        targetsInsideRadius = inside
        return ObjectiveProximityResult(
            nearby: Array(measured.prefix(nearbyLimit)), newlyVisited: newlyVisited,
            targetReached: targetReached)
    }

    func reset() {
        lastEvaluation = nil
        lastPosition = nil
        targetsInsideRadius = []
    }
}

struct NavigationRoute: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var objectives: [MapObjectiveID]
    var currentIndex: Int
    var startedAt: Date?
    var finishedAt: Date?

    init(id: UUID = UUID(), name: String, objectives: [MapObjectiveID], currentIndex: Int = 0,
         startedAt: Date? = nil, finishedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.objectives = objectives
        self.currentIndex = currentIndex
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var currentObjectiveID: MapObjectiveID? {
        objectives.indices.contains(currentIndex) ? objectives[currentIndex] : nil
    }
}

enum RouteGenerator {
    static func nearestNeighbor(from start: ContinentPoint, objectives: [MapObjective]) -> [MapObjectiveID] {
        var remaining = objectives
        var point = start
        var result: [MapObjectiveID] = []
        while !remaining.isEmpty {
            let index = remaining.indices.min { lhs, rhs in
                let ld = ObjectiveDistanceEngine.distance(from: point, to: remaining[lhs].coordinate)
                let rd = ObjectiveDistanceEngine.distance(from: point, to: remaining[rhs].coordinate)
                if abs(ld - rd) > 0.000_001 { return ld < rd }
                return remaining[lhs].id.rawValue < remaining[rhs].id.rawValue
            }!
            let next = remaining.remove(at: index)
            result.append(next.id)
            point = next.coordinate
        }
        return result
    }
}
