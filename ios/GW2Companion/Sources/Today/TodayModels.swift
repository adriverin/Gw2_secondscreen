import Foundation

struct OpportunityID: RawRepresentable, Codable, Hashable, Sendable, Identifiable, Comparable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    var id: String { rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum OpportunityResetScope: String, Codable, CaseIterable, Sendable {
    case daily, weekly, seasonal, none

    var title: String {
        switch self { case .daily: "Current Daily"; case .weekly: "Current Weekly"; case .seasonal: "This Vault Season"; case .none: "No reset scope" }
    }
}

enum OpportunityUrgency: String, Codable, CaseIterable, Sendable {
    case daily, weekly, seasonal, none
}

enum OpportunityType: String, Codable, CaseIterable, Sendable {
    case wizardVaultDaily
    case wizardVaultWeekly
    case wizardVaultSpecial
    case worldBoss
    case mapChest
    case dailyCrafting
    case raidEncounter
    case dungeonPath

    var title: String {
        switch self {
        case .wizardVaultDaily: "Wizard's Vault Daily"
        case .wizardVaultWeekly: "Wizard's Vault Weekly"
        case .wizardVaultSpecial: "Wizard's Vault Special"
        case .worldBoss: "World Bosses"
        case .mapChest: "Map Chests"
        case .dailyCrafting: "Daily Crafting"
        case .raidEncounter: "Raids"
        case .dungeonPath: "Dungeons"
        }
    }
}

enum OpportunityActivityCategory: String, Codable, CaseIterable, Sendable {
    case pve = "PvE"
    case pvp = "PvP"
    case wvw = "WvW"
    case crafting = "Crafting"
    case raids = "Raids"
    case dungeons = "Dungeons"
    case unknown = "Unknown"
}

enum OpportunityState: String, Codable, CaseIterable, Sendable {
    case incomplete
    case completeUnclaimed
    case completeClaimed
    case completed
    case unavailable
    case unknown

    var isComplete: Bool { [.completeUnclaimed, .completeClaimed, .completed].contains(self) }
    var isClaimable: Bool { self == .completeUnclaimed }
    var accessibilityTitle: String {
        switch self {
        case .incomplete: "incomplete"
        case .completeUnclaimed: "complete, ready to claim in game"
        case .completeClaimed: "complete and claimed"
        case .completed: "completed"
        case .unavailable: "unavailable"
        case .unknown: "completion unknown"
        }
    }
}

struct OpportunityProgress: Codable, Hashable, Sendable {
    let current: Int
    let complete: Int
    var isComplete: Bool { complete > 0 && current >= complete }
    var fraction: Double { complete > 0 ? min(1, Double(current) / Double(complete)) : 0 }
}

struct OpportunityReward: Codable, Hashable, Sendable {
    let astralAcclaim: Int?
    let itemID: Int?
    let itemName: String?
}

struct AccountOpportunity: Identifiable, Codable, Hashable, Sendable {
    let id: OpportunityID
    let type: OpportunityType
    let resetScope: OpportunityResetScope
    let urgency: OpportunityUrgency
    let title: String
    let subtitle: String?
    let progress: OpportunityProgress?
    let reward: OpportunityReward?
    let state: OpportunityState
    let activity: OpportunityActivityCategory
    let relatedItemIDs: [Int]
    let relatedAchievementIDs: [Int]
    let mapID: Int?
    let mapName: String?
    let sourceIdentifier: String
    let provenance: [DataProvenance]
}

struct TodayOpportunityLink: Identifiable, Codable, Hashable, Sendable {
    var id: OpportunityID { opportunityID }
    let opportunityID: OpportunityID
    let mapID: Int
    let mapName: String?
    let objective: MapObjective?
    let provenance: DataProvenance
}

struct VaultMetaProgress: Codable, Hashable, Sendable {
    let resetScope: OpportunityResetScope
    let progress: OpportunityProgress
    let reward: OpportunityReward
    let claimed: Bool
    var state: OpportunityState {
        guard progress.isComplete else { return .incomplete }
        return claimed ? .completeClaimed : .completeUnclaimed
    }
}

struct VaultRewardListing: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let itemID: Int
    let itemName: String
    let icon: URL?
    let itemCount: Int
    let type: WizardVaultListingType
    let cost: Int
    let purchased: Int?
    let purchaseLimit: Int?

    var isLimitReached: Bool {
        guard let purchased, let purchaseLimit else { return false }
        return purchased >= purchaseLimit
    }
}

struct TodayDiagnostics: Codable, Hashable, Sendable {
    let dailyObjectiveCount: Int
    let weeklyObjectiveCount: Int
    let specialObjectiveCount: Int
    let claimableCount: Int
    let worldBossIDs: [String]
    let mapChestIDs: [String]
    let dailyCraftingIDs: [String]
    let raidEventIDs: [String]
    let dungeonPathIDs: [String]
    let unknownIDs: [String]
}

struct TodayDataSnapshot: Codable, Hashable, Sendable {
    let timestamp: Date
    let accountID: String?
    let season: WizardVaultSeason?
    let opportunities: [AccountOpportunity]
    let dailyMeta: VaultMetaProgress?
    let weeklyMeta: VaultMetaProgress?
    let vaultRewards: [VaultRewardListing]
    let astralAcclaimBalance: Int?
    let hasProgressionPermission: Bool
    let diagnostics: TodayDiagnostics

    var claimable: [AccountOpportunity] { opportunities.filter(\.state.isClaimable) }
    var daily: [AccountOpportunity] { opportunities.filter { $0.resetScope == .daily } }
    var weekly: [AccountOpportunity] { opportunities.filter { $0.resetScope == .weekly } }
    var special: [AccountOpportunity] { opportunities.filter { $0.resetScope == .seasonal } }
}

struct TodayProgressSnapshot: Codable, Hashable, Sendable {
    let timestamp: Date
    let dailyVaultCompleted: Int
    let dailyVaultTotal: Int
    let weeklyVaultCompleted: Int
    let weeklyVaultTotal: Int
    let worldBossesCompleted: Set<String>
    let mapChestsCompleted: Set<String>
    let dailyCraftingCompleted: Set<String>
    let raidEncountersCompleted: Set<String>
    let dungeonPathsCompleted: Set<String>

    init(data: TodayDataSnapshot) {
        timestamp = data.timestamp
        let daily = data.opportunities.filter { $0.type == .wizardVaultDaily }
        let weekly = data.opportunities.filter { $0.type == .wizardVaultWeekly }
        dailyVaultCompleted = daily.filter(\.state.isComplete).count
        dailyVaultTotal = daily.count
        weeklyVaultCompleted = weekly.filter(\.state.isComplete).count
        weeklyVaultTotal = weekly.count
        worldBossesCompleted = Self.completedIDs(.worldBoss, data: data)
        mapChestsCompleted = Self.completedIDs(.mapChest, data: data)
        dailyCraftingCompleted = Self.completedIDs(.dailyCrafting, data: data)
        raidEncountersCompleted = Self.completedIDs(.raidEncounter, data: data)
        dungeonPathsCompleted = Self.completedIDs(.dungeonPath, data: data)
    }

    private static func completedIDs(_ type: OpportunityType, data: TodayDataSnapshot) -> Set<String> {
        Set(data.opportunities.filter { $0.type == type && $0.state.isComplete }.map(\.sourceIdentifier))
    }
}

struct TodayProgressChange: Identifiable, Codable, Hashable, Sendable {
    let label: String
    let before: Int
    let after: Int
    var id: String { label }
}

enum TodayProgressDiff {
    static func changes(from before: TodayProgressSnapshot, to after: TodayProgressSnapshot) -> [TodayProgressChange] {
        let candidates = [
            TodayProgressChange(label: "Wizard's Vault Daily", before: before.dailyVaultCompleted, after: after.dailyVaultCompleted),
            TodayProgressChange(label: "Wizard's Vault Weekly", before: before.weeklyVaultCompleted, after: after.weeklyVaultCompleted),
            TodayProgressChange(label: "World Bosses", before: before.worldBossesCompleted.count, after: after.worldBossesCompleted.count),
            TodayProgressChange(label: "Map Chests", before: before.mapChestsCompleted.count, after: after.mapChestsCompleted.count),
            TodayProgressChange(label: "Daily Crafting", before: before.dailyCraftingCompleted.count, after: after.dailyCraftingCompleted.count),
            TodayProgressChange(label: "Raid Encounters", before: before.raidEncountersCompleted.count, after: after.raidEncountersCompleted.count),
            TodayProgressChange(label: "Dungeon Paths", before: before.dungeonPathsCompleted.count, after: after.dungeonPathsCompleted.count)
        ]
        return candidates.filter { $0.before != $0.after }
    }
}

enum TodayFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case daily = "Daily"
    case weekly = "Weekly"
    case vault = "Vault"
    case pve = "PvE"
    var id: Self { self }
}
