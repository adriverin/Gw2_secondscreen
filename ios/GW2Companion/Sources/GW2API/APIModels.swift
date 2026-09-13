import Foundation

struct TokenInfo: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let permissions: [String]
}

struct GW2Account: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let world: Int
    let created: String
    let commander: Bool?
    let fractalLevel: Int?
    let dailyAP: Int?
    let monthlyAP: Int?
    let wvwRank: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, world, created, commander
        case fractalLevel = "fractal_level"
        case dailyAP = "daily_ap"
        case monthlyAP = "monthly_ap"
        case wvwRank = "wvw_rank"
    }
}

struct GW2World: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let population: String?
}

struct CraftingDiscipline: Codable, Sendable, Equatable {
    let discipline: String
    let rating: Int
    let active: Bool
}

struct GW2Character: Codable, Sendable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let race: String
    let gender: String
    let profession: String
    let level: Int
    let age: Int
    var created: String? = nil
    var deaths: Int? = nil
    var crafting: [CraftingDiscipline]? = nil
    var equipment: [CharacterEquipment]? = nil
    var bags: [InventoryBag?]? = nil
    var activeBuildTab: Int? = nil
    var activeEquipmentTab: Int? = nil

    enum CodingKeys: String, CodingKey {
        case name, race, gender, profession, level, age, created, deaths, crafting, equipment, bags
        case activeBuildTab = "active_build_tab"
        case activeEquipmentTab = "active_equipment_tab"
    }
}

struct InventoryBag: Codable, Sendable, Equatable {
    let id: Int?
    let size: Int?
    let inventory: [InventorySlot?]?
}

struct CharacterInventoryResponse: Codable, Sendable, Equatable {
    let bags: [InventoryBag?]
}

struct InventorySlot: Codable, Sendable, Equatable {
    let id: Int
    let count: Int
    var charges: Int? = nil
    var skin: Int? = nil
    var upgrades: [Int]? = nil
    var upgradeSlotIndices: [Int]? = nil
    var infusions: [Int]? = nil
    var binding: String? = nil
    var boundTo: String? = nil
    var stats: SelectedItemStats? = nil

    enum CodingKeys: String, CodingKey {
        case id, count, charges, skin, upgrades, infusions, binding, stats
        case upgradeSlotIndices = "upgrade_slot_indices"
        case boundTo = "bound_to"
    }
}

struct SelectedItemStats: Codable, Sendable, Equatable {
    let id: Int?
    let attributes: [String: Int]?
}

struct CharacterEquipment: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(slot)-\(itemID)-\(location ?? "equipped")" }
    let itemID: Int
    let slot: String
    var infusions: [Int]? = nil
    var upgrades: [Int]? = nil
    var skin: Int? = nil
    var stats: SelectedItemStats? = nil
    var binding: String? = nil
    var boundTo: String? = nil
    var location: String? = nil

    enum CodingKeys: String, CodingKey {
        case slot, infusions, upgrades, skin, stats, binding, location
        case itemID = "id"
        case boundTo = "bound_to"
    }
}

struct EquipmentTab: Codable, Sendable, Identifiable, Equatable {
    var id: Int { tab }
    let tab: Int
    let name: String
    let isActive: Bool
    let equipment: [CharacterEquipment]

    enum CodingKeys: String, CodingKey {
        case tab, name, equipment
        case isActive = "is_active"
    }
}

struct BuildTab: Codable, Sendable, Identifiable, Equatable {
    var id: Int { tab }
    let tab: Int
    let name: String
    let isActive: Bool
    let build: CharacterBuild

    enum CodingKeys: String, CodingKey {
        case tab, name, build
        case isActive = "is_active"
    }
}

struct CharacterBuild: Codable, Sendable, Equatable {
    let name: String?
    let profession: String
    let specializations: [BuildSpecialization]
    let skills: BuildSkillModes
}

struct BuildSpecialization: Codable, Sendable, Equatable {
    let id: Int?
    let traits: [Int?]
}

struct BuildSkillModes: Codable, Sendable, Equatable {
    let terrestrial: BuildSkills?
    let aquatic: BuildSkills?
    let pve: BuildSkills?
    let pvp: BuildSkills?
    let wvw: BuildSkills?
}

struct BuildSkills: Codable, Sendable, Equatable {
    let heal: Int?
    let utilities: [Int?]
    let elite: Int?
}

struct AccountMaterial: Codable, Sendable, Equatable {
    let id: Int
    let category: Int
    let count: Int
    var binding: String? = nil
}

struct WalletEntry: Codable, Sendable, Equatable, Identifiable { let id: Int; let value: Int }

struct CoinAmount: Equatable, Sendable {
    let gold: Int
    let silver: Int
    let copper: Int

    init(gold: Int, silver: Int, copper: Int) {
        self.gold = gold
        self.silver = silver
        self.copper = copper
    }

    init(copperValue: Int) {
        let value = max(0, copperValue)
        self.init(gold: value / 10_000, silver: value % 10_000 / 100, copper: value % 100)
    }

    var accessibilityLabel: String { "\(gold) gold, \(silver) silver, \(copper) copper" }
}

struct ItemMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let rarity: String
    var description: String? = nil
    var type: String? = nil
    var level: Int? = nil
    var flags: [String]? = nil
    var restrictions: [String]? = nil
    var details: ItemDetails? = nil
}

struct ItemDetails: Codable, Sendable, Equatable {
    var type: String? = nil
    var weightClass: String? = nil
    var defense: Int? = nil
    var damageType: String? = nil
    var minPower: Int? = nil
    var maxPower: Int? = nil
    var infusionSlots: [InfusionSlot]? = nil
    var infixUpgrade: InfixUpgrade? = nil
    var suffixItemID: Int? = nil
    var secondarySuffixItemID: Int? = nil
    var statChoices: [Int]? = nil

    enum CodingKeys: String, CodingKey {
        case type, defense
        case weightClass = "weight_class"
        case damageType = "damage_type"
        case minPower = "min_power"
        case maxPower = "max_power"
        case infusionSlots = "infusion_slots"
        case infixUpgrade = "infix_upgrade"
        case suffixItemID = "suffix_item_id"
        case secondarySuffixItemID = "secondary_suffix_item_id"
        case statChoices = "stat_choices"
    }
}

struct InfusionSlot: Codable, Sendable, Equatable {
    let flags: [String]
    let itemID: Int?
    enum CodingKeys: String, CodingKey { case flags; case itemID = "item_id" }
}

struct InfixUpgrade: Codable, Sendable, Equatable {
    let id: Int?
    let attributes: [ItemAttribute]
    let buff: ItemBuff?
}

struct ItemAttribute: Codable, Sendable, Equatable, Identifiable {
    var id: String { attribute }
    let attribute: String
    let modifier: Int
}

struct ItemBuff: Codable, Sendable, Equatable {
    let skillID: Int?
    let description: String?
    enum CodingKeys: String, CodingKey { case description; case skillID = "skill_id" }
}

struct CurrencyMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let icon: URL?
    var order: Int? = nil
}

struct ProfessionMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: URL?
    let iconBig: URL?
    let specializations: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, specializations
        case iconBig = "icon_big"
    }
}

struct SpecializationMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let profession: String
    let elite: Bool
    let icon: URL?
    let background: URL?
    let minorTraits: [Int]
    let majorTraits: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name, profession, elite, icon, background
        case minorTraits = "minor_traits"
        case majorTraits = "major_traits"
    }
}

struct TraitMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let description: String
    let tier: Int?
    let slot: String?
}

struct SkillMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let description: String
    let type: String?
    let weaponType: String?
    let slot: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, description, type, slot
        case weaponType = "weapon_type"
    }
}

struct SkinMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let rarity: String?
    let description: String?
}

struct MaterialCategoryMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let items: [Int]
    let order: Int
}

struct GW2MapMetadata: Codable, Sendable, Equatable {
    let id: Int
    let name: String
    let continentId: Int
    let defaultFloor: Int
    let mapRect: [[Double]]
    let continentRect: [[Double]]
    var regionId: Int? = nil
    var floors: [Int]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name
        case continentId = "continent_id"
        case defaultFloor = "default_floor"
        case mapRect = "map_rect"
        case continentRect = "continent_rect"
        case regionId = "region_id"
        case floors
    }
}

enum InventorySource: String, CaseIterable, Identifiable {
    case character = "Character"
    case bank = "Bank"
    case shared = "Shared"
    case materials = "Materials"
    var id: Self { self }
}

struct DisplayInventoryItem: Identifiable, Sendable, Equatable {
    let metadata: ItemMetadata
    let quantity: Int
    let slot: InventorySlot?
    var id: Int { metadata.id }

    init(metadata: ItemMetadata, quantity: Int, slot: InventorySlot? = nil) {
        self.metadata = metadata
        self.quantity = quantity
        self.slot = slot
    }
}
