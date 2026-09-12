import Foundation

struct TokenInfo: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let permissions: [String]
}

struct GW2Character: Codable, Sendable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let race: String
    let gender: String
    let profession: String
    let level: Int
    let age: Int
}

struct InventoryBag: Codable, Sendable {
    let id: Int?
    let size: Int?
    let inventory: [InventorySlot?]?
}

struct CharacterInventoryResponse: Codable, Sendable {
    let bags: [InventoryBag?]
}

struct InventorySlot: Codable, Sendable {
    let id: Int
    let count: Int
}

struct AccountMaterial: Codable, Sendable {
    let id: Int
    let category: Int
    let count: Int
}

struct WalletEntry: Codable, Sendable { let id: Int; let value: Int }

struct ItemMetadata: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let icon: URL?
    let rarity: String
}

struct CurrencyMetadata: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let icon: URL?
}

struct GW2MapMetadata: Codable, Sendable, Equatable {
    let id: Int
    let name: String
    let continentId: Int
    let defaultFloor: Int
    let mapRect: [[Double]]
    let continentRect: [[Double]]

    enum CodingKeys: String, CodingKey {
        case id, name
        case continentId = "continent_id"
        case defaultFloor = "default_floor"
        case mapRect = "map_rect"
        case continentRect = "continent_rect"
    }
}

enum InventorySource: String, CaseIterable, Identifiable {
    case character = "Character"
    case bank = "Bank"
    case shared = "Shared"
    case materials = "Materials"
    var id: Self { self }
}

struct DisplayInventoryItem: Identifiable, Sendable {
    let metadata: ItemMetadata
    let quantity: Int
    var id: Int { metadata.id }
}
