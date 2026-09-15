import Foundation

enum LegendaryBinding: String, Codable, Sendable {
    case tradable
    case accountBound
}

enum LegendaryAcquisitionKind: String, Codable, Sendable {
    case mysticForge
    case craft
    case vendor
    case tradingPost
    case gameplayManual
    case unknown

    var methodType: AcquisitionMethodType {
        switch self {
        case .mysticForge: .mysticForge
        case .craft: .craft
        case .vendor: .vendor
        case .tradingPost: .tradingPost
        case .gameplayManual, .unknown: .manual
        }
    }

    var title: String {
        switch self {
        case .mysticForge: "Mystic Forge"
        case .craft: "Craftable"
        case .vendor: "Vendor"
        case .tradingPost: "Tradable"
        case .gameplayManual: "Gameplay / manual"
        case .unknown: "Unknown"
        }
    }
}

enum LegendaryBrowserCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case weapons
    case armor
    case trinkets
    case upgradeComponents
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .weapons: "Weapons"
        case .armor: "Armor"
        case .trinkets: "Trinkets"
        case .upgradeComponents: "Runes / Sigils"
        case .other: "Other"
        }
    }

    static func grouping(for item: ItemMetadata) -> Self {
        switch item.type {
        case "Weapon": .weapons
        case "Armor": .armor
        case "Trinket", "Back": .trinkets
        case "UpgradeComponent": .upgradeComponents
        default: .other
        }
    }
}

enum LegendaryOwnershipState: String, Sendable {
    case armory
    case holdings
    case notOwned
}

enum LegendaryRequirementStatus: String, Sendable {
    case owned
    case readyToCraft
    case missing
    case accountBoundManual
    case unknownManual

    var title: String {
        switch self {
        case .owned: "Owned"
        case .readyToCraft: "Ready to craft"
        case .missing: "Missing"
        case .accountBoundManual: "Account-bound / manual"
        case .unknownManual: "Unknown / manual"
        }
    }
}

enum LegendaryPlanAvailability: String, Sendable {
    case complete
    case partial
    case none

    var title: String {
        switch self {
        case .complete: "Plan available"
        case .partial: "Limited plan"
        case .none: "No curated plan yet"
        }
    }
}

struct LegendaryIngredient: Codable, Hashable, Sendable {
    let itemID: Int
    let quantity: Int
}

struct LegendaryComponentDefinition: Codable, Hashable, Sendable, Identifiable {
    var id: Int { itemID }
    let itemID: Int
    let name: String
    let binding: LegendaryBinding
    let acquisition: LegendaryAcquisitionKind
    let ingredients: [LegendaryIngredient]
    let craftDiscipline: String?
    let craftRating: Int?
    let vendorCurrencyID: Int?
    let vendorCurrencyQuantity: Int?
    let vendorCoinCopper: Int64?
    let coverage: KnowledgeCoverage
    let sourceURL: URL?
    let reviewedAt: Date
    let notes: String?
}

struct LegendaryPlanDefinition: Codable, Hashable, Sendable, Identifiable {
    var id: Int { targetItemID }
    let targetItemID: Int
    let name: String
    let category: LegendaryBrowserCategory
    let weaponType: String?
    let topLevelRequirements: [LegendaryIngredient]
    let source: KnowledgeSource
    let coverage: KnowledgeCoverage
}

struct LegendaryCatalog: Codable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let catalogVersion: String
    let lastReviewedAt: Date
    let coverage: KnowledgeCoverage
    let components: [LegendaryComponentDefinition]
    let plans: [LegendaryPlanDefinition]

    var componentsByID: [Int: LegendaryComponentDefinition] {
        Dictionary(uniqueKeysWithValues: components.map { ($0.itemID, $0) })
    }

    var plansByItemID: [Int: LegendaryPlanDefinition] {
        Dictionary(uniqueKeysWithValues: plans.map { ($0.targetItemID, $0) })
    }

    func plan(for itemID: Int) -> LegendaryPlanDefinition? { plansByItemID[itemID] }

    func availability(for itemID: Int) -> LegendaryPlanAvailability {
        guard let plan = plansByItemID[itemID] else { return .none }
        return plan.coverage == .complete ? .complete : .partial
    }
}

enum LegendaryCatalogValidationIssue: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case emptyCatalogVersion
    case duplicateComponent(Int)
    case duplicatePlan(Int)
    case unknownIngredient(componentID: Int, itemID: Int)
    case unknownTopLevel(planID: Int, itemID: Int)
    case missingTargetComponent(Int)

    var description: String {
        switch self {
        case let .unsupportedSchema(value): "Unsupported legendary schema \(value)"
        case .emptyCatalogVersion: "Legendary catalog version is empty"
        case let .duplicateComponent(id): "Duplicate legendary component \(id)"
        case let .duplicatePlan(id): "Duplicate legendary plan \(id)"
        case let .unknownIngredient(componentID, itemID): "Component \(componentID) references unknown item \(itemID)"
        case let .unknownTopLevel(planID, itemID): "Plan \(planID) references unknown item \(itemID)"
        case let .missingTargetComponent(id): "Plan \(id) is missing a target component"
        }
    }
}

enum LegendaryCatalogError: Error, LocalizedError {
    case invalid([LegendaryCatalogValidationIssue])

    var errorDescription: String? {
        switch self {
        case let .invalid(issues): issues.map(\.description).joined(separator: "; ")
        }
    }
}

enum LegendaryCatalogValidator {
    static func validate(_ catalog: LegendaryCatalog) -> [LegendaryCatalogValidationIssue] {
        var issues: [LegendaryCatalogValidationIssue] = []
        if catalog.schemaVersion != LegendaryCatalog.schemaVersion {
            issues.append(.unsupportedSchema(catalog.schemaVersion))
        }
        if catalog.catalogVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyCatalogVersion)
        }
        var seenComponents: Set<Int> = []
        for component in catalog.components {
            if !seenComponents.insert(component.itemID).inserted {
                issues.append(.duplicateComponent(component.itemID))
            }
        }
        let known = Set(catalog.components.map(\.itemID))
        for component in catalog.components {
            for ingredient in component.ingredients where !known.contains(ingredient.itemID) {
                issues.append(.unknownIngredient(componentID: component.itemID, itemID: ingredient.itemID))
            }
        }
        var seenPlans: Set<Int> = []
        for plan in catalog.plans {
            if !seenPlans.insert(plan.targetItemID).inserted {
                issues.append(.duplicatePlan(plan.targetItemID))
            }
            if !known.contains(plan.targetItemID) {
                issues.append(.missingTargetComponent(plan.targetItemID))
            }
            for requirement in plan.topLevelRequirements where !known.contains(requirement.itemID) {
                issues.append(.unknownTopLevel(planID: plan.targetItemID, itemID: requirement.itemID))
            }
        }
        return issues
    }
}

struct BundledLegendaryCatalogProvider {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = Bundle(for: GoalStore.self), resourceName: String = "legendary-plans-v1") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func catalog() throws -> LegendaryCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(LegendaryCatalog.self, from: Data(contentsOf: url))
        let issues = LegendaryCatalogValidator.validate(catalog)
        guard issues.isEmpty else { throw LegendaryCatalogError.invalid(issues) }
        return catalog
    }
}

struct LegendaryProgressNode: Identifiable, Hashable, Sendable {
    var id: Int { itemID }
    let itemID: Int
    let name: String
    let requiredQuantity: Int
    let ownedQuantity: Int
    let missingQuantity: Int
    let status: LegendaryRequirementStatus
    let binding: LegendaryBinding
    let acquisition: LegendaryAcquisitionKind
    let coverage: KnowledgeCoverage
    let notes: String?
    let children: [LegendaryProgressNode]
}

struct LegendaryProgressPlan: Hashable, Sendable {
    let targetItemID: Int
    let name: String
    let coverage: KnowledgeCoverage
    let ownership: LegendaryOwnershipState
    let topLevel: [LegendaryProgressNode]
    let flattenedLeaves: [LegendaryProgressNode]
    let sessionNodes: [LegendaryProgressNode]
    let tradableMissing: [LegendaryProgressNode]
    let accountBoundMissing: [LegendaryProgressNode]
    let estimatedBuyNowCopper: Int64?
    let pricesUnavailableItemIDs: [Int]
    let topLevelReadyCount: Int
    let topLevelTotalCount: Int
    let materialSatisfiedCount: Int
    let materialMissingCount: Int

    var isOwnedInArmory: Bool { ownership == .armory }

    var progress: GoalProgress {
        if ownership != .notOwned {
            return GoalProgress(
                ready: 1, total: 1,
                label: ownership == .armory ? "Owned in Legendary Armory ✓" : "Owned in account holdings ✓",
                isAuthoritativeCompletion: ownership == .armory)
        }
        return GoalProgress(
            ready: topLevelReadyCount, total: max(topLevelTotalCount, 1),
            label: "\(topLevelReadyCount) / \(topLevelTotalCount) top-level requirements ready",
            isAuthoritativeCompletion: false)
    }

    var materialSummary: String {
        "\(materialSatisfiedCount) material requirements satisfied\n\(materialMissingCount) missing"
    }

    var coverageTitle: String { coverage == .complete ? "Complete" : "Partial" }
}

struct LegendaryBrowserItem: Identifiable, Hashable, Sendable {
    var id: Int { itemID }
    let itemID: Int
    let name: String
    let icon: URL?
    let category: LegendaryBrowserCategory
    let weaponType: String?
    let ownership: LegendaryOwnershipState
    let availability: LegendaryPlanAvailability
}
