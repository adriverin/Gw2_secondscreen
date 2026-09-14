import Foundation

enum KnowledgeSourceType: String, Codable, CaseIterable, Sendable {
    case arenaNetAPI
    case arenaNetOfficial
    case companionCurated
    case userDeclared
}

struct KnowledgeSource: Codable, Hashable, Sendable {
    let type: KnowledgeSourceType
    let sourceID: String?
    let sourceURL: URL?
    let reviewedAt: Date?
    let notes: String?

    var provenance: DataProvenance {
        switch type {
        case .arenaNetAPI, .arenaNetOfficial: .arenaNetPublic
        case .companionCurated: .companionObserved
        case .userDeclared: .userDeclared
        }
    }

    var displayTitle: String {
        switch type {
        case .arenaNetAPI: "ArenaNet API"
        case .arenaNetOfficial: "ArenaNet official"
        case .companionCurated: "Companion curated acquisition catalog"
        case .userDeclared: "User declared"
        }
    }
}

enum AcquisitionMethodType: String, Codable, CaseIterable, Identifiable, Sendable {
    case craft
    case tradingPost
    case gathering
    case vendor
    case achievement
    case mysticForge
    case mapCurrency
    case worldObjective
    case manual
    case unknown

    var id: Self { self }
    var title: String {
        switch self {
        case .craft: "Craft"
        case .tradingPost: "Trading Post"
        case .gathering: "Gather"
        case .vendor: "Vendor"
        case .achievement: "Achievement"
        case .mysticForge: "Mystic Forge"
        case .mapCurrency: "Map Currency"
        case .worldObjective: "World Objective"
        case .manual: "Manual"
        case .unknown: "Unknown"
        }
    }
}

enum AcquisitionTargetKind: String, Codable, Sendable {
    case item, currency, achievement, custom
}

/// A tagged structure keeps catalog JSON stable while allowing future target kinds.
struct AcquisitionTarget: Codable, Hashable, Sendable {
    let kind: AcquisitionTargetKind
    let numericID: Int?
    let quantity: Int
    let customID: String?

    static func item(id: Int, quantity: Int = 1) -> Self {
        .init(kind: .item, numericID: id, quantity: quantity, customID: nil)
    }
    static func currency(id: Int, quantity: Int = 1) -> Self {
        .init(kind: .currency, numericID: id, quantity: quantity, customID: nil)
    }
    static func achievement(id: Int) -> Self {
        .init(kind: .achievement, numericID: id, quantity: 1, customID: nil)
    }
    static func custom(_ id: String, quantity: Int = 1) -> Self {
        .init(kind: .custom, numericID: nil, quantity: quantity, customID: id)
    }

    var key: String {
        switch kind {
        case .item: "item:\(numericID ?? -1)"
        case .currency: "currency:\(numericID ?? -1)"
        case .achievement: "achievement:\(numericID ?? -1)"
        case .custom: "custom:\(customID ?? "")"
        }
    }

    func withQuantity(_ value: Int) -> Self {
        .init(kind: kind, numericID: numericID, quantity: value, customID: customID)
    }
}

enum AcquisitionRequirementKind: String, Codable, Sendable {
    case item, currency, achievement, map, craftingDiscipline, vendorInteraction, acquisition, manual
}

struct AcquisitionRequirement: Codable, Hashable, Sendable {
    let kind: AcquisitionRequirementKind
    let numericID: Int?
    let quantity: Int?
    let value: String?
    let rating: Int?

    static func item(id: Int, quantity: Int) -> Self {
        .init(kind: .item, numericID: id, quantity: quantity, value: nil, rating: nil)
    }
    static func currency(id: Int, quantity: Int) -> Self {
        .init(kind: .currency, numericID: id, quantity: quantity, value: nil, rating: nil)
    }
    static func achievement(id: Int) -> Self {
        .init(kind: .achievement, numericID: id, quantity: nil, value: nil, rating: nil)
    }
    static func map(id: Int) -> Self {
        .init(kind: .map, numericID: id, quantity: nil, value: nil, rating: nil)
    }
    static func craftingDiscipline(_ name: String, rating: Int) -> Self {
        .init(kind: .craftingDiscipline, numericID: nil, quantity: nil, value: name, rating: rating)
    }
    static func manual(_ description: String) -> Self {
        .init(kind: .manual, numericID: nil, quantity: nil, value: description, rating: nil)
    }
}

struct CurrencyCost: Codable, Hashable, Sendable {
    let currencyID: Int
    let quantity: Int
}

struct ItemCost: Codable, Hashable, Sendable {
    let itemID: Int
    let quantity: Int
}

struct AcquisitionCost: Codable, Hashable, Sendable {
    let coinCopper: Int64?
    let currencies: [CurrencyCost]
    let items: [ItemCost]

    static let none = AcquisitionCost(coinCopper: nil, currencies: [], items: [])
}

enum LocationPrecision: String, Codable, Sendable {
    case exactCoordinate, mapOnly, objectiveReference, unknown
}

struct AcquisitionLocation: Codable, Hashable, Sendable {
    let mapID: Int?
    let continentX: Double?
    let continentY: Double?
    let objectiveID: MapObjectiveID?
    let label: String?
    let locationPrecision: LocationPrecision
}

enum AcquisitionConfidence: String, Codable, CaseIterable, Sendable {
    case verified, strong, limited, userProvided, unknown
}

enum KnowledgeCoverage: String, Codable, CaseIterable, Sendable {
    case complete, partial, exampleOnly
}

struct AcquisitionMethod: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let target: AcquisitionTarget
    let type: AcquisitionMethodType
    let title: String
    let description: String?
    let requirements: [AcquisitionRequirement]
    let location: AcquisitionLocation?
    let cost: AcquisitionCost?
    let source: KnowledgeSource
    let confidence: AcquisitionConfidence
    let coverage: KnowledgeCoverage
    /// Optional bridge to the current bundled gathering marker taxonomy.
    let gatheringCategory: GatheringCategory?
    let markerSubtype: String?
}

struct AcquisitionCatalog: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let catalogVersion: String
    let lastReviewedAt: Date
    let coverage: KnowledgeCoverage
    let methods: [AcquisitionMethod]
}

enum AcquisitionCatalogValidationIssue: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case emptyCatalogVersion
    case duplicateMethodID(String)
    case invalidTarget(String)
    case invalidRequirement(methodID: String)
    case invalidCost(methodID: String)
    case invalidLocation(methodID: String)
    case unknownMap(methodID: String, mapID: Int)
    case missingProvenance(methodID: String)
    case directCycle(methodID: String)

    var description: String {
        switch self {
        case let .unsupportedSchema(value): "Unsupported acquisition schema \(value)"
        case .emptyCatalogVersion: "Catalog version is empty"
        case let .duplicateMethodID(id): "Duplicate acquisition method ID: \(id)"
        case let .invalidTarget(id): "Invalid target in \(id)"
        case let .invalidRequirement(id): "Invalid requirement in \(id)"
        case let .invalidCost(id): "Invalid cost in \(id)"
        case let .invalidLocation(id): "Invalid location in \(id)"
        case let .unknownMap(id, mapID): "Unknown map \(mapID) in \(id)"
        case let .missingProvenance(id): "Missing provenance in \(id)"
        case let .directCycle(id): "Direct acquisition cycle in \(id)"
        }
    }
}

enum AcquisitionCatalogValidator {
    static let schemaVersion = 1

    static func validate(_ catalog: AcquisitionCatalog, knownMapIDs: Set<Int>? = nil) -> [AcquisitionCatalogValidationIssue] {
        var issues: [AcquisitionCatalogValidationIssue] = []
        if catalog.schemaVersion != schemaVersion { issues.append(.unsupportedSchema(catalog.schemaVersion)) }
        if catalog.catalogVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyCatalogVersion) }
        var seen: Set<String> = []
        for method in catalog.methods {
            if method.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !seen.insert(method.id).inserted {
                issues.append(.duplicateMethodID(method.id))
            }
            if !valid(method.target) { issues.append(.invalidTarget(method.id)) }
            if method.requirements.contains(where: { !valid($0) }) { issues.append(.invalidRequirement(methodID: method.id)) }
            if let cost = method.cost,
               cost.coinCopper.map({ $0 < 0 }) == true || cost.currencies.contains(where: { $0.currencyID <= 0 || $0.quantity <= 0 }) ||
               cost.items.contains(where: { $0.itemID <= 0 || $0.quantity <= 0 }) {
                issues.append(.invalidCost(methodID: method.id))
            }
            if let location = method.location {
                let oneCoordinate = (location.continentX == nil) != (location.continentY == nil)
                let coordinateWithoutMap = location.continentX != nil && location.mapID == nil
                let precisionMismatch = location.locationPrecision == .exactCoordinate && location.continentX == nil
                if oneCoordinate || coordinateWithoutMap || precisionMismatch || location.mapID.map({ $0 <= 0 }) == true {
                    issues.append(.invalidLocation(methodID: method.id))
                }
                if let knownMapIDs, let mapID = location.mapID, !knownMapIDs.contains(mapID) {
                    issues.append(.unknownMap(methodID: method.id, mapID: mapID))
                }
            }
            if method.source.type == .companionCurated,
               method.source.sourceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.missingProvenance(methodID: method.id))
            }
            if method.requirements.contains(where: { $0.kind == .acquisition && $0.value == method.id }) {
                issues.append(.directCycle(methodID: method.id))
            }
        }
        return issues
    }

    private static func valid(_ target: AcquisitionTarget) -> Bool {
        guard target.quantity > 0 else { return false }
        switch target.kind {
        case .item, .currency, .achievement: return target.numericID.map { $0 > 0 } == true && target.customID == nil
        case .custom: return target.numericID == nil && !(target.customID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private static func valid(_ requirement: AcquisitionRequirement) -> Bool {
        switch requirement.kind {
        case .item, .currency:
            return requirement.numericID.map { $0 > 0 } == true && requirement.quantity.map { $0 > 0 } == true
        case .achievement, .map:
            return requirement.numericID.map { $0 > 0 } == true
        case .craftingDiscipline:
            return !(requirement.value?.isEmpty ?? true) && requirement.rating.map { $0 >= 0 } == true
        case .vendorInteraction, .acquisition, .manual:
            return !(requirement.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}
