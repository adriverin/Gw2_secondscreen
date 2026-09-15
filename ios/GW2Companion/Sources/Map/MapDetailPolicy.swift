import CoreGraphics
import Foundation

struct MapMarkerAppearance: Equatable, Sendable {
    var visible: Bool
    var size: CGFloat
    var showLabel: Bool
    var important: Bool

    static let hidden = MapMarkerAppearance(visible: false, size: 0, showLabel: false, important: false)
}

struct MapDetailViewportCounts: Equatable, Sendable {
    var visiblePOIs: Int
    var visibleWaypoints: Int
    var visibleVistas: Int
    var visibleHeroChallenges: Int
    var visibleGathering: Int
    var visibleLabels: Int
    var sourceTileZoom: Int
    var displayZoom: Int

    var totalVisible: Int {
        visiblePOIs + visibleWaypoints + visibleVistas + visibleHeroChallenges + visibleGathering
    }

    func diagnosticsText(mode: MapDetailMode) -> String {
        """
        \(mode.title.uppercased())
        visible POIs \(visiblePOIs)
        visible waypoints \(visibleWaypoints)
        visible vistas \(visibleVistas)
        visible hero challenges \(visibleHeroChallenges)
        visible gathering markers \(visibleGathering)
        labels \(visibleLabels)
        display zoom \(displayZoom)
        source artwork zoom \(sourceTileZoom)
        """
    }
}

enum MapDetailPolicy {
    static func appearance(
        for objective: MapObjective,
        mode: MapDetailMode,
        displayZoom: Int,
        targetID: MapObjectiveID?,
        routeIDs: Set<MapObjectiveID> = []
    ) -> MapMarkerAppearance {
        let important = objective.id == targetID || routeIDs.contains(objective.id)
        if important {
            return MapMarkerAppearance(
                visible: true, size: displayZoom >= 6 ? 34 : 26, showLabel: true, important: true)
        }
        let minimum = minVisibleZoom(for: objective.type, mode: mode)
        guard displayZoom >= minimum else { return .hidden }
        let size = markerSize(for: objective.type, mode: mode, displayZoom: displayZoom)
        let label = shouldShowLabel(for: objective.type, mode: mode, displayZoom: displayZoom)
        return MapMarkerAppearance(visible: true, size: size, showLabel: label, important: false)
    }

    static func minVisibleZoom(for type: MapObjectiveType, mode: MapDetailMode) -> Int {
        switch type {
        case .waypoint, .masteryInsight:
            return 2
        case .heroChallenge, .vista, .renownHeart:
            return mode == .detailed ? 4 : 6
        case .landmark, .adventure:
            return mode == .detailed ? 5 : 7
        case .gatheringOre, .gatheringWood, .gatheringPlant:
            return mode == .detailed ? 5 : 7
        case .custom:
            return mode == .detailed ? 4 : 6
        }
    }

    static func markerSize(for type: MapObjectiveType, mode: MapDetailMode, displayZoom: Int) -> CGFloat {
        if displayZoom >= 7 { return mode == .detailed ? 31 : 28 }
        if displayZoom >= 6 { return mode == .detailed ? 26 : 22 }
        if displayZoom >= 5 { return 18 }
        return 14
    }

    static func shouldShowLabel(for type: MapObjectiveType, mode: MapDetailMode, displayZoom: Int) -> Bool {
        guard mode == .detailed, displayZoom >= 5 else { return false }
        switch type {
        case .waypoint, .heroChallenge, .vista, .masteryInsight:
            return displayZoom >= 6
        default:
            return false
        }
    }

    static func counts(
        objectives: [MapObjective],
        mode: MapDetailMode,
        displayZoom: Int,
        sourceTileZoom: Int,
        targetID: MapObjectiveID? = nil,
        routeIDs: Set<MapObjectiveID> = []
    ) -> MapDetailViewportCounts {
        var counts = MapDetailViewportCounts(
            visiblePOIs: 0, visibleWaypoints: 0, visibleVistas: 0, visibleHeroChallenges: 0,
            visibleGathering: 0, visibleLabels: 0, sourceTileZoom: sourceTileZoom, displayZoom: displayZoom)
        for objective in objectives {
            let appearance = appearance(
                for: objective, mode: mode, displayZoom: displayZoom, targetID: targetID, routeIDs: routeIDs)
            guard appearance.visible else { continue }
            if appearance.showLabel { counts.visibleLabels += 1 }
            switch objective.type {
            case .landmark: counts.visiblePOIs += 1
            case .waypoint: counts.visibleWaypoints += 1
            case .vista: counts.visibleVistas += 1
            case .heroChallenge: counts.visibleHeroChallenges += 1
            case .gatheringOre, .gatheringWood, .gatheringPlant: counts.visibleGathering += 1
            default: break
            }
        }
        return counts
    }

    static func comparison(
        objectives: [MapObjective],
        displayZoom: Int,
        balancedSourceZoom: Int,
        detailedSourceZoom: Int,
        targetID: MapObjectiveID? = nil,
        routeIDs: Set<MapObjectiveID> = []
    ) -> (balanced: MapDetailViewportCounts, detailed: MapDetailViewportCounts) {
        (
            counts(
                objectives: objectives, mode: .balanced, displayZoom: displayZoom,
                sourceTileZoom: balancedSourceZoom, targetID: targetID, routeIDs: routeIDs),
            counts(
                objectives: objectives, mode: .detailed, displayZoom: displayZoom,
                sourceTileZoom: detailedSourceZoom, targetID: targetID, routeIDs: routeIDs)
        )
    }
}
