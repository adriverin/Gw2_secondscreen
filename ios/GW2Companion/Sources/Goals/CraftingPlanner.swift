import Foundation

enum Requirement: Codable, Hashable, Sendable, Identifiable {
    case item(Int)
    case currency(Int)
    case guildUpgrade(Int)
    case unknown(type: String, id: Int)

    var id: String {
        switch self {
        case let .item(id): "item:\(id)"
        case let .currency(id): "currency:\(id)"
        case let .guildUpgrade(id): "guild:\(id)"
        case let .unknown(type, id): "unknown:\(type):\(id)"
        }
    }
}

enum AcquisitionOptionType: String, Codable, Sendable {
    case owned, craft, buy, gather, manual, unsupported
}

struct AcquisitionOption: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let type: AcquisitionOptionType
    let title: String
    let reason: String
    let provenance: [DataProvenance]

    init(
        id: UUID = UUID(), type: AcquisitionOptionType, title: String,
        reason: String, provenance: [DataProvenance]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.reason = reason
        self.provenance = provenance
    }
}

enum CraftGraphIssue: Codable, Hashable, Sendable {
    case cycle(itemID: Int)
    case depthLimit(itemID: Int)
    case missingRecipe(itemID: Int)
    case unknownIngredient(type: String, id: Int)
    case guildUpgradeUnsupported(id: Int)
}

struct CraftRequirementNode: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let requirement: Requirement
    let requiredQuantity: Int
    let ownedQuantity: Int
    let missingQuantity: Int
    let recipeID: Int?
    let recipeOutputQuantity: Int?
    let children: [CraftRequirementNode]
    let acquisitionOptions: [AcquisitionOption]
    let issues: [CraftGraphIssue]

    init(
        id: UUID = UUID(), requirement: Requirement, requiredQuantity: Int,
        ownedQuantity: Int, missingQuantity: Int, recipeID: Int? = nil,
        recipeOutputQuantity: Int? = nil, children: [CraftRequirementNode] = [],
        acquisitionOptions: [AcquisitionOption] = [], issues: [CraftGraphIssue] = []
    ) {
        self.id = id
        self.requirement = requirement
        self.requiredQuantity = requiredQuantity
        self.ownedQuantity = ownedQuantity
        self.missingQuantity = missingQuantity
        self.recipeID = recipeID
        self.recipeOutputQuantity = recipeOutputQuantity
        self.children = children
        self.acquisitionOptions = acquisitionOptions
        self.issues = issues
    }
}

struct FlattenedRequirement: Identifiable, Codable, Hashable, Sendable {
    var id: String { requirement.id }
    let requirement: Requirement
    let requiredQuantity: Int
    let ownedQuantity: Int
    let missingQuantity: Int
    let provenance: ExplainableValue<Int>
}

struct CraftingPlan: Codable, Hashable, Sendable {
    let targetItemID: Int
    let targetQuantity: Int
    let targetOwnedQuantity: Int
    let root: CraftRequirementNode
    let flattenedRequirements: [FlattenedRequirement]
    let nodeCount: Int
    let maximumDepth: Int
    let issues: [CraftGraphIssue]

    var targetAlreadyOwned: Bool { targetOwnedQuantity >= targetQuantity }
    var readyRequirementCount: Int { flattenedRequirements.filter { $0.missingQuantity == 0 }.count }
    var totalRequirementCount: Int { max(flattenedRequirements.count, targetAlreadyOwned ? 1 : 0) }
    var progress: GoalProgress {
        if targetAlreadyOwned {
            return GoalProgress(ready: 1, total: 1, label: "Target already owned", isAuthoritativeCompletion: false)
        }
        let ready = readyRequirementCount
        let total = totalRequirementCount
        return GoalProgress(
            ready: ready, total: total,
            label: total == 0 ? "Requirements unresolved" : "\(ready) of \(total) final requirements ready",
            isAuthoritativeCompletion: false)
    }
}

struct RecipeOutputIndex: Codable, Sendable, Equatable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let builtAt: Date
    let recipeIDsByOutputItem: [Int: [Int]]

    init(recipes: [Int: RecipeDefinition], builtAt: Date = Date()) {
        schemaVersion = Self.schemaVersion
        self.builtAt = builtAt
        var result: [Int: [Int]] = [:]
        for recipe in recipes.values {
            guard let output = recipe.outputItemID else { continue }
            result[output, default: []].append(recipe.id)
        }
        recipeIDsByOutputItem = result.mapValues { $0.sorted() }
    }

    func recipesProducing(itemID: Int) -> [Int] { recipeIDsByOutputItem[itemID] ?? [] }
}

enum RecipeAvailability: String, Codable, Sendable {
    case known, autoLearned, unknown, locked
}

struct CraftingCapability: Equatable, Sendable {
    let disciplineSatisfied: Bool
    let characterName: String?
    let discipline: String?
    let requiredRating: Int
    let highestRating: Int
    let recipeAvailability: RecipeAvailability
}

enum RecipeCapabilityEngine {
    static func capability(
        recipe: RecipeDefinition, characters: [GW2Character], unlockedRecipeIDs: Set<Int>,
        unlockPermissionAvailable: Bool
    ) -> CraftingCapability {
        let matching = characters.flatMap { character in
            (character.crafting ?? []).filter { recipe.disciplines.contains($0.discipline) }
                .map { (character.name, $0) }
        }.sorted { lhs, rhs in
            if lhs.1.rating != rhs.1.rating { return lhs.1.rating > rhs.1.rating }
            return lhs.0 < rhs.0
        }
        let best = matching.first
        let availability: RecipeAvailability
        if recipe.isAutomaticallyLearned { availability = .autoLearned }
        else if !unlockPermissionAvailable { availability = .unknown }
        else if unlockedRecipeIDs.contains(recipe.id) { availability = .known }
        else { availability = .locked }
        return CraftingCapability(
            disciplineSatisfied: (best?.1.rating ?? 0) >= recipe.minRating,
            characterName: best?.0, discipline: best?.1.discipline ?? recipe.disciplines.first,
            requiredRating: recipe.minRating, highestRating: best?.1.rating ?? 0,
            recipeAvailability: availability)
    }
}

enum CraftingPlanner {
    private struct Totals { var required = 0; var owned = 0 }

    static func build(
        targetItemID: Int, quantity: Int, recipes: [Int: RecipeDefinition],
        index: RecipeOutputIndex, selectedRecipeIDs: [Int: Int] = [:],
        holdings: [AccountHolding], wallet: [WalletEntry] = [],
        holdingsAvailable: Bool = true, maxDepth: Int = 24,
        calculatedAt: Date = Date()
    ) -> CraftingPlan {
        let requested = max(1, quantity)
        var itemSupply = Dictionary(uniqueKeysWithValues: holdings.map { ($0.itemID, $0.totalQuantity) })
        var currencySupply = Dictionary(uniqueKeysWithValues: wallet.map { ($0.id, $0.value) })
        let targetOwned = min(requested, itemSupply[targetItemID] ?? 0)
        var totals: [Requirement: Totals] = [:]
        var issues: [CraftGraphIssue] = []
        var nodeCount = 0
        var deepest = 0

        func recipe(for itemID: Int) -> RecipeDefinition? {
            let candidates = index.recipesProducing(itemID: itemID)
            if let selected = selectedRecipeIDs[itemID], candidates.contains(selected) { return recipes[selected] }
            return candidates.compactMap { recipes[$0] }.sorted { $0.id < $1.id }.first
        }

        func options(for requirement: Requirement, owned: Int, recipeID: Int?) -> [AcquisitionOption] {
            var values: [AcquisitionOption] = []
            if owned > 0 {
                values.append(AcquisitionOption(
                    type: .owned, title: "Already owned", reason: "Allocated from current account holdings.",
                    provenance: [.arenaNetAccount, .derived]))
            }
            if recipeID != nil {
                values.append(AcquisitionOption(
                    type: .craft, title: "Craft", reason: "An ArenaNet recipe produces this item.",
                    provenance: [.arenaNetPublic]))
            }
            if case .item = requirement {
                values.append(AcquisitionOption(
                    type: .buy, title: "Check Trading Post", reason: "Availability depends on current public listings.",
                    provenance: [.arenaNetPublic]))
            }
            return values
        }

        func expand(_ requirement: Requirement, quantity: Int, depth: Int, path: Set<Int>) -> CraftRequirementNode {
            nodeCount += 1
            deepest = max(deepest, depth)
            let required = max(0, quantity)
            switch requirement {
            case let .item(itemID):
                let available = holdingsAvailable ? itemSupply[itemID, default: 0] : 0
                let owned = min(required, available)
                if holdingsAvailable { itemSupply[itemID] = max(0, available - owned) }
                let remaining = required - owned
                guard remaining > 0 else {
                    totals[requirement, default: Totals()].required += required
                    totals[requirement, default: Totals()].owned += owned
                    return CraftRequirementNode(
                        requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                        missingQuantity: 0, acquisitionOptions: options(for: requirement, owned: owned, recipeID: nil))
                }
                if path.contains(itemID) {
                    let issue = CraftGraphIssue.cycle(itemID: itemID)
                    issues.append(issue)
                    totals[requirement, default: Totals()].required += required
                    totals[requirement, default: Totals()].owned += owned
                    return CraftRequirementNode(
                        requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                        missingQuantity: remaining, acquisitionOptions: options(for: requirement, owned: owned, recipeID: nil),
                        issues: [issue])
                }
                if depth >= maxDepth {
                    let issue = CraftGraphIssue.depthLimit(itemID: itemID)
                    issues.append(issue)
                    totals[requirement, default: Totals()].required += required
                    totals[requirement, default: Totals()].owned += owned
                    return CraftRequirementNode(
                        requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                        missingQuantity: remaining, acquisitionOptions: options(for: requirement, owned: owned, recipeID: nil),
                        issues: [issue])
                }
                guard let selected = recipe(for: itemID), selected.outputItemCount > 0 else {
                    let issue = CraftGraphIssue.missingRecipe(itemID: itemID)
                    issues.append(issue)
                    totals[requirement, default: Totals()].required += required
                    totals[requirement, default: Totals()].owned += owned
                    return CraftRequirementNode(
                        requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                        missingQuantity: remaining, acquisitionOptions: options(for: requirement, owned: owned, recipeID: nil),
                        issues: [issue])
                }
                let batches = (remaining + selected.outputItemCount - 1) / selected.outputItemCount
                let childPath = path.union([itemID])
                let children = selected.ingredients.sorted { ($0.type, $0.id) < ($1.type, $1.id) }.map { ingredient in
                    let scaled = ingredient.count.multipliedReportingOverflow(by: batches)
                    let childQuantity = scaled.overflow ? Int.max : scaled.partialValue
                    switch ingredient.knownType {
                    case .item: return expand(.item(ingredient.id), quantity: childQuantity, depth: depth + 1, path: childPath)
                    case .currency: return expand(.currency(ingredient.id), quantity: childQuantity, depth: depth + 1, path: childPath)
                    case .guildUpgrade:
                        return expand(.guildUpgrade(ingredient.id), quantity: childQuantity, depth: depth + 1, path: childPath)
                    case nil:
                        return expand(.unknown(type: ingredient.type, id: ingredient.id), quantity: childQuantity, depth: depth + 1, path: childPath)
                    }
                }
                return CraftRequirementNode(
                    requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                    missingQuantity: remaining, recipeID: selected.id,
                    recipeOutputQuantity: selected.outputItemCount, children: children,
                    acquisitionOptions: options(for: requirement, owned: owned, recipeID: selected.id))

            case let .currency(currencyID):
                let available = currencySupply[currencyID, default: 0]
                let owned = min(required, available)
                currencySupply[currencyID] = max(0, available - owned)
                totals[requirement, default: Totals()].required += required
                totals[requirement, default: Totals()].owned += owned
                return CraftRequirementNode(
                    requirement: requirement, requiredQuantity: required, ownedQuantity: owned,
                    missingQuantity: required - owned,
                    acquisitionOptions: owned > 0 ? [AcquisitionOption(
                        type: .owned, title: "Wallet balance", reason: "Allocated from the ArenaNet account wallet.",
                        provenance: [.arenaNetAccount, .derived])] : [])

            case let .guildUpgrade(id):
                let issue = CraftGraphIssue.guildUpgradeUnsupported(id: id)
                issues.append(issue)
                totals[requirement, default: Totals()].required += required
                return CraftRequirementNode(
                    requirement: requirement, requiredQuantity: required, ownedQuantity: 0,
                    missingQuantity: required, acquisitionOptions: [AcquisitionOption(
                        type: .unsupported, title: "Guild upgrade", reason: "Guild upgrade planning is not supported yet.",
                        provenance: [.arenaNetPublic])], issues: [issue])

            case let .unknown(type, id):
                let issue = CraftGraphIssue.unknownIngredient(type: type, id: id)
                issues.append(issue)
                totals[requirement, default: Totals()].required += required
                return CraftRequirementNode(
                    requirement: requirement, requiredQuantity: required, ownedQuantity: 0,
                    missingQuantity: required, acquisitionOptions: [AcquisitionOption(
                        type: .unsupported, title: "Unsupported requirement", reason: "ArenaNet returned ingredient type \(type).",
                        provenance: [.arenaNetPublic])], issues: [issue])
            }
        }

        let root = expand(.item(targetItemID), quantity: requested, depth: 0, path: [])
        let holdingsByID = Dictionary(uniqueKeysWithValues: holdings.map { ($0.itemID, $0) })
        let flattened = totals.map { requirement, total in
            let missing = max(0, total.required - total.owned)
            var dependencies = [ProvenanceDependency(
                label: "Recipe demand", detail: "\(total.required) required",
                provenance: .arenaNetPublic, observedAt: calculatedAt)]
            if case let .item(id) = requirement, let holding = holdingsByID[id] {
                dependencies.append(contentsOf: holding.locations.map {
                    ProvenanceDependency(
                        label: $0.location.title, detail: "\($0.quantity) owned",
                        provenance: .arenaNetAccount, observedAt: calculatedAt)
                })
            } else if case let .currency(id) = requirement, let value = wallet.first(where: { $0.id == id })?.value {
                dependencies.append(ProvenanceDependency(
                    label: "Wallet", detail: "\(value) owned", provenance: .arenaNetAccount,
                    observedAt: calculatedAt))
            }
            return FlattenedRequirement(
                requirement: requirement, requiredQuantity: total.required,
                ownedQuantity: total.owned, missingQuantity: missing,
                provenance: ExplainableValue(
                    value: missing, provenance: .derived, dependencies: dependencies,
                    calculatedAt: calculatedAt))
        }.sorted { $0.id < $1.id }

        return CraftingPlan(
            targetItemID: targetItemID, targetQuantity: requested,
            targetOwnedQuantity: targetOwned, root: root,
            flattenedRequirements: flattened, nodeCount: nodeCount,
            maximumDepth: deepest, issues: issues)
    }
}

enum MarketDataState: Equatable, Sendable {
    case available
    case noSellOrders
    case noBuyOrders
    case noPriceRecord
    case nonTradable
    case stale
    case unavailable
}

struct MarketEstimate: Equatable, Sendable {
    let copper: Int64
    let unitCopper: Int64
    let quantity: Int
    let checkedAt: Date
    let stale: Bool

    var amount: CoinAmount { CoinAmount(copperValue: copper) }
}

enum MarketCalculator {
    static func buyState(
        price: TimedCommercePrice?, item: ItemMetadata? = nil,
        now: Date = Date(), ttl: TimeInterval = 300
    ) -> MarketDataState {
        if item?.flags?.contains(where: { ["AccountBound", "SoulbindOnAcquire"].contains($0) }) == true {
            return .nonTradable
        }
        guard let price else { return .noPriceRecord }
        if now.timeIntervalSince(price.fetchedAt) > ttl { return .stale }
        return price.price.sells.quantity > 0 && price.price.sells.unitPrice > 0 ? .available : .noSellOrders
    }

    static func sellState(
        price: TimedCommercePrice?, item: ItemMetadata? = nil,
        now: Date = Date(), ttl: TimeInterval = 300
    ) -> MarketDataState {
        if item?.flags?.contains(where: { ["AccountBound", "SoulbindOnAcquire"].contains($0) }) == true {
            return .nonTradable
        }
        guard let price else { return .noPriceRecord }
        if now.timeIntervalSince(price.fetchedAt) > ttl { return .stale }
        return price.price.buys.quantity > 0 && price.price.buys.unitPrice > 0 ? .available : .noBuyOrders
    }

    static func buyNow(price: TimedCommercePrice?, quantity: Int, now: Date = Date(), ttl: TimeInterval = 300) -> MarketEstimate? {
        guard let price, quantity > 0, price.price.sells.quantity > 0, price.price.sells.unitPrice > 0 else { return nil }
        let unit = Int64(price.price.sells.unitPrice)
        let result = unit.multipliedReportingOverflow(by: Int64(quantity))
        guard !result.overflow else { return nil }
        return MarketEstimate(
            copper: result.partialValue, unitCopper: unit, quantity: quantity,
            checkedAt: price.fetchedAt, stale: now.timeIntervalSince(price.fetchedAt) > ttl)
    }

    static func sellNow(price: TimedCommercePrice?, quantity: Int, now: Date = Date(), ttl: TimeInterval = 300) -> MarketEstimate? {
        guard let price, quantity > 0, price.price.buys.quantity > 0, price.price.buys.unitPrice > 0 else { return nil }
        let unit = Int64(price.price.buys.unitPrice)
        let result = unit.multipliedReportingOverflow(by: Int64(quantity))
        guard !result.overflow else { return nil }
        return MarketEstimate(
            copper: result.partialValue, unitCopper: unit, quantity: quantity,
            checkedAt: price.fetchedAt, stale: now.timeIntervalSince(price.fetchedAt) > ttl)
    }
}

struct GatheringMaterialMapping: Codable, Hashable, Sendable {
    let itemID: Int
    let gatheringCategory: GatheringCategory
    let markerSubtype: String?
    let provenance: DataProvenance
}

enum ValidatedGatheringMappings {
    /// Deliberately small. A marker is a possible location, never a yield guarantee.
    static let values = [
        GatheringMaterialMapping(
            itemID: 19_700, gatheringCategory: .ore, markerSubtype: "Mithril",
            provenance: .companionObserved)
    ]

    static func mapping(itemID: Int) -> GatheringMaterialMapping? {
        values.first { $0.itemID == itemID }
    }
}

/// Acquisition is intentionally separate from the dependency graph. New rule providers can
/// add ways to satisfy a requirement without changing the goal or equating every item to a recipe.
protocol AcquisitionRuleProvider: Sendable {
    func options(for requirement: Requirement) async -> [AcquisitionOption]
}

struct RecipeAcquisitionProvider: AcquisitionRuleProvider {
    let index: RecipeOutputIndex

    func options(for requirement: Requirement) async -> [AcquisitionOption] {
        guard case let .item(itemID) = requirement,
              !index.recipesProducing(itemID: itemID).isEmpty else { return [] }
        return [AcquisitionOption(
            type: .craft, title: "Craft", reason: "A public ArenaNet recipe produces this item.",
            provenance: [.arenaNetPublic])]
    }
}

struct TradingPostAcquisitionProvider: AcquisitionRuleProvider {
    let prices: [Int: TimedCommercePrice]

    func options(for requirement: Requirement) async -> [AcquisitionOption] {
        guard case let .item(itemID) = requirement, let value = prices[itemID],
              value.price.sells.quantity > 0, value.price.sells.unitPrice > 0 else { return [] }
        return [AcquisitionOption(
            type: .buy, title: "Buy", reason: "A current lowest sell offer is available.",
            provenance: [.arenaNetPublic])]
    }
}

struct GatheringAcquisitionProvider: AcquisitionRuleProvider {
    func options(for requirement: Requirement) async -> [AcquisitionOption] {
        guard case let .item(itemID) = requirement,
              let mapping = ValidatedGatheringMappings.mapping(itemID: itemID) else { return [] }
        return [AcquisitionOption(
            type: .gather, title: "Find gathering locations",
            reason: "A validated \(mapping.gatheringCategory.rawValue) marker mapping exists; spawn and yield are not guaranteed.",
            provenance: [mapping.provenance])]
    }
}

struct ManualAcquisitionProvider: AcquisitionRuleProvider {
    func options(for requirement: Requirement) async -> [AcquisitionOption] {
        [AcquisitionOption(
            type: .manual, title: "Resolve manually",
            reason: "No authoritative automated acquisition rule is required to record manual progress.",
            provenance: [.userDeclared])]
    }
}

enum AcquisitionOptionEngine {
    static func options(
        for requirement: Requirement, providers: [any AcquisitionRuleProvider]
    ) async -> [AcquisitionOption] {
        var result: [AcquisitionOption] = []
        for provider in providers { result.append(contentsOf: await provider.options(for: requirement)) }
        return result
    }
}
