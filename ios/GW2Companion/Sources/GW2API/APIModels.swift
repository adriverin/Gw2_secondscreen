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

    enum CodingKeys: String, CodingKey { case id, size, inventory }

    init(id: Int?, size: Int?, inventory: [InventorySlot?]?) {
        self.id = id
        self.size = size
        self.inventory = inventory
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id)
        size = try values.decodeIfPresent(Int.self, forKey: .size)
        if let slots = try? values.decodeIfPresent(SparseNullableArray<InventorySlot>.self, forKey: .inventory) {
            inventory = slots.values
        } else {
            inventory = try? values.decodeIfPresent([InventorySlot?].self, forKey: .inventory)
        }
    }
}

struct CharacterInventoryResponse: Codable, Sendable, Equatable {
    let bags: [InventoryBag?]

    enum CodingKeys: String, CodingKey { case bags }

    init(bags: [InventoryBag?]) { self.bags = bags }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bags = (try? values.decode(SparseNullableArray<InventoryBag>.self, forKey: .bags))?.values ?? []
    }
}

struct InventorySlot: Codable, Sendable, Equatable {
    let id: Int
    let count: Int
    var charges: Int? = nil
    var skin: Int? = nil
    var upgrades: [Int]? = nil
    var upgradeSlotIndices: [Int]? = nil
    var infusions: [Int]? = nil
    var dyes: [Int]? = nil
    var binding: String? = nil
    var boundTo: String? = nil
    var stats: SelectedItemStats? = nil

    enum CodingKeys: String, CodingKey {
        case id, count, charges, skin, upgrades, infusions, dyes, binding, stats
        case upgradeSlotIndices = "upgrade_slot_indices"
        case boundTo = "bound_to"
    }

    init(
        id: Int, count: Int, charges: Int? = nil, skin: Int? = nil,
        upgrades: [Int]? = nil, upgradeSlotIndices: [Int]? = nil, infusions: [Int]? = nil,
        dyes: [Int]? = nil, binding: String? = nil, boundTo: String? = nil, stats: SelectedItemStats? = nil
    ) {
        self.id = id
        self.count = count
        self.charges = charges
        self.skin = skin
        self.upgrades = upgrades
        self.upgradeSlotIndices = upgradeSlotIndices
        self.infusions = infusions
        self.dyes = dyes
        self.binding = binding
        self.boundTo = boundTo
        self.stats = stats
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? 1
        charges = try values.decodeIfPresent(Int.self, forKey: .charges)
        skin = try values.decodeIfPresent(Int.self, forKey: .skin)
        upgrades = values.decodeCompactInts(forKey: .upgrades)
        upgradeSlotIndices = values.decodeCompactInts(forKey: .upgradeSlotIndices)
        infusions = values.decodeCompactInts(forKey: .infusions)
        dyes = values.decodeCompactInts(forKey: .dyes)
        binding = try values.decodeIfPresent(String.self, forKey: .binding)
        boundTo = try values.decodeIfPresent(String.self, forKey: .boundTo)
        stats = try values.decodeIfPresent(SelectedItemStats.self, forKey: .stats)
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
    var dyes: [Int]? = nil
    var skin: Int? = nil
    var stats: SelectedItemStats? = nil
    var binding: String? = nil
    var boundTo: String? = nil
    var location: String? = nil

    enum CodingKeys: String, CodingKey {
        case slot, infusions, upgrades, dyes, skin, stats, binding, location
        case itemID = "id"
        case boundTo = "bound_to"
    }

    init(
        itemID: Int, slot: String, infusions: [Int]? = nil, upgrades: [Int]? = nil,
        dyes: [Int]? = nil, skin: Int? = nil, stats: SelectedItemStats? = nil,
        binding: String? = nil, boundTo: String? = nil, location: String? = nil
    ) {
        self.itemID = itemID
        self.slot = slot
        self.infusions = infusions
        self.upgrades = upgrades
        self.dyes = dyes
        self.skin = skin
        self.stats = stats
        self.binding = binding
        self.boundTo = boundTo
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try values.decode(Int.self, forKey: .itemID)
        slot = try values.decodeIfPresent(String.self, forKey: .slot) ?? "Unknown"
        infusions = values.decodeCompactInts(forKey: .infusions)
        upgrades = values.decodeCompactInts(forKey: .upgrades)
        dyes = values.decodeCompactInts(forKey: .dyes)
        skin = try values.decodeIfPresent(Int.self, forKey: .skin)
        stats = try values.decodeIfPresent(SelectedItemStats.self, forKey: .stats)
        binding = try values.decodeIfPresent(String.self, forKey: .binding)
        boundTo = try values.decodeIfPresent(String.self, forKey: .boundTo)
        location = try values.decodeIfPresent(String.self, forKey: .location)
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

    init(tab: Int, name: String, isActive: Bool, equipment: [CharacterEquipment]) {
        self.tab = tab
        self.name = name
        self.isActive = isActive
        self.equipment = equipment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tab = try values.decode(Int.self, forKey: .tab)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Tab \(tab)"
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        equipment = values.decodeLossyArray(CharacterEquipment.self, forKey: .equipment)
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

    init(tab: Int, name: String, isActive: Bool, build: CharacterBuild) {
        self.tab = tab
        self.name = name
        self.isActive = isActive
        self.build = build
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tab = try values.decode(Int.self, forKey: .tab)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Tab \(tab)"
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        build = try values.decode(CharacterBuild.self, forKey: .build)
    }
}

struct CharacterBuild: Codable, Sendable, Equatable {
    let name: String?
    let profession: String
    let specializations: [BuildSpecialization]
    let skills: BuildSkillModes

    enum CodingKeys: String, CodingKey {
        case name, profession, specializations, skills
    }

    init(name: String?, profession: String, specializations: [BuildSpecialization], skills: BuildSkillModes) {
        self.name = name
        self.profession = profession
        self.specializations = specializations
        self.skills = skills
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        profession = try values.decodeIfPresent(String.self, forKey: .profession) ?? "Unknown"
        specializations = values.decodeLossyArray(BuildSpecialization.self, forKey: .specializations)
        skills = (try? values.decode(BuildSkillModes.self, forKey: .skills)) ?? .empty
    }
}

struct BuildSpecialization: Codable, Sendable, Equatable {
    let id: Int?
    let traits: [Int?]

    enum CodingKeys: String, CodingKey { case id, traits }

    init(id: Int?, traits: [Int?]) {
        self.id = id
        self.traits = traits
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id)
        if let compact = try? values.decodeIfPresent([OptionalIntBox].self, forKey: .traits) {
            traits = compact.map(\.value)
        } else {
            traits = (try? values.decodeIfPresent([Int?].self, forKey: .traits)) ?? []
        }
    }
}

private struct OptionalIntBox: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = container.decodeNil() ? nil : (try? container.decode(Int.self))
    }
}

struct BuildSkillModes: Codable, Sendable, Equatable {
    let terrestrial: BuildSkills?
    let aquatic: BuildSkills?
    let pve: BuildSkills?
    let pvp: BuildSkills?
    let wvw: BuildSkills?

    static let empty = BuildSkillModes(terrestrial: nil, aquatic: nil, pve: nil, pvp: nil, wvw: nil)
}

struct BuildSkills: Codable, Sendable, Equatable {
    let heal: Int?
    let utilities: [Int?]
    let elite: Int?

    enum CodingKeys: String, CodingKey { case heal, utilities, elite }

    init(heal: Int?, utilities: [Int?], elite: Int?) {
        self.heal = heal
        self.utilities = utilities
        self.elite = elite
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        heal = try values.decodeIfPresent(Int.self, forKey: .heal)
        elite = try values.decodeIfPresent(Int.self, forKey: .elite)
        if let boxed = try? values.decodeIfPresent([OptionalIntBox].self, forKey: .utilities) {
            utilities = boxed.map(\.value)
        } else {
            utilities = (try? values.decodeIfPresent([Int?].self, forKey: .utilities)) ?? []
        }
    }
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

    init(copperValue: Int64) {
        self.init(copperValue: Int(clamping: copperValue))
    }

    var totalCopper: Int64 { Int64(gold) * 10_000 + Int64(silver) * 100 + Int64(copper) }
    var formatted: String { "\(gold)g \(silver)s \(copper)c" }

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

    enum CodingKeys: String, CodingKey {
        case id, name, icon, rarity, description, type, level, flags, restrictions, details
    }

    init(
        id: Int, name: String, icon: URL?, rarity: String, description: String? = nil,
        type: String? = nil, level: Int? = nil, flags: [String]? = nil,
        restrictions: [String]? = nil, details: ItemDetails? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.rarity = rarity
        self.description = description
        self.type = type
        self.level = level
        self.flags = flags
        self.restrictions = restrictions
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Item \(id)"
        icon = values.decodeFlexibleURL(forKey: .icon)
        rarity = try values.decodeIfPresent(String.self, forKey: .rarity) ?? "Unknown"
        description = try values.decodeIfPresent(String.self, forKey: .description)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        level = try values.decodeIfPresent(Int.self, forKey: .level)
        flags = try values.decodeIfPresent([String].self, forKey: .flags)
        restrictions = try values.decodeIfPresent([String].self, forKey: .restrictions)
        details = try? values.decodeIfPresent(ItemDetails.self, forKey: .details)
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, order
    }

    init(id: Int, name: String, description: String, icon: URL?, order: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Currency \(id)"
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        icon = values.decodeFlexibleURL(forKey: .icon)
        order = try values.decodeIfPresent(Int.self, forKey: .order)
    }
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

    init(id: String, name: String, icon: URL?, iconBig: URL?, specializations: [Int]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.iconBig = iconBig
        self.specializations = specializations
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? id
        icon = values.decodeFlexibleURL(forKey: .icon)
        iconBig = values.decodeFlexibleURL(forKey: .iconBig)
        specializations = values.decodeCompactInts(forKey: .specializations) ?? []
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

    init(
        id: Int, name: String, profession: String, elite: Bool, icon: URL?, background: URL?,
        minorTraits: [Int], majorTraits: [Int]
    ) {
        self.id = id
        self.name = name
        self.profession = profession
        self.elite = elite
        self.icon = icon
        self.background = background
        self.minorTraits = minorTraits
        self.majorTraits = majorTraits
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Specialization \(id)"
        profession = try values.decodeIfPresent(String.self, forKey: .profession) ?? ""
        elite = try values.decodeIfPresent(Bool.self, forKey: .elite) ?? false
        icon = values.decodeFlexibleURL(forKey: .icon)
        background = values.decodeFlexibleURL(forKey: .background)
        minorTraits = values.decodeCompactInts(forKey: .minorTraits) ?? []
        majorTraits = values.decodeCompactInts(forKey: .majorTraits) ?? []
    }
}

struct TraitMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let description: String
    let tier: Int?
    let slot: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, description, tier, slot
    }

    init(id: Int, name: String, icon: URL?, description: String, tier: Int?, slot: String?) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.tier = tier
        self.slot = slot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Trait \(id)"
        icon = values.decodeFlexibleURL(forKey: .icon)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        tier = try values.decodeIfPresent(Int.self, forKey: .tier)
        slot = try values.decodeIfPresent(String.self, forKey: .slot)
    }
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

    init(
        id: Int, name: String, icon: URL?, description: String, type: String?,
        weaponType: String?, slot: String?
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.type = type
        self.weaponType = weaponType
        self.slot = slot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Skill \(id)"
        icon = values.decodeFlexibleURL(forKey: .icon)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        type = try values.decodeIfPresent(String.self, forKey: .type)
        weaponType = try values.decodeIfPresent(String.self, forKey: .weaponType)
        slot = try values.decodeIfPresent(String.self, forKey: .slot)
    }
}

struct SkinMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let rarity: String?
    let description: String?
}

struct MiniMetadata: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let icon: URL?
    let order: Int?
    let itemID: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, order
        case itemID = "item_id"
    }
}

struct AchievementGroup: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let order: Int
    let categories: [Int]
}

struct AchievementCategory: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let order: Int
    let icon: URL?
    let achievements: [Int]
}

enum AchievementBit: Codable, Hashable, Sendable {
    case text(String)
    case item(Int)
    case minipet(Int)
    case skin(Int)
    case unknown(type: String, id: Int?, text: String?)

    private enum CodingKeys: String, CodingKey { case type, id, text }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decode(String.self, forKey: .type)
        let id = try values.decodeIfPresent(Int.self, forKey: .id)
        let text = try values.decodeIfPresent(String.self, forKey: .text)
        switch type.lowercased() {
        case "text": self = .text(text ?? "")
        case "item": self = id.map(AchievementBit.item) ?? .unknown(type: type, id: nil, text: text)
        case "minipet": self = id.map(AchievementBit.minipet) ?? .unknown(type: type, id: nil, text: text)
        case "skin": self = id.map(AchievementBit.skin) ?? .unknown(type: type, id: nil, text: text)
        default: self = .unknown(type: type, id: id, text: text)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try values.encode("Text", forKey: .type); try values.encode(text, forKey: .text)
        case let .item(id):
            try values.encode("Item", forKey: .type); try values.encode(id, forKey: .id)
        case let .minipet(id):
            try values.encode("Minipet", forKey: .type); try values.encode(id, forKey: .id)
        case let .skin(id):
            try values.encode("Skin", forKey: .type); try values.encode(id, forKey: .id)
        case let .unknown(type, id, text):
            try values.encode(type, forKey: .type)
            try values.encodeIfPresent(id, forKey: .id)
            try values.encodeIfPresent(text, forKey: .text)
        }
    }

    var referencedItemID: Int? { if case let .item(id) = self { id } else { nil } }
    var referencedSkinID: Int? { if case let .skin(id) = self { id } else { nil } }
    var referencedMiniID: Int? { if case let .minipet(id) = self { id } else { nil } }
}

struct AchievementTier: Codable, Hashable, Sendable {
    let count: Int
    let points: Int
}

struct AchievementDefinition: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let icon: URL?
    let name: String
    let description: String
    let requirement: String
    let lockedText: String?
    let type: String?
    let flags: [String]
    let tiers: [AchievementTier]
    let prerequisites: [Int]?
    let bits: [AchievementBit]?
    let pointCap: Int?

    enum CodingKeys: String, CodingKey {
        case id, icon, name, description, requirement, type, flags, tiers, prerequisites, bits
        case lockedText = "locked_text"
        case pointCap = "point_cap"
    }

    var totalPoints: Int { tiers.reduce(0) { $0 + $1.points } }
}

struct AccountAchievementProgress: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let current: Int?
    let max: Int?
    let done: Bool
    let repeated: Int?
    let bits: [Int]?
}

enum RecipeIngredientType: Hashable, Equatable, Sendable {
    case item
    case currency
    case guildUpgrade
    case unknown(String)

    static func parse(_ raw: String) -> RecipeIngredientType {
        switch raw.lowercased() {
        case "item": .item
        case "currency": .currency
        case "guildupgrade": .guildUpgrade
        default: .unknown(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .item: "Item"
        case .currency: "Currency"
        case .guildUpgrade: "GuildUpgrade"
        case let .unknown(value): value
        }
    }
}

struct RecipeIngredient: Codable, Hashable, Sendable {
    let type: String
    let id: Int
    let count: Int

    var knownType: RecipeIngredientType { RecipeIngredientType.parse(type) }

    private enum CodingKeys: String, CodingKey {
        case type, id, count
        case itemID = "item_id"
        case upgradeID = "upgrade_id"
    }

    init(type: String, id: Int, count: Int) {
        self.type = type
        self.id = id
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        count = (try? values.decode(Int.self, forKey: .count)) ?? 1
        if let itemID = try values.decodeIfPresent(Int.self, forKey: .itemID) {
            type = RecipeIngredientType.item.rawValue
            id = itemID
        } else if let upgradeID = try values.decodeIfPresent(Int.self, forKey: .upgradeID) {
            type = RecipeIngredientType.guildUpgrade.rawValue
            id = upgradeID
        } else {
            type = (try? values.decode(String.self, forKey: .type)) ?? "Unknown"
            id = (try? values.decode(Int.self, forKey: .id)) ?? 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(type, forKey: .type)
        try values.encode(id, forKey: .id)
        try values.encode(count, forKey: .count)
    }
}

struct RecipeDefinition: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let type: String
    let outputItemID: Int?
    let outputItemCount: Int
    let timeToCraftMS: Int?
    let disciplines: [String]
    let minRating: Int
    let flags: [String]
    let ingredients: [RecipeIngredient]
    let chatLink: String?

    enum CodingKeys: String, CodingKey {
        case id, type, disciplines, flags, ingredients
        case outputItemID = "output_item_id"
        case outputItemCount = "output_item_count"
        case timeToCraftMS = "time_to_craft_ms"
        case minRating = "min_rating"
        case chatLink = "chat_link"
        case guildIngredients = "guild_ingredients"
    }

    var isAutomaticallyLearned: Bool { flags.contains("AutoLearned") }

    init(
        id: Int, type: String, outputItemID: Int?, outputItemCount: Int,
        timeToCraftMS: Int?, disciplines: [String], minRating: Int,
        flags: [String], ingredients: [RecipeIngredient], chatLink: String?
    ) {
        self.id = id
        self.type = type
        self.outputItemID = outputItemID
        self.outputItemCount = outputItemCount
        self.timeToCraftMS = timeToCraftMS
        self.disciplines = disciplines
        self.minRating = minRating
        self.flags = flags
        self.ingredients = ingredients
        self.chatLink = chatLink
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "Unknown"
        outputItemID = try values.decodeIfPresent(Int.self, forKey: .outputItemID)
        outputItemCount = try values.decodeIfPresent(Int.self, forKey: .outputItemCount) ?? 1
        timeToCraftMS = try values.decodeIfPresent(Int.self, forKey: .timeToCraftMS)
        disciplines = try values.decodeIfPresent([String].self, forKey: .disciplines) ?? []
        minRating = try values.decodeIfPresent(Int.self, forKey: .minRating) ?? 0
        flags = try values.decodeIfPresent([String].self, forKey: .flags) ?? []
        let regular = values.decodeLossyArray(RecipeIngredient.self, forKey: .ingredients)
        let guild = values.decodeLossyArray(RecipeIngredient.self, forKey: .guildIngredients)
        ingredients = regular + guild
        chatLink = try values.decodeIfPresent(String.self, forKey: .chatLink)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(type, forKey: .type)
        try values.encodeIfPresent(outputItemID, forKey: .outputItemID)
        try values.encode(outputItemCount, forKey: .outputItemCount)
        try values.encodeIfPresent(timeToCraftMS, forKey: .timeToCraftMS)
        try values.encode(disciplines, forKey: .disciplines)
        try values.encode(minRating, forKey: .minRating)
        try values.encode(flags, forKey: .flags)
        try values.encode(ingredients, forKey: .ingredients)
        try values.encodeIfPresent(chatLink, forKey: .chatLink)
    }
}

struct CommerceListingSummary: Codable, Hashable, Sendable {
    let quantity: Int
    let unitPrice: Int

    enum CodingKeys: String, CodingKey {
        case quantity
        case unitPrice = "unit_price"
    }
}

struct CommercePrice: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let whitelisted: Bool?
    let buys: CommerceListingSummary
    let sells: CommerceListingSummary
}

struct TimedCommercePrice: Codable, Sendable, Equatable {
    let price: CommercePrice
    let fetchedAt: Date
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
