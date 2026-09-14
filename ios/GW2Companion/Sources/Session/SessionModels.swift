import Foundation

enum AcquisitionPreferenceLevel: Int, Codable, CaseIterable, Sendable {
    case avoid = -1
    case neutral = 0
    case prefer = 1

    var title: String {
        switch self { case .avoid: "Avoid"; case .neutral: "Neutral"; case .prefer: "Prefer" }
    }
}

struct PlanningPreferences: Codable, Hashable, Sendable {
    /// Applies when no narrower override exists.
    var global: [AcquisitionMethodType: AcquisitionPreferenceLevel] = [:]
    /// Key: goal UUID + target key.
    var goalOverrides: [String: AcquisitionMethodType] = [:]
    /// Key: goal UUID + requirement identity. This has the highest precedence.
    var requirementOverrides: [String: AcquisitionMethodType] = [:]

    static func goalKey(goalID: UUID, targetKey: String) -> String { "\(goalID.uuidString)|\(targetKey)" }
    static func requirementKey(goalID: UUID, requirementID: String) -> String { "\(goalID.uuidString)|\(requirementID)" }

    func preferredMethod(goalID: UUID, requirementID: String, targetKey: String) -> (AcquisitionMethodType?, String) {
        if let value = requirementOverrides[Self.requirementKey(goalID: goalID, requirementID: requirementID)] {
            return (value, "Requirement override")
        }
        if let value = goalOverrides[Self.goalKey(goalID: goalID, targetKey: targetKey)] {
            return (value, "Goal override")
        }
        return (nil, "Global preference")
    }
}

enum SessionDuration: Int, Codable, CaseIterable, Identifiable, Sendable {
    case minutes15 = 15, minutes30 = 30, minutes45 = 45, minutes60 = 60, openEnded = 0
    var id: Self { self }
    var title: String { self == .openEnded ? "Open ended" : "\(rawValue) min" }
    var taskLimit: Int? {
        switch self {
        case .minutes15: 3
        case .minutes30: 5
        case .minutes45: 7
        case .minutes60: 9
        case .openEnded: nil
        }
    }
}

struct SessionParameters: Codable, Hashable, Sendable {
    var duration: SessionDuration = .minutes45
    var selectedGoalIDs: Set<UUID>? = nil
    var stayNearCurrentMap = true
    var enabledMethods: Set<AcquisitionMethodType> = Set(AcquisitionMethodType.allCases)
}

struct PlanningRequirement: Codable, Hashable, Sendable {
    let id: String
    let target: AcquisitionTarget
    let requiredQuantity: Int
    let name: String
    let provenance: [DataProvenance]
    let craftReady: Bool
}

struct PlanningGoal: Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let priority: GoalPriority
    let requirements: [PlanningRequirement]
    let linkedObjectives: [MapObjective]
    let fallbackReason: String?
}

struct ScoreContribution: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(factor):\(value):\(explanation)" }
    let factor: String
    let value: Int
    let explanation: String
}

struct ScoreBreakdown: Codable, Hashable, Sendable {
    let total: Int
    let contributions: [ScoreContribution]

    init(contributions: [ScoreContribution]) {
        self.contributions = contributions
        total = contributions.reduce(0) { $0 + $1.value }
    }
}

enum SessionTaskType: String, Codable, CaseIterable, Sendable {
    case navigate, gather, craft, buy, vendor, achievement, mysticForge, visit, manual
    // Reserved general-purpose shapes for later API-backed daily/weekly work.
    case daily, weekly

    var title: String {
        switch self {
        case .navigate: "Navigate"
        case .gather: "Gather"
        case .craft: "Craft"
        case .buy: "Buy"
        case .vendor: "Vendor"
        case .achievement: "Achievement"
        case .mysticForge: "Mystic Forge"
        case .visit: "Visit"
        case .manual: "Manual"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum SessionTaskState: String, Codable, Sendable {
    case pending, visited, completed, skipped, doLater

    var isFinished: Bool { [.visited, .completed, .skipped].contains(self) }
}

struct SessionTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let deduplicationKey: String
    let title: String
    let type: SessionTaskType
    let relatedGoalIDs: [UUID]
    let relatedGoalTitles: [String]
    let acquisitionMethodID: String?
    let target: AcquisitionTarget?
    let quantity: Int?
    let mapObjectiveIDs: [MapObjectiveID]
    let mapID: Int?
    let reason: String
    let scoreBreakdown: ScoreBreakdown
    let provenance: [DataProvenance]
    let knowledgeSources: [KnowledgeSource]
    let coverage: KnowledgeCoverage?
    var state: SessionTaskState
    var isLocked: Bool

    init(
        id: UUID = UUID(), deduplicationKey: String, title: String, type: SessionTaskType,
        relatedGoalIDs: [UUID], relatedGoalTitles: [String], acquisitionMethodID: String? = nil,
        target: AcquisitionTarget? = nil, quantity: Int? = nil,
        mapObjectiveIDs: [MapObjectiveID] = [], mapID: Int? = nil, reason: String,
        scoreBreakdown: ScoreBreakdown, provenance: [DataProvenance],
        knowledgeSources: [KnowledgeSource] = [], coverage: KnowledgeCoverage? = nil,
        state: SessionTaskState = .pending, isLocked: Bool = false
    ) {
        self.id = id
        self.deduplicationKey = deduplicationKey
        self.title = title
        self.type = type
        self.relatedGoalIDs = relatedGoalIDs
        self.relatedGoalTitles = relatedGoalTitles
        self.acquisitionMethodID = acquisitionMethodID
        self.target = target
        self.quantity = quantity
        self.mapObjectiveIDs = mapObjectiveIDs
        self.mapID = mapID
        self.reason = reason
        self.scoreBreakdown = scoreBreakdown
        self.provenance = provenance
        self.knowledgeSources = knowledgeSources
        self.coverage = coverage
        self.state = state
        self.isLocked = isLocked
    }
}

struct SessionPlanDiagnostics: Codable, Hashable, Sendable {
    let candidateCount: Int
    let deduplicatedCount: Int
    let filteredCount: Int
    let selectedCount: Int
    let planningDurationMilliseconds: Double
}

struct SessionPlan: Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let parameters: SessionParameters
    let currentMapID: Int?
    let tasks: [SessionTask]
    let diagnostics: SessionPlanDiagnostics

    init(
        id: UUID = UUID(), createdAt: Date = Date(), parameters: SessionParameters,
        currentMapID: Int?, tasks: [SessionTask], diagnostics: SessionPlanDiagnostics
    ) {
        self.id = id
        self.createdAt = createdAt
        self.parameters = parameters
        self.currentMapID = currentMapID
        self.tasks = tasks
        self.diagnostics = diagnostics
    }
}

struct SessionAccountSnapshot: Codable, Hashable, Sendable {
    let timestamp: Date
    let relevantHoldings: [Int: Int]
    let relevantCurrencies: [Int: Int]
}

enum SessionAccountValueKind: String, Codable, Sendable { case item, currency }

struct SessionAccountChange: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(numericID)" }
    let kind: SessionAccountValueKind
    let numericID: Int
    let before: Int
    let after: Int
    var delta: Int { after - before }
}

enum SessionAccountDiff {
    static func changes(from before: SessionAccountSnapshot, to after: SessionAccountSnapshot) -> [SessionAccountChange] {
        let itemIDs = Set(before.relevantHoldings.keys).union(after.relevantHoldings.keys)
        let currencyIDs = Set(before.relevantCurrencies.keys).union(after.relevantCurrencies.keys)
        let items = itemIDs.compactMap { id -> SessionAccountChange? in
            let change = SessionAccountChange(
                kind: .item, numericID: id, before: before.relevantHoldings[id, default: 0],
                after: after.relevantHoldings[id, default: 0])
            return change.delta == 0 ? nil : change
        }
        let currencies = currencyIDs.compactMap { id -> SessionAccountChange? in
            let change = SessionAccountChange(
                kind: .currency, numericID: id, before: before.relevantCurrencies[id, default: 0],
                after: after.relevantCurrencies[id, default: 0])
            return change.delta == 0 ? nil : change
        }
        return (items + currencies).sorted { $0.id < $1.id }
    }
}

struct ActiveSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var endedAt: Date?
    let planningHorizon: SessionDuration
    let initialMapID: Int?
    let initialPlayerPosition: ContinentPoint?
    let initialAccountSnapshot: SessionAccountSnapshot
    var latestAccountSnapshot: SessionAccountSnapshot
    var tasks: [SessionTask]

    var completedTaskCount: Int { tasks.filter { [.visited, .completed].contains($0.state) }.count }
    var helpedGoalIDs: Set<UUID> { Set(tasks.filter { $0.state != .skipped }.flatMap(\.relatedGoalIDs)) }
}

struct SessionHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let planningHorizon: SessionDuration
    let completedTaskCount: Int
    let totalTaskCount: Int
    let goalCount: Int
    let mapsVisited: [Int]
    let objectiveVisits: Int
    let accountChanges: [SessionAccountChange]
}
