import Foundation

protocol AcquisitionCatalogProvider: Sendable {
    func catalog() async throws -> AcquisitionCatalog
}

struct BundledCatalogProvider: AcquisitionCatalogProvider {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "acquisition-catalog-v1") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func catalog() async throws -> AcquisitionCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AcquisitionCatalog.self, from: Data(contentsOf: url))
    }
}

enum AcquisitionKnowledgeError: Error, LocalizedError {
    case invalidCatalog([AcquisitionCatalogValidationIssue])

    var errorDescription: String? {
        switch self {
        case let .invalidCatalog(issues): issues.map(\.description).joined(separator: "; ")
        }
    }
}

/// Authoritative acquisition-query layer. Bundled, API-derived, and user-declared data remain
/// separate internally so a catalog update can never overwrite a user's additions.
actor AcquisitionKnowledgeStore {
    private var bundled: [String: AcquisitionMethod] = [:]
    private var apiDerived: [String: AcquisitionMethod] = [:]
    private var userDeclared: [String: AcquisitionMethod] = [:]
    private var byTarget: [String: [AcquisitionMethod]] = [:]
    private(set) var catalogMetadata: AcquisitionCatalog?

    func load(provider: any AcquisitionCatalogProvider) async throws {
        let catalog = try await provider.catalog()
        let issues = AcquisitionCatalogValidator.validate(catalog)
        guard issues.isEmpty else { throw AcquisitionKnowledgeError.invalidCatalog(issues) }
        bundled = Dictionary(uniqueKeysWithValues: catalog.methods.map { ($0.id, $0) })
        catalogMetadata = catalog
        rebuildIndex()
    }

    func replaceAPIDerived(with methods: [AcquisitionMethod]) {
        apiDerived = Dictionary(uniqueKeysWithValues: methods.map { ($0.id, $0) })
        rebuildIndex()
    }

    func replaceUserDeclared(with methods: [AcquisitionMethod]) {
        userDeclared = Dictionary(uniqueKeysWithValues: methods.map { ($0.id, $0) })
        rebuildIndex()
    }

    func addUserDeclared(_ method: AcquisitionMethod) {
        userDeclared[method.id] = method
        rebuildIndex()
    }

    func methods(for target: AcquisitionTarget) -> [AcquisitionMethod] {
        byTarget[target.key] ?? []
    }

    func allMethods() -> [AcquisitionMethod] {
        byTarget.values.flatMap { $0 }.sorted { $0.id < $1.id }
    }

    private func rebuildIndex() {
        // Explicit precedence: user > API-derived > bundled for an identical stable ID.
        var merged = bundled
        apiDerived.forEach { merged[$0.key] = $0.value }
        userDeclared.forEach { merged[$0.key] = $0.value }
        byTarget = Dictionary(grouping: merged.values, by: { $0.target.key })
            .mapValues { $0.sorted { lhs, rhs in
                if lhs.type.rawValue != rhs.type.rawValue { return lhs.type.rawValue < rhs.type.rawValue }
                return lhs.id < rhs.id
            } }
    }
}

enum AcquisitionMethodFactory {
    static func apiDerived(
        recipes: [Int: RecipeDefinition], prices: [Int: TimedCommercePrice]
    ) -> [AcquisitionMethod] {
        var methods: [AcquisitionMethod] = []
        let source = KnowledgeSource(
            type: .arenaNetAPI, sourceID: "api.guildwars2.com/v2", sourceURL: URL(string: "https://api.guildwars2.com/v2"),
            reviewedAt: nil, notes: "Generated from currently loaded public API records.")
        for recipe in recipes.values.sorted(by: { $0.id < $1.id }) {
            guard let itemID = recipe.outputItemID, recipe.outputItemCount > 0 else { continue }
            let requirements = recipe.ingredients.compactMap { ingredient -> AcquisitionRequirement? in
                switch ingredient.knownType {
                case .item: .item(id: ingredient.id, quantity: ingredient.count)
                case .currency: .currency(id: ingredient.id, quantity: ingredient.count)
                case .guildUpgrade, .unknown: nil
                }
            }
            methods.append(AcquisitionMethod(
                id: "api:recipe:\(recipe.id)", target: .item(id: itemID, quantity: recipe.outputItemCount),
                type: .craft, title: "Craft with recipe \(recipe.id)",
                description: "ArenaNet recipe output; discipline and unlock readiness are checked separately.",
                requirements: requirements, location: nil, cost: nil, source: source,
                confidence: .verified, coverage: .partial, gatheringCategory: nil, markerSubtype: nil))
        }
        for (itemID, price) in prices.sorted(by: { $0.key < $1.key })
        where price.price.sells.quantity > 0 && price.price.sells.unitPrice > 0 {
            methods.append(AcquisitionMethod(
                id: "api:trading-post:\(itemID)", target: .item(id: itemID), type: .tradingPost,
                title: "Buy on the Trading Post", description: "A current lowest sell offer is available.",
                requirements: [], location: nil,
                cost: AcquisitionCost(coinCopper: Int64(price.price.sells.unitPrice), currencies: [], items: []),
                source: source, confidence: .verified, coverage: .partial,
                gatheringCategory: nil, markerSubtype: nil))
        }
        return methods
    }
}

extension AcquisitionMethod {
    var phaseFourOption: AcquisitionOption {
        let optionType: AcquisitionOptionType = switch type {
        case .craft: .craft
        case .tradingPost: .buy
        case .gathering: .gather
        case .manual, .unknown: .manual
        default: .manual
        }
        return AcquisitionOption(
            type: optionType, title: title,
            reason: description ?? "Available through the acquisition knowledge catalog.",
            provenance: [source.provenance])
    }
}
