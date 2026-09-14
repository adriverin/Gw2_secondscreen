import Foundation

struct WizardVaultSeason: Codable, Hashable, Sendable {
    let title: String
    let start: String
    let end: String
    let listings: [Int]
    let objectives: [Int]

    var identity: String { "\(title)|\(start)|\(end)" }
}

struct WizardVaultObjectiveMetadata: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let track: String
    let acclaim: Int
}

enum WizardVaultListingType: Codable, Hashable, Sendable {
    case featured
    case normal
    case legacy
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "featured": self = .featured
        case "normal": self = .normal
        case "legacy": self = .legacy
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .featured: "Featured"
        case .normal: "Normal"
        case .legacy: "Legacy"
        case let .unknown(value): value
        }
    }

    var sortOrder: Int {
        switch self { case .featured: 0; case .normal: 1; case .legacy: 2; case .unknown: 3 }
    }
}

struct WizardVaultListingMetadata: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let itemID: Int
    let itemCount: Int
    let type: WizardVaultListingType
    let cost: Int

    enum CodingKeys: String, CodingKey {
        case id, type, cost
        case itemID = "item_id"
        case itemCount = "item_count"
    }
}

struct WizardVaultAccountObjective: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let track: String
    let acclaim: Int
    let progressCurrent: Int
    let progressComplete: Int
    let claimed: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, track, acclaim, claimed
        case progressCurrent = "progress_current"
        case progressComplete = "progress_complete"
    }
}

struct WizardVaultAccountPeriod: Codable, Hashable, Sendable {
    let metaProgressCurrent: Int
    let metaProgressComplete: Int
    let metaRewardItemID: Int
    let metaRewardAstral: Int
    let metaRewardClaimed: Bool
    let objectives: [WizardVaultAccountObjective]

    enum CodingKeys: String, CodingKey {
        case objectives
        case metaProgressCurrent = "meta_progress_current"
        case metaProgressComplete = "meta_progress_complete"
        case metaRewardItemID = "meta_reward_item_id"
        case metaRewardAstral = "meta_reward_astral"
        case metaRewardClaimed = "meta_reward_claimed"
    }
}

struct WizardVaultAccountSpecial: Codable, Hashable, Sendable {
    let objectives: [WizardVaultAccountObjective]
}

struct WizardVaultAccountListing: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let itemID: Int
    let itemCount: Int
    let type: WizardVaultListingType
    let cost: Int
    let purchased: Int?
    let purchaseLimit: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, cost, purchased
        case itemID = "item_id"
        case itemCount = "item_count"
        case purchaseLimit = "purchase_limit"
    }
}

enum RaidEventType: Codable, Hashable, Sendable {
    case boss
    case checkpoint
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "boss": self = .boss
        case "checkpoint": self = .checkpoint
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self { case .boss: "Boss"; case .checkpoint: "Checkpoint"; case let .unknown(value): value }
    }
}

struct RaidDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let wings: [RaidWing]
}

struct RaidWing: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let events: [RaidEvent]
}

struct RaidEvent: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let type: RaidEventType
}

struct DungeonDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let paths: [DungeonPath]
}

struct DungeonPath: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let type: String
}

protocol TodayDataProvider: Sendable {
    func wizardVaultSeason(language: String) async throws -> WizardVaultSeason
    func wizardVaultObjectives(ids: [Int], language: String) async throws -> [WizardVaultObjectiveMetadata]
    func wizardVaultListings(ids: [Int], language: String) async throws -> [WizardVaultListingMetadata]
    func worldBossIDs() async throws -> [String]
    func mapChestIDs() async throws -> [String]
    func dailyCraftingIDs() async throws -> [String]
    func raids(language: String) async throws -> [RaidDefinition]
    func dungeons(language: String) async throws -> [DungeonDefinition]
    func wizardVaultDaily() async throws -> WizardVaultAccountPeriod
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing]
    func accountWorldBossIDs() async throws -> [String]
    func accountMapChestIDs() async throws -> [String]
    func accountDailyCraftingIDs() async throws -> [String]
    func accountRaidEventIDs() async throws -> [String]
    func accountDungeonPathIDs() async throws -> [String]
    func todayItems(ids: [Int]) async throws -> [Int: ItemMetadata]
    func todayCurrencies(ids: [Int]) async throws -> [Int: CurrencyMetadata]
    func todayWallet() async throws -> [WalletEntry]
}
