import Foundation

enum PlayerGoalType: Codable, Hashable, Sendable {
    case achievement(Int)
    case craftItem(itemID: Int, quantity: Int)
    case legendary(itemID: Int)
    case custom

    var title: String {
        switch self {
        case .achievement: "Achievement"
        case .craftItem: "Crafting"
        case .legendary: "Legendary"
        case .custom: "Custom"
        }
    }
}

enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active, completed, paused, archived
}

enum GoalPriority: Int, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Self { self }
    var title: String { String(describing: self).capitalized }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct GoalSourceReference: Codable, Hashable, Sendable {
    let apiPath: String?
    let apiID: Int?
    let provenance: DataProvenance
}

struct ManualChecklistItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var isComplete: Bool
    let provenance: DataProvenance

    init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        provenance = .userDeclared
    }
}

struct GoalMapLink: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let achievementBitIndex: Int?
    var objective: MapObjective
    let provenance: DataProvenance
    let createdAt: Date

    init(
        id: UUID = UUID(), achievementBitIndex: Int? = nil, objective: MapObjective,
        provenance: DataProvenance = .userDeclared, createdAt: Date = Date()
    ) {
        self.id = id
        self.achievementBitIndex = achievementBitIndex
        self.objective = objective
        self.provenance = provenance
        self.createdAt = createdAt
    }
}

struct PlayerGoal: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var type: PlayerGoalType
    let createdAt: Date
    var priority: GoalPriority
    var status: GoalStatus
    var sourceReference: GoalSourceReference?
    var notes: String
    var checklist: [ManualChecklistItem]
    var mapLinks: [GoalMapLink]
    /// Recipe choices are keyed by output item ID, so recalculation is deterministic.
    var selectedRecipeIDs: [Int: Int]

    init(
        id: UUID = UUID(), title: String, type: PlayerGoalType,
        createdAt: Date = Date(), priority: GoalPriority = .normal,
        status: GoalStatus = .active, sourceReference: GoalSourceReference? = nil,
        notes: String = "", checklist: [ManualChecklistItem] = [],
        mapLinks: [GoalMapLink] = [], selectedRecipeIDs: [Int: Int] = [:]
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.createdAt = createdAt
        self.priority = priority
        self.status = status
        self.sourceReference = sourceReference
        self.notes = notes
        self.checklist = checklist
        self.mapLinks = mapLinks
        self.selectedRecipeIDs = selectedRecipeIDs
    }
}

struct GoalScopeSnapshot: Codable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    var goals: [PlayerGoal]
}

struct GoalProgress: Equatable, Sendable {
    let ready: Int
    let total: Int
    let label: String
    let isAuthoritativeCompletion: Bool

    var fraction: Double { total > 0 ? Double(ready) / Double(total) : 0 }
}

enum SuggestedActionType: String, Codable, Sendable {
    case navigate, gather, craft, buy, inspect, markManually, refreshAccount
}

enum ActionConfidence: String, Codable, Sendable {
    case authoritative, derivedStrong, userConfigured, limitedData
}

struct SuggestedAction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: SuggestedActionType
    let title: String
    let reason: String
    let goalID: UUID
    let confidence: ActionConfidence
    let provenance: [DataProvenance]
    let score: Int
    let objectiveIDs: [MapObjectiveID]
    let itemID: Int?

    init(
        id: UUID = UUID(), type: SuggestedActionType, title: String, reason: String,
        goalID: UUID, confidence: ActionConfidence, provenance: [DataProvenance],
        score: Int, objectiveIDs: [MapObjectiveID] = [], itemID: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.reason = reason
        self.goalID = goalID
        self.confidence = confidence
        self.provenance = provenance
        self.score = score
        self.objectiveIDs = objectiveIDs
        self.itemID = itemID
    }
}
