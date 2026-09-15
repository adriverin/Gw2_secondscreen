import Foundation

enum LegendaryPlanner {
    static func plan(
        itemID: Int, catalog: LegendaryCatalog, holdings: [AccountHolding],
        armoryCounts: [Int: Int], prices: [Int: TimedCommercePrice] = [:],
        itemNames: [Int: String] = [:]
    ) -> LegendaryProgressPlan? {
        guard let definition = catalog.plan(for: itemID) else { return nil }
        return plan(
            definition: definition, catalog: catalog, holdings: holdings,
            armoryCounts: armoryCounts, prices: prices, itemNames: itemNames)
    }

    static func plan(
        definition: LegendaryPlanDefinition, catalog: LegendaryCatalog,
        holdings: [AccountHolding], armoryCounts: [Int: Int],
        prices: [Int: TimedCommercePrice] = [:], itemNames: [Int: String] = [:]
    ) -> LegendaryProgressPlan {
        var supply = Dictionary(uniqueKeysWithValues: holdings.map { ($0.itemID, $0.totalQuantity) })
        let components = catalog.componentsByID
        let armoryOwned = (armoryCounts[definition.targetItemID] ?? 0) > 0
        let holdingsOwned = (supply[definition.targetItemID] ?? 0) > 0
        let ownership: LegendaryOwnershipState = if armoryOwned { .armory } else if holdingsOwned { .holdings } else { .notOwned }

        if ownership != .notOwned {
            let topLevel = definition.topLevelRequirements.map { requirement in
                ownedNode(requirement: requirement, components: components, itemNames: itemNames)
            }
            return makePlan(
                definition: definition, ownership: ownership, topLevel: topLevel,
                prices: prices)
        }

        var leaves: [Int: LegendaryProgressNode] = [:]
        var session: [Int: LegendaryProgressNode] = [:]
        let topLevel = definition.topLevelRequirements.map { requirement in
            expand(
                requirement, components: components, supply: &supply, itemNames: itemNames,
                leaves: &leaves, session: &session, path: [])
        }
        return makePlan(
            definition: definition, ownership: ownership, topLevel: topLevel,
            leaves: Array(leaves.values), session: Array(session.values), prices: prices)
    }

    static func acquisitionMethods(from catalog: LegendaryCatalog) -> [AcquisitionMethod] {
        catalog.components.map { component in
            var requirements = component.ingredients.map { AcquisitionRequirement.item(id: $0.itemID, quantity: $0.quantity) }
            if let currencyID = component.vendorCurrencyID, let quantity = component.vendorCurrencyQuantity {
                requirements.append(.currency(id: currencyID, quantity: quantity))
            }
            if component.acquisition == .gameplayManual, let notes = component.notes {
                requirements.append(.manual(notes))
            }
            let cost: AcquisitionCost? = {
                if let copper = component.vendorCoinCopper {
                    return AcquisitionCost(coinCopper: copper, currencies: [], items: [])
                }
                if let currencyID = component.vendorCurrencyID, let quantity = component.vendorCurrencyQuantity {
                    return AcquisitionCost(
                        coinCopper: nil, currencies: [CurrencyCost(currencyID: currencyID, quantity: quantity)],
                        items: [])
                }
                return nil
            }()
            return AcquisitionMethod(
                id: "legendary:\(component.acquisition.rawValue):\(component.itemID)",
                target: .item(id: component.itemID),
                type: component.acquisition.methodType,
                title: methodTitle(component),
                description: component.notes,
                requirements: requirements,
                location: nil,
                cost: cost,
                source: KnowledgeSource(
                    type: .companionCurated, sourceID: catalog.catalogVersion,
                    sourceURL: component.sourceURL, reviewedAt: component.reviewedAt,
                    notes: "Curated legendary acquisition fact."),
                confidence: component.coverage == .complete ? .verified : .limited,
                coverage: component.coverage, gatheringCategory: nil, markerSubtype: nil)
        }
    }

    static func browserItems(
        definitions: [LegendaryArmoryDefinition], items: [Int: ItemMetadata],
        catalog: LegendaryCatalog, armoryCounts: [Int: Int], holdings: [AccountHolding]
    ) -> [LegendaryBrowserItem] {
        let holdingIDs = Set(holdings.filter { $0.totalQuantity > 0 }.map(\.itemID))
        var seen = Set<Int>()
        var values: [LegendaryBrowserItem] = []
        let ids = Set(definitions.map(\.id)).union(catalog.plans.map(\.targetItemID))
        for itemID in ids.sorted() {
            guard seen.insert(itemID).inserted else { continue }
            let item = items[itemID]
            let plan = catalog.plan(for: itemID)
            let ownership: LegendaryOwnershipState = if (armoryCounts[itemID] ?? 0) > 0 {
                .armory
            } else if holdingIDs.contains(itemID) {
                .holdings
            } else {
                .notOwned
            }
            values.append(LegendaryBrowserItem(
                itemID: itemID,
                name: item?.name ?? plan?.name ?? "Item \(itemID)",
                icon: item?.icon,
                category: plan?.category ?? item.map(LegendaryBrowserCategory.grouping(for:)) ?? .other,
                weaponType: plan?.weaponType ?? item?.details?.type,
                ownership: ownership,
                availability: catalog.availability(for: itemID)))
        }
        return values.sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return lhs.category.title < rhs.category.title
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func estimatedBuyNow(for plan: LegendaryProgressPlan) -> MarketEstimate? {
        guard let copper = plan.estimatedBuyNowCopper else { return nil }
        return MarketEstimate(
            copper: copper, unitCopper: 0, quantity: plan.tradableMissing.count,
            checkedAt: Date(), stale: !plan.pricesUnavailableItemIDs.isEmpty)
    }

    private static func expand(
        _ requirement: LegendaryIngredient,
        components: [Int: LegendaryComponentDefinition],
        supply: inout [Int: Int],
        itemNames: [Int: String],
        leaves: inout [Int: LegendaryProgressNode],
        session: inout [Int: LegendaryProgressNode],
        path: Set<Int>
    ) -> LegendaryProgressNode {
        let component = components[requirement.itemID]
        let available = supply[requirement.itemID, default: 0]
        let owned = min(requirement.quantity, available)
        supply[requirement.itemID] = max(0, available - owned)
        let missing = requirement.quantity - owned
        let node: LegendaryProgressNode
        if missing == 0 || component == nil || component?.ingredients.isEmpty == true || path.contains(requirement.itemID) {
            node = makeNode(
                requirement: requirement, component: component, owned: owned, missing: missing,
                children: [], itemNames: itemNames)
            merge(&leaves, node)
            merge(&session, node)
            return node
        }
        var childPath = path
        childPath.insert(requirement.itemID)
        let children = (component?.ingredients ?? []).map { ingredient in
            let scaled = ingredient.quantity.multipliedReportingOverflow(by: missing)
            let quantity = scaled.overflow ? Int.max : scaled.partialValue
            return expand(
                LegendaryIngredient(itemID: ingredient.itemID, quantity: quantity),
                components: components, supply: &supply, itemNames: itemNames,
                leaves: &leaves, session: &session, path: childPath)
        }
        node = makeNode(
            requirement: requirement, component: component, owned: owned, missing: missing,
            children: children, itemNames: itemNames)
        merge(&session, node)
        return node
    }

    private static func makeNode(
        requirement: LegendaryIngredient, component: LegendaryComponentDefinition?,
        owned: Int, missing: Int, children: [LegendaryProgressNode], itemNames: [Int: String]
    ) -> LegendaryProgressNode {
        let binding = component?.binding ?? .tradable
        let acquisition = component?.acquisition ?? .unknown
        let status: LegendaryRequirementStatus
        if missing == 0 {
            status = .owned
        } else if !children.isEmpty, children.allSatisfy({ $0.missingQuantity == 0 }) {
            status = .readyToCraft
        } else if acquisition == .gameplayManual {
            status = .unknownManual
        } else if binding == .accountBound, children.isEmpty {
            status = .accountBoundManual
        } else {
            status = .missing
        }
        return LegendaryProgressNode(
            itemID: requirement.itemID,
            name: component?.name ?? itemNames[requirement.itemID] ?? "Item \(requirement.itemID)",
            requiredQuantity: requirement.quantity, ownedQuantity: owned, missingQuantity: missing,
            status: status, binding: binding, acquisition: acquisition,
            coverage: component?.coverage ?? .partial, notes: component?.notes, children: children)
    }

    private static func ownedNode(
        requirement: LegendaryIngredient, components: [Int: LegendaryComponentDefinition],
        itemNames: [Int: String]
    ) -> LegendaryProgressNode {
        let component = components[requirement.itemID]
        return LegendaryProgressNode(
            itemID: requirement.itemID,
            name: component?.name ?? itemNames[requirement.itemID] ?? "Item \(requirement.itemID)",
            requiredQuantity: requirement.quantity, ownedQuantity: requirement.quantity, missingQuantity: 0,
            status: .owned, binding: component?.binding ?? .accountBound,
            acquisition: component?.acquisition ?? .unknown,
            coverage: component?.coverage ?? .partial, notes: component?.notes, children: [])
    }

    private static func merge(_ bucket: inout [Int: LegendaryProgressNode], _ node: LegendaryProgressNode) {
        if let existing = bucket[node.itemID] {
            bucket[node.itemID] = LegendaryProgressNode(
                itemID: node.itemID, name: node.name,
                requiredQuantity: existing.requiredQuantity + node.requiredQuantity,
                ownedQuantity: existing.ownedQuantity + node.ownedQuantity,
                missingQuantity: existing.missingQuantity + node.missingQuantity,
                status: node.status, binding: node.binding, acquisition: node.acquisition,
                coverage: node.coverage, notes: node.notes, children: [])
        } else {
            bucket[node.itemID] = LegendaryProgressNode(
                itemID: node.itemID, name: node.name, requiredQuantity: node.requiredQuantity,
                ownedQuantity: node.ownedQuantity, missingQuantity: node.missingQuantity,
                status: node.status, binding: node.binding, acquisition: node.acquisition,
                coverage: node.coverage, notes: node.notes, children: [])
        }
    }

    private static func makePlan(
        definition: LegendaryPlanDefinition, ownership: LegendaryOwnershipState,
        topLevel: [LegendaryProgressNode], leaves: [LegendaryProgressNode] = [],
        session: [LegendaryProgressNode] = [], prices: [Int: TimedCommercePrice]
    ) -> LegendaryProgressPlan {
        let tradable = leaves.filter { $0.binding == .tradable && $0.missingQuantity > 0 }
        let bound = leaves.filter { $0.binding == .accountBound && $0.missingQuantity > 0 }
            + session.filter {
                $0.binding == .accountBound && $0.missingQuantity > 0 &&
                [.gameplayManual, .vendor].contains($0.acquisition)
            }
        var buyNow: Int64 = 0
        var unavailable: [Int] = []
        var counted = false
        for node in tradable {
            let state = TradingPostPriceResolver.state(price: prices[node.itemID])
            switch state {
            case .available, .stale:
                if let estimate = MarketCalculator.buyNow(price: prices[node.itemID], quantity: node.missingQuantity) {
                    buyNow += estimate.copper
                    counted = true
                } else {
                    unavailable.append(node.itemID)
                }
            default:
                unavailable.append(node.itemID)
            }
        }
        let uniqueBound = Dictionary(bound.map { ($0.itemID, $0) }, uniquingKeysWith: { _, last in last })
            .values.sorted { $0.itemID < $1.itemID }
        return LegendaryProgressPlan(
            targetItemID: definition.targetItemID, name: definition.name, coverage: definition.coverage,
            ownership: ownership, topLevel: topLevel,
            flattenedLeaves: leaves.sorted { $0.itemID < $1.itemID },
            sessionNodes: session.sorted { $0.itemID < $1.itemID },
            tradableMissing: tradable.sorted { $0.itemID < $1.itemID },
            accountBoundMissing: Array(uniqueBound),
            estimatedBuyNowCopper: counted ? buyNow : nil,
            pricesUnavailableItemIDs: unavailable.sorted(),
            topLevelReadyCount: topLevel.filter { $0.missingQuantity == 0 || $0.status == .readyToCraft }.count,
            topLevelTotalCount: topLevel.count,
            materialSatisfiedCount: leaves.filter { $0.missingQuantity == 0 }.count,
            materialMissingCount: leaves.filter { $0.missingQuantity > 0 }.count)
    }

    private static func methodTitle(_ component: LegendaryComponentDefinition) -> String {
        switch component.acquisition {
        case .mysticForge: "Create \(component.name) in the Mystic Forge"
        case .craft: "Craft \(component.name)"
        case .vendor: "Buy \(component.name) from a vendor"
        case .tradingPost: "Buy \(component.name) on the Trading Post"
        case .gameplayManual: "Resolve \(component.name) manually"
        case .unknown: "Unknown acquisition for \(component.name)"
        }
    }
}
