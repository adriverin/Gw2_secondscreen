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
        legendaryPlan: LegendaryProgressPlan? = nil,
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
                if let timed = context.prices[itemID] {
                    let state = TradingPostPriceResolver.state(
                        price: timed, item: nil)
                    if let title = TradingPostPriceResolver.suggestedActionTitle(
                        name: name, missingQuantity: missing.missingQuantity, state: state)
                    {
                        actions.append(SuggestedAction(
                            type: .buy, title: title,
                            reason: "You are missing \(missing.missingQuantity). Opening this shows the current Trading Post price state.",
                            goalID: goal.id, confidence: .derivedStrong,
                            provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                            score: priority + 20, itemID: itemID))
                    }
                } else {
                    actions.append(SuggestedAction(
                        type: .buy, title: "Check Trading Post price",
                        reason: "You are missing \(missing.missingQuantity). A Trading Post lookup can be attempted for this item.",
                        goalID: goal.id, confidence: .limitedData,
                        provenance: [.arenaNetPublic, .derived],
                        score: priority + 15, itemID: itemID))
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

        if let plan = legendaryPlan, plan.ownership == .notOwned {
            for node in plan.sessionNodes where node.missingQuantity > 0 {
                let name = node.name
                if node.binding == .tradable {
                    if let mapping = ValidatedGatheringMappings.mapping(itemID: node.itemID) {
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
                                reason: "You need \(node.missingQuantity) more for this legendary plan. Node spawn and yield are not guaranteed.",
                                goalID: goal.id, confidence: .derivedStrong,
                                provenance: [.companionObserved, .arenaNetAccount, mapping.provenance, .derived] + (sameMap ? [.liveTelemetry] : []),
                                score: priority + 80 + (sameMap ? 100 : 0) + distanceScore(to: nearest, player: context.playerPosition),
                                objectiveIDs: matching.map(\.id)))
                        }
                    }
                    if let timed = context.prices[node.itemID] {
                        let state = TradingPostPriceResolver.state(price: timed, item: nil)
                        if let title = TradingPostPriceResolver.suggestedActionTitle(
                            name: name, missingQuantity: node.missingQuantity, state: state)
                        {
                            actions.append(SuggestedAction(
                                type: .buy, title: title,
                                reason: "Tradable missing material for this legendary. Opening this shows the current Trading Post price state.",
                                goalID: goal.id, confidence: .derivedStrong,
                                provenance: [.arenaNetPublic, .companionObserved, .derived],
                                score: priority + 20, itemID: node.itemID))
                        }
                    } else {
                        actions.append(SuggestedAction(
                            type: .buy, title: "Check Trading Post price",
                            reason: "You are missing \(node.missingQuantity) \(name). A Trading Post lookup can be attempted.",
                            goalID: goal.id, confidence: .limitedData,
                            provenance: [.companionObserved, .derived],
                            score: priority + 15, itemID: node.itemID))
                    }
                } else if node.acquisition == .mysticForge || node.status == .readyToCraft {
                    actions.append(SuggestedAction(
                        type: .craft, title: "Create \(name) in the Mystic Forge",
                        reason: node.status == .readyToCraft
                            ? "Holdings satisfy the known ingredients for this component."
                            : "This legendary component is created in the Mystic Forge.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.companionObserved, .derived], score: priority + 40, itemID: node.itemID))
                } else if node.acquisition == .craft {
                    actions.append(SuggestedAction(
                        type: .craft, title: "Craft \(name)",
                        reason: "This account-bound component is crafted after buying the recipe from a Mystic Forge vendor.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.companionObserved, .derived], score: priority + 35, itemID: node.itemID))
                } else if node.acquisition == .vendor {
                    actions.append(SuggestedAction(
                        type: .inspect, title: "Get \(name) from a vendor",
                        reason: node.notes ?? "This account-bound component is purchased from a vendor and cannot be priced on the Trading Post.",
                        goalID: goal.id, confidence: .derivedStrong,
                        provenance: [.companionObserved, .derived], score: priority + 25, itemID: node.itemID))
                } else {
                    actions.append(SuggestedAction(
                        type: .markManually, title: "Resolve \(name) manually",
                        reason: node.notes ?? "This requirement is account-bound or gameplay-gated and is not inferred from other holdings.",
                        goalID: goal.id, confidence: .limitedData,
                        provenance: [.companionObserved, .derived], score: priority + 10, itemID: node.itemID))
                }
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
                if let price = context.prices[itemID] {
                    let state = TradingPostPriceResolver.state(price: price)
                    if let title = TradingPostPriceResolver.suggestedActionTitle(
                        name: name, missingQuantity: 1, state: state)
                    {
                        actions.append(SuggestedAction(
                            type: .buy, title: title,
                            reason: "This unfinished item objective can be looked up on the Trading Post.",
                            goalID: goal.id, confidence: .derivedStrong,
                            provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                            score: priority + 20, itemID: itemID))
                    }
                } else if !context.craftableItemIDs.contains(itemID) {
                    actions.append(SuggestedAction(
                        type: .buy, title: "Check Trading Post price",
                        reason: "ArenaNet identifies this unfinished objective as an item; a Trading Post lookup can be attempted.",
                        goalID: goal.id, confidence: .authoritative,
                        provenance: [.arenaNetPublic, .arenaNetAccount], score: priority + 15,
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
