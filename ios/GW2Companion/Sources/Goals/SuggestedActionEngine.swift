import Foundation

struct SuggestedActionContext: Sendable {
    let currentMapID: Int?
    let playerPosition: ContinentPoint?
    let mapObjectives: [MapObjective]
    let prices: [Int: TimedCommercePrice]
    let itemNames: [Int: String]
    var craftableItemIDs: Set<Int> = []
}

enum SuggestedActionEngine {
    /// Explicit score components. Scores rank convenience, not optimal gameplay:
    /// same map +100, navigable +80, high/normal/low priority +50/+25/+0,
    /// proximity +0...30, ready craft +40, market listing +20, inspect +5.
    static func actions(
        for goal: PlayerGoal, craftingPlan: CraftingPlan? = nil,
        achievement: AchievementTrackingState? = nil,
        context: SuggestedActionContext
    ) -> [SuggestedAction] {
        let priority = switch goal.priority { case .high: 50; case .normal: 25; case .low: 0 }
        var actions: [SuggestedAction] = []

        for link in goal.mapLinks {
            let sameMap = link.objective.mapId == context.currentMapID
            let proximity = distanceScore(to: link.objective, player: context.playerPosition)
            actions.append(SuggestedAction(
                type: .navigate, title: "Navigate to \(link.objective.name)",
                reason: sameMap
                    ? "You linked this objective, and it is on your current map."
                    : "You linked this objective manually. It is on map \(link.objective.mapId).",
                goalID: goal.id, confidence: .userConfigured,
                provenance: [.userDeclared] + (sameMap ? [.liveTelemetry] : []),
                score: priority + 80 + (sameMap ? 100 : 0) + proximity,
                objectiveIDs: [link.objective.id]))
        }

        if let plan = craftingPlan {
            for missing in plan.flattenedRequirements where missing.missingQuantity > 0 {
                guard case let .item(itemID) = missing.requirement else { continue }
                let name = context.itemNames[itemID] ?? "Item \(itemID)"
                if let mapping = ValidatedGatheringMappings.mapping(itemID: itemID) {
                    let matching = context.mapObjectives.filter { objective in
                        let categoryMatches: Bool = switch mapping.gatheringCategory {
                        case .ore: objective.type == .gatheringOre
                        case .wood: objective.type == .gatheringWood
                        case .plant: objective.type == .gatheringPlant
                        case .other: objective.type == .custom
                        }
                        return categoryMatches && (mapping.markerSubtype.map {
                            objective.name.localizedCaseInsensitiveContains($0)
                        } ?? true)
                    }.sorted { lhs, rhs in
                        distance(to: lhs, player: context.playerPosition) < distance(to: rhs, player: context.playerPosition)
                    }
                    if let nearest = matching.first {
                        let sameMap = nearest.mapId == context.currentMapID
                        actions.append(SuggestedAction(
                            type: .gather, title: "Find \(name) gathering locations",
                            reason: "You need \(missing.missingQuantity) more. A validated \(mapping.gatheringCategory.rawValue) mapping has a known location on your current map; node spawn and yield are not guaranteed.",
                            goalID: goal.id, confidence: .derivedStrong,
                            provenance: [.arenaNetPublic, .arenaNetAccount, mapping.provenance, .derived] + (sameMap ? [.liveTelemetry] : []),
                            score: priority + 80 + (sameMap ? 100 : 0) + distanceScore(to: nearest, player: context.playerPosition),
                            objectiveIDs: matching.map { $0.id }))
                    }
                }
                if let timed = context.prices[itemID], timed.price.sells.quantity > 0,
                   timed.price.sells.unitPrice > 0 {
                    actions.append(SuggestedAction(
                        type: .buy, title: "View \(name) buy-now price",
                        reason: "You are missing \(missing.missingQuantity), and current sell offers are available.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                        score: priority + 20))
                } else {
                    actions.append(SuggestedAction(
                        type: .inspect, title: "Inspect \(name)",
                        reason: "This unresolved requirement has no currently loaded acquisition price or navigable mapping.",
                        goalID: goal.id, confidence: .limitedData,
                        provenance: [.arenaNetPublic, .derived], score: priority + 5))
                }
            }
            if !plan.targetAlreadyOwned && !plan.flattenedRequirements.isEmpty &&
                plan.flattenedRequirements.allSatisfy({ $0.missingQuantity == 0 }) {
                actions.append(SuggestedAction(
                    type: .craft, title: "Craft the ready requirements",
                    reason: "Current account holdings satisfy every flattened requirement.",
                    goalID: goal.id, confidence: .derivedStrong,
                    provenance: [.arenaNetPublic, .arenaNetAccount, .derived], score: priority + 40))
            }
        }

        if let achievement, achievement.progressAvailable,
           achievement.progress?.done == false, goal.mapLinks.isEmpty {
            actions.append(SuggestedAction(
                type: .inspect, title: "Inspect unfinished objectives",
                reason: "ArenaNet reports this achievement as incomplete, but no trustworthy map location is linked.",
                goalID: goal.id, confidence: .authoritative,
                provenance: [.arenaNetAccount, .arenaNetPublic], score: priority + 5))
        }


        if let achievement {
            for bit in achievement.bits where bit.isComplete != true {
                guard case let .item(itemID) = bit.bit else { continue }
                let name = context.itemNames[itemID] ?? bit.title
                if context.craftableItemIDs.contains(itemID) {
                    actions.append(SuggestedAction(
                        type: .craft, title: "Plan crafting \(name)",
                        reason: "This unfinished achievement objective references an item with a known public recipe.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                        score: priority + 40, itemID: itemID))
                }
                if let price = context.prices[itemID], price.price.sells.quantity > 0 {
                    actions.append(SuggestedAction(
                        type: .buy, title: "View \(name) market price",
                        reason: "This unfinished item objective has a current lowest sell offer.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                        score: priority + 20, itemID: itemID))
                } else if !context.craftableItemIDs.contains(itemID) {
                    actions.append(SuggestedAction(
                        type: .inspect, title: "Inspect \(name)",
                        reason: "ArenaNet identifies this unfinished objective as an item; no stronger loaded acquisition option is available.",
                        goalID: goal.id, confidence: .authoritative,
                        provenance: [.arenaNetPublic, .arenaNetAccount], score: priority + 5,
                        itemID: itemID))
                }
            }
        }

        if actions.isEmpty {
            actions.append(SuggestedAction(
                type: .inspect, title: "Inspect goal details",
                reason: "No stronger action is justified by the currently available data.",
                goalID: goal.id, confidence: .limitedData,
                provenance: [.derived], score: priority))
        }
        return actions.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func distance(to objective: MapObjective, player: ContinentPoint?) -> Double {
        player.map { ObjectiveDistanceEngine.distance(from: $0, to: objective.coordinate) } ?? .greatestFiniteMagnitude
    }

    private static func distanceScore(to objective: MapObjective, player: ContinentPoint?) -> Int {
        guard let player else { return 0 }
        let distance = ObjectiveDistanceEngine.distance(from: player, to: objective.coordinate)
        return max(0, 30 - Int(distance / 100))
    }
}
