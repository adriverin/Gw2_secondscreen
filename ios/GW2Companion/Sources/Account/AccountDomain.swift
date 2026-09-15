import Foundation

enum AccountPermission: String, CaseIterable, Codable, Sendable, Identifiable {
    case account
    case characters
    case inventories
    case builds
    case wallet
    case progression
    case unlocks
    case tradingPost = "tradingpost"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tradingPost: "Trading Post"
        default: rawValue.capitalized
        }
    }
}

struct PermissionSet: Equatable, Sendable {
    private let values: Set<String>
    init(_ values: [String]) { self.values = Set(values.map { $0.lowercased() }) }
    func contains(_ permission: AccountPermission) -> Bool { values.contains(permission.rawValue) }
}

enum ItemLocation: Hashable, Codable, Sendable, Identifiable {
    case character(String)
    case bank
    case sharedInventory
    case materialStorage

    var id: String {
        switch self {
        case let .character(name): "character:\(name)"
        case .bank: "bank"
        case .sharedInventory: "shared"
        case .materialStorage: "materials"
        }
    }

    var title: String {
        switch self {
        case let .character(name): name
        case .bank: "Bank"
        case .sharedInventory: "Shared Inventory"
        case .materialStorage: "Material Storage"
        }
    }
}

struct HoldingLocation: Hashable, Codable, Sendable, Identifiable {
    let location: ItemLocation
    let quantity: Int
    var id: String { location.id }
}

struct AccountHolding: Identifiable, Equatable, Codable, Sendable {
    var id: Int { itemID }
    let itemID: Int
    let totalQuantity: Int
    let locations: [HoldingLocation]
}

enum AccountHoldingAggregator {
    static func aggregate(_ sources: [(ItemLocation, [InventorySlot])]) -> [AccountHolding] {
        var quantities: [Int: [ItemLocation: Int]] = [:]
        for (location, slots) in sources {
            for slot in slots where slot.count > 0 {
                quantities[slot.id, default: [:]][location, default: 0] += slot.count
            }
        }
        return quantities.map { itemID, locations in
            let values = locations.map { HoldingLocation(location: $0.key, quantity: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.quantity != rhs.quantity { return lhs.quantity > rhs.quantity }
                    return lhs.location.title.localizedCaseInsensitiveCompare(rhs.location.title) == .orderedAscending
                }
            return AccountHolding(
                itemID: itemID,
                totalQuantity: values.reduce(0) { $0 + $1.quantity },
                locations: values)
        }
        .sorted { $0.itemID < $1.itemID }
    }
}

struct HoldingSearchResult: Identifiable, Equatable, Sendable {
    var id: Int { holding.itemID }
    let holding: AccountHolding
    let item: ItemMetadata
}

enum HoldingSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case quantity = "Quantity"
    case rarity = "Rarity"
    var id: Self { self }
}

enum HoldingSearch {
    static func results(
        holdings: [AccountHolding], metadata: [Int: ItemMetadata], query: String, sort: HoldingSort
    ) -> [HoldingSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = holdings.compactMap { holding -> HoldingSearchResult? in
            let item = metadata[holding.itemID] ?? ItemPlaceholder.metadata(id: holding.itemID)
            guard normalized.isEmpty || item.name.localizedCaseInsensitiveContains(normalized) || String(holding.itemID) == normalized else { return nil }
            return HoldingSearchResult(holding: holding, item: item)
        }
        return values.sorted { lhs, rhs in
            switch sort {
            case .name:
                lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
            case .quantity:
                lhs.holding.totalQuantity == rhs.holding.totalQuantity
                    ? lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
                    : lhs.holding.totalQuantity > rhs.holding.totalQuantity
            case .rarity:
                rarityRank(lhs.item.rarity) == rarityRank(rhs.item.rarity)
                    ? lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
                    : rarityRank(lhs.item.rarity) > rarityRank(rhs.item.rarity)
            }
        }
    }

    private static func rarityRank(_ rarity: String) -> Int {
        ["junk", "basic", "fine", "masterwork", "rare", "exotic", "ascended", "legendary"]
            .firstIndex(of: rarity.lowercased()) ?? 0
    }
}

enum CurrentCharacterMatcher {
    static func match(liveName: String?, characters: [GW2Character]) -> GW2Character? {
        guard let name = liveName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if let exact = characters.first(where: { $0.name == name }) { return exact }
        let insensitive = characters.filter { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }
        return insensitive.count == 1 ? insensitive[0] : nil
    }
}

struct AccountSummary: Codable, Equatable, Sendable {
    let characterCount: Int
    let totalPlaytime: TimeInterval
    let totalDeaths: Int
    let maxLevelCharacterCount: Int
    let occupiedInventorySlots: Int
    let uniqueItemCount: Int

    init(characters: [GW2Character], holdings: [AccountHolding]) {
        characterCount = characters.count
        totalPlaytime = TimeInterval(characters.reduce(0) { $0 + $1.age })
        totalDeaths = characters.reduce(0) { $0 + ($1.deaths ?? 0) }
        maxLevelCharacterCount = characters.filter { $0.level == 80 }.count
        occupiedInventorySlots = holdings.reduce(0) { result, holding in result + holding.locations.count }
        uniqueItemCount = holdings.count
    }
}

struct CharacterEquipmentStats: Equatable, Sendable {
    let attributes: [String: Int]
}

struct CharacterDetailData: Equatable, Sendable, Codable {
    var equipmentTabs: [EquipmentTab] = []
    var buildTabs: [BuildTab] = []
    var inventory: CharacterInventoryResponse?
    var items: [Int: ItemMetadata] = [:]
    var skins: [Int: SkinMetadata] = [:]
    var specializations: [Int: SpecializationMetadata] = [:]
    var traits: [Int: TraitMetadata] = [:]
    var skills: [Int: SkillMetadata] = [:]
    var errorMessage: String?
    var equipmentError: String?
    var buildError: String?
    var inventoryError: String?
    var updatedAt: Date? = nil
    var source: AccountDataSource? = nil
}

extension GW2Character {
    var formattedPlaytime: String {
        let hours = age / 3_600
        return hours < 1_000 ? "\(hours) h" : "\(hours.formatted()) h"
    }

    var creationYear: String? { created.flatMap { String($0.prefix(4)) } }
}

extension String {
    var readableGW2Attribute: String {
        switch self {
        case "ConditionDamage": "Condition Damage"
        case "HealingPower": "Healing Power"
        default: replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }

    var strippingSimpleHTML: String {
        replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
