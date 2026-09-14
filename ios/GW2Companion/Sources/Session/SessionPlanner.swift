import Foundation

struct SessionPlanningContext: Sendable {
    let goals: [PlanningGoal]
    let holdings: [Int: Int]
    let currencies: [Int: Int]
    let acquisitionMethods: [AcquisitionMethod]
    let preferences: PlanningPreferences
    let parameters: SessionParameters
    let currentMapID: Int?
    let playerPosition: ContinentPoint?
    let mapObjectives: [MapObjective]
    var opportunities: [AccountOpportunity] = []
    var opportunityLinks: [OpportunityID: TodayOpportunityLink] = [:]
}

enum SessionScoring {
    static let priority: [GoalPriority: Int] = [.low: 15, .normal: 35, .high: 60]
    static let multiGoalBenefit = 20
    static let sameCurrentMap = 50
    static let nearby = 30
    /// Strong enough to choose a preferred acquisition path over a nearby alternative while
    /// still leaving that alternative visible in the reviewed plan.
    static let preferredMethod = 80
    static let explicitOverride = 80
    static let notSelectedOverride = -80
    static let craftReady = 35
    static let marketAvailable = 10
    static let manualMethod = -10
    static let avoidedMethod = -30
    static let nearbyDistance = 1_500.0
    static let dailyOpportunity = 40
    static let weeklyOpportunity = 20
    static let seasonalOpportunity = 5
    static let claimableReward = 70
    static let nearCompletion = 15
    static let preferredActivity = 20
    static let avoidedActivity = -25
    static let goalOpportunityCrossBenefit = 60
}

enum SessionPlanner {
    private struct Need {
        let target: AcquisitionTarget
        let name: String
        var required: Int
        var goals: [PlanningGoal]
        var requirements: [(UUID, PlanningRequirement)]
        var provenance: Set<DataProvenance>
    }

    static func plan(context: SessionPlanningContext, now: Date = Date()) -> SessionPlan {
        let started = ContinuousClock.now
        let selectedGoals = context.goals.filter { goal in
            context.parameters.selectedGoalIDs?.contains(goal.id) ?? true
        }
        var needs: [String: Need] = [:]
        for goal in selectedGoals {
            for requirement in goal.requirements where requirement.requiredQuantity > 0 {
                var need = needs[requirement.target.key] ?? Need(
                    target: requirement.target, name: requirement.name, required: 0,
                    goals: [], requirements: [], provenance: [])
                need.required += requirement.requiredQuantity
                if !need.goals.contains(where: { $0.id == goal.id }) { need.goals.append(goal) }
                need.requirements.append((goal.id, requirement))
                need.provenance.formUnion(requirement.provenance)
                needs[requirement.target.key] = need
            }
        }

        let methodsByTarget = Dictionary(grouping: context.acquisitionMethods, by: { $0.target.key })
        var candidates: [SessionTask] = []
        for key in needs.keys.sorted() {
            guard let need = needs[key] else { continue }
            let owned: Int = switch need.target.kind {
            case .item: context.holdings[need.target.numericID ?? -1, default: 0]
            case .currency: context.currencies[need.target.numericID ?? -1, default: 0]
            case .achievement, .custom: 0
            }
            let shortage = max(0, need.required - owned)
            guard shortage > 0 else { continue }
            var methods = methodsByTarget[key] ?? []
            if methods.isEmpty { methods = [fallbackMethod(for: need.target)] }
            for method in methods where context.parameters.enabledMethods.contains(method.type) {
                let matchingObjectives = objectives(for: method, in: context.mapObjectives)
                let score = score(
                    method: method, need: need, matchingObjectives: matchingObjectives,
                    context: context)
                let goalIDs = need.goals.map(\.id).sorted { $0.uuidString < $1.uuidString }
                let goalTitles = need.goals.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.title)
                let target = need.target.withQuantity(shortage)
                let taskType = taskType(for: method.type)
                let title = taskTitle(method: method, name: need.name, shortage: shortage)
                let reason = reason(method: method, need: need, shortage: shortage, objectives: matchingObjectives)
                let mapID = method.location?.mapID ?? matchingObjectives.first?.mapId
                candidates.append(SessionTask(
                    deduplicationKey: "acquire|\(method.type.rawValue)|\(key)|\(mapID ?? -1)",
                    title: title, type: taskType, relatedGoalIDs: goalIDs,
                    relatedGoalTitles: goalTitles, acquisitionMethodID: method.id,
                    source: goalIDs.count == 1 ? .goal(goalIDs[0]) : .multipleGoals(goalIDs),
                    target: target, quantity: shortage, mapObjectiveIDs: matchingObjectives.map(\.id),
                    mapID: mapID, reason: reason, scoreBreakdown: score,
                    provenance: Array(need.provenance.union([method.source.provenance, .derived])).sorted { $0.rawValue < $1.rawValue },
                    knowledgeSources: [method.source], coverage: method.coverage))
            }
        }

        // User-linked goal objectives become location tasks and naturally consolidate by ID.
        let linked = Dictionary(grouping: selectedGoals.flatMap { goal in
            goal.linkedObjectives.map { (goal, $0) }
        }, by: { $0.1.id })
        for objectiveID in linked.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let values = linked[objectiveID], let objective = values.first?.1 else { continue }
            let goals = values.map(\.0)
            let contributions = commonScoreContributions(
                goals: goals, mapID: objective.mapId, coordinate: objective.coordinate,
                method: .worldObjective, context: context)
            candidates.append(SessionTask(
                deduplicationKey: "objective|\(objective.id.rawValue)",
                title: "Visit \(objective.name)", type: .navigate,
                relatedGoalIDs: goals.map(\.id).sorted { $0.uuidString < $1.uuidString },
                relatedGoalTitles: goals.map(\.title).sorted(),
                source: goals.count == 1 ? .goal(goals[0].id) : .multipleGoals(goals.map(\.id)),
                mapObjectiveIDs: [objective.id],
                mapID: objective.mapId,
                reason: "This user-linked map objective helps \(goals.count == 1 ? goals[0].title : "\(goals.count) active goals").",
                scoreBreakdown: ScoreBreakdown(contributions: contributions),
                provenance: [.userDeclared, .liveTelemetry, .derived], coverage: .partial))
        }

        // A custom goal without requirements or links remains honestly manual.
        for goal in selectedGoals where goal.requirements.isEmpty && goal.linkedObjectives.isEmpty {
            guard let reason = goal.fallbackReason, context.parameters.enabledMethods.contains(.manual) else { continue }
            let contributions = commonScoreContributions(
                goals: [goal], mapID: nil, coordinate: nil, method: .manual, context: context)
            candidates.append(SessionTask(
                deduplicationKey: "manual|\(goal.id.uuidString)", title: "Review \(goal.title)", type: .manual,
                relatedGoalIDs: [goal.id], relatedGoalTitles: [goal.title], source: .goal(goal.id), reason: reason,
                scoreBreakdown: ScoreBreakdown(contributions: contributions),
                provenance: [.userDeclared, .derived], coverage: .exampleOnly))
        }


        var todayCandidateCount = 0
        for opportunity in context.opportunities where [.incomplete, .completeUnclaimed].contains(opportunity.state) {
            if opportunity.type == .dailyCrafting,
               let itemID = opportunity.relatedItemIDs.first,
               let index = candidates.firstIndex(where: { $0.type == .craft && $0.target?.numericID == itemID }) {
                candidates[index] = enrich(candidates[index], with: opportunity, context: context)
                todayCandidateCount += 1
            } else {
                candidates.append(opportunityCandidate(opportunity, context: context))
                todayCandidateCount += 1
            }
        }

        let candidateCount = candidates.count
        // Candidate construction already consolidates requirement work by target/type/map.
        let deduplicated = Dictionary(grouping: candidates, by: { $0.deduplicationKey }).values.compactMap { group in
            group.sorted { lhs, rhs in
                if lhs.scoreBreakdown.total != rhs.scoreBreakdown.total { return lhs.scoreBreakdown.total > rhs.scoreBreakdown.total }
                return lhs.title < rhs.title
            }.first
        }
        let filtered = deduplicated.filter { task in
            guard context.parameters.stayNearCurrentMap, let current = context.currentMapID, let mapID = task.mapID else { return true }
            return mapID == current || task.isLocked
        }
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.scoreBreakdown.total != rhs.scoreBreakdown.total { return lhs.scoreBreakdown.total > rhs.scoreBreakdown.total }
            return lhs.deduplicationKey < rhs.deduplicationKey
        }
        let selected = context.parameters.duration.taskLimit.map { Array(sorted.prefix($0)) } ?? sorted
        let elapsed = ContinuousClock.now - started
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return SessionPlan(
            createdAt: now, parameters: context.parameters, currentMapID: context.currentMapID,
            tasks: selected,
            diagnostics: SessionPlanDiagnostics(
                candidateCount: candidateCount, deduplicatedCount: deduplicated.count,
                filteredCount: deduplicated.count - filtered.count, selectedCount: selected.count,
                planningDurationMilliseconds: milliseconds,
                todayDerivedCandidateCount: todayCandidateCount))
    }

    static func replan(_ session: ActiveSession, context: SessionPlanningContext, now: Date = Date()) -> ActiveSession {
        let newPlan = plan(context: context, now: now)
        let previous = Dictionary(uniqueKeysWithValues: session.tasks.map { ($0.deduplicationKey, $0) })
        let protected = session.tasks.filter { $0.isLocked || $0.state.isFinished || $0.state == .doLater }
        var tasks = newPlan.tasks.compactMap { candidate -> SessionTask? in
            if let old = previous[candidate.deduplicationKey] {
                if old.state == .skipped || old.state == .completed || old.state == .visited { return nil }
                var copy = candidate
                copy.state = old.state
                copy.isLocked = old.isLocked
                return copy
            }
            return candidate
        }
        for old in protected where !old.state.isFinished && !tasks.contains(where: { $0.deduplicationKey == old.deduplicationKey }) {
            tasks.insert(old, at: 0)
        }
        var copy = session
        copy.tasks = protected.filter { $0.state.isFinished } + tasks
        return copy
    }

    private static func score(
        method: AcquisitionMethod, need: Need, matchingObjectives: [MapObjective],
        context: SessionPlanningContext
    ) -> ScoreBreakdown {
        let mapID = method.location?.mapID ?? matchingObjectives.first?.mapId
        let coordinate = method.location.flatMap { location -> ContinentPoint? in
            guard let x = location.continentX, let y = location.continentY else { return nil }
            return ContinentPoint(x: x, y: y)
        } ?? matchingObjectives.first?.coordinate
        var values = commonScoreContributions(
            goals: need.goals, mapID: mapID, coordinate: coordinate, method: method.type, context: context)
        let overrideResults = need.requirements.map { goalID, requirement in
            context.preferences.preferredMethod(
                goalID: goalID, requirementID: requirement.id, targetKey: requirement.target.key)
        }
        if let explicit = overrideResults.first(where: { $0.0 != nil }), let selected = explicit.0 {
            let value = selected == method.type ? SessionScoring.explicitOverride : SessionScoring.notSelectedOverride
            values.append(ScoreContribution(
                factor: "acquisitionOverride", value: value,
                explanation: "\(explicit.1) selects \(selected.title)."))
        } else {
            let preference = context.preferences.global[method.type, default: .neutral]
            if preference == .prefer {
                values.append(ScoreContribution(
                    factor: "acquisitionPreference", value: SessionScoring.preferredMethod,
                    explanation: "\(method.type.title) is globally preferred."))
            } else if preference == .avoid {
                values.append(ScoreContribution(
                    factor: "acquisitionPreference", value: SessionScoring.avoidedMethod,
                    explanation: "\(method.type.title) is globally avoided but remains available."))
            }
        }
        if method.type == .craft && need.requirements.contains(where: { $0.1.craftReady }) {
            values.append(ScoreContribution(
                factor: "requirementsReadiness", value: SessionScoring.craftReady,
                explanation: "The known ingredients are currently ready."))
        }
        if method.type == .tradingPost {
            values.append(ScoreContribution(
                factor: "marketAvailability", value: SessionScoring.marketAvailable,
                explanation: "A current public sell offer was loaded."))
        }
        return ScoreBreakdown(contributions: values)
    }

    private static func commonScoreContributions(
        goals: [PlanningGoal], mapID: Int?, coordinate: ContinentPoint?,
        method: AcquisitionMethodType, context: SessionPlanningContext
    ) -> [ScoreContribution] {
        var values: [ScoreContribution] = []
        let priority = goals.map(\.priority).max() ?? .low
        values.append(ScoreContribution(
            factor: "goalPriority", value: SessionScoring.priority[priority, default: 0],
            explanation: "Highest related goal priority is \(priority.title.lowercased())."))
        if goals.count > 1 {
            let value = (goals.count - 1) * SessionScoring.multiGoalBenefit
            values.append(ScoreContribution(
                factor: "multiGoalBenefit", value: value,
                explanation: "One action helps \(goals.count) active goals."))
        }
        if let current = context.currentMapID, mapID == current {
            values.append(ScoreContribution(
                factor: "sameCurrentMap", value: SessionScoring.sameCurrentMap,
                explanation: "The action is on the current map."))
        }
        if let player = context.playerPosition, let coordinate,
           ObjectiveDistanceEngine.distance(from: player, to: coordinate) <= SessionScoring.nearbyDistance {
            values.append(ScoreContribution(
                factor: "nearbyDistance", value: SessionScoring.nearby,
                explanation: "The mapped action is in the nearby distance band."))
        }
        if [.manual, .unknown].contains(method) {
            values.append(ScoreContribution(
                factor: "limitedAutomation", value: SessionScoring.manualMethod,
                explanation: "This action needs manual verification."))
        }
        return values
    }

    private static func objectives(for method: AcquisitionMethod, in values: [MapObjective]) -> [MapObjective] {
        guard method.type == .gathering else {
            if let id = method.location?.objectiveID { return values.filter { $0.id == id } }
            return []
        }
        return values.filter { objective in
            if let category = method.gatheringCategory {
                let expected: MapObjectiveType = switch category {
                case .ore: .gatheringOre
                case .wood: .gatheringWood
                case .plant: .gatheringPlant
                case .other: .custom
                }
                guard objective.type == expected else { return false }
            }
            guard let subtype = method.markerSubtype?.lowercased() else { return true }
            return objective.name.lowercased().contains(subtype.lowercased())
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private static func opportunityCandidate(
        _ opportunity: AccountOpportunity, context: SessionPlanningContext
    ) -> SessionTask {
        let isClaim = opportunity.state == .completeUnclaimed
        let taskType: SessionTaskType = if isClaim {
            opportunity.resetScope == .weekly ? .weekly : .daily
        } else {
            switch opportunity.type {
            case .dailyCrafting: .craft
            case .wizardVaultWeekly, .raidEncounter: .weekly
            case .wizardVaultSpecial: .seasonal
            case .wizardVaultDaily, .worldBoss, .mapChest, .dungeonPath: .daily
            }
        }
        let title: String = if isClaim {
            "Claim \(opportunity.title) reward in game"
        } else {
            switch opportunity.type {
            case .dailyCrafting: "Craft \(opportunity.title)"
            case .worldBoss: "Defeat \(opportunity.title)"
            case .mapChest: "Complete \(opportunity.title) map activity"
            case .raidEncounter, .dungeonPath: "Complete \(opportunity.title)"
            default: opportunity.title
            }
        }
        let target = opportunity.relatedItemIDs.first.map { AcquisitionTarget.item(id: $0, quantity: 1) }
        let userLink = context.opportunityLinks[opportunity.id]
        let mapID = userLink?.mapID ?? opportunity.mapID
        let objectiveIDs = userLink?.objective.map { [$0.id] } ?? []
        return SessionTask(
            deduplicationKey: "opportunity|\(opportunity.id.rawValue)", title: title, type: taskType,
            relatedGoalIDs: [], relatedGoalTitles: [], source: .opportunity(opportunity.id),
            relatedOpportunityIDs: [opportunity.id], relatedOpportunityTitles: [opportunity.type.title],
            target: target, quantity: nil, mapObjectiveIDs: objectiveIDs, mapID: mapID,
            reason: opportunityReason(opportunity),
            scoreBreakdown: ScoreBreakdown(contributions: opportunityScore(opportunity, context: context)),
            provenance: Array(Set(opportunity.provenance + [.derived])).sorted { $0.rawValue < $1.rawValue },
            coverage: opportunity.mapID == nil ? .partial : .exampleOnly)
    }

    private static func enrich(
        _ task: SessionTask, with opportunity: AccountOpportunity, context: SessionPlanningContext
    ) -> SessionTask {
        var contributions = task.scoreBreakdown.contributions
        contributions += opportunityScore(opportunity, context: context)
        contributions.append(ScoreContribution(
            factor: "goalOpportunityCrossBenefit", value: SessionScoring.goalOpportunityCrossBenefit,
            explanation: "One structured action helps both an active goal and today's account opportunity."))
        let opportunityIDs = Array(Set((task.relatedOpportunityIDs ?? []) + [opportunity.id])).sorted()
        let opportunityTitles = Array(Set((task.relatedOpportunityTitles ?? []) + [opportunity.type.title])).sorted()
        return SessionTask(
            id: task.id, deduplicationKey: task.deduplicationKey, title: task.title, type: task.type,
            relatedGoalIDs: task.relatedGoalIDs, relatedGoalTitles: task.relatedGoalTitles,
            acquisitionMethodID: task.acquisitionMethodID,
            source: .mixed(goals: task.relatedGoalIDs, opportunities: opportunityIDs),
            relatedOpportunityIDs: opportunityIDs, relatedOpportunityTitles: opportunityTitles,
            target: task.target, quantity: task.quantity, mapObjectiveIDs: task.mapObjectiveIDs,
            mapID: task.mapID,
            reason: task.reason + " Also available as \(opportunity.resetScope.title.lowercased()): \(opportunity.title).",
            scoreBreakdown: ScoreBreakdown(contributions: contributions),
            provenance: Array(Set(task.provenance + opportunity.provenance + [.derived])).sorted { $0.rawValue < $1.rawValue },
            knowledgeSources: task.knowledgeSources, coverage: task.coverage,
            state: task.state, isLocked: task.isLocked)
    }

    private static func opportunityScore(
        _ opportunity: AccountOpportunity, context: SessionPlanningContext
    ) -> [ScoreContribution] {
        var values: [ScoreContribution] = []
        let urgencyValue: Int
        switch opportunity.urgency {
        case .daily: urgencyValue = SessionScoring.dailyOpportunity
        case .weekly: urgencyValue = SessionScoring.weeklyOpportunity
        case .seasonal: urgencyValue = SessionScoring.seasonalOpportunity
        case .none: urgencyValue = 0
        }
        if urgencyValue != 0 {
            values.append(ScoreContribution(
                factor: "opportunityUrgency", value: urgencyValue,
                explanation: "This is a \(opportunity.resetScope.title.lowercased()) opportunity."))
        }
        if opportunity.state == .completeUnclaimed {
            values.append(ScoreContribution(
                factor: "readyToClaim", value: SessionScoring.claimableReward,
                explanation: "ArenaNet reports this reward complete but not claimed."))
        } else if let progress = opportunity.progress, progress.fraction >= 0.75, !progress.isComplete {
            values.append(ScoreContribution(
                factor: "nearCompletion", value: SessionScoring.nearCompletion,
                explanation: "The API-reported progress is at least three quarters complete."))
        }
        let preference = context.preferences.activities[opportunity.type, default: .neutral]
        if preference == .prefer {
            values.append(ScoreContribution(
                factor: "activityPreference", value: SessionScoring.preferredActivity,
                explanation: "\(opportunity.type.title) is preferred for Today planning."))
        } else if preference == .avoid {
            values.append(ScoreContribution(
                factor: "activityPreference", value: SessionScoring.avoidedActivity,
                explanation: "\(opportunity.type.title) is avoided but remains visible."))
        }
        let mapID = context.opportunityLinks[opportunity.id]?.mapID ?? opportunity.mapID
        if let currentMapID = context.currentMapID, currentMapID == mapID {
            values.append(ScoreContribution(
                factor: "sameCurrentMap", value: SessionScoring.sameCurrentMap,
                explanation: "The validated opportunity map is the current map."))
        }
        return values
    }

    private static func opportunityReason(_ opportunity: AccountOpportunity) -> String {
        if opportunity.state == .completeUnclaimed {
            return "ArenaNet account data reports complete progress and an unclaimed reward. Claiming is only available inside Guild Wars 2."
        }
        var parts = ["Incomplete \(opportunity.resetScope.title.lowercased()) opportunity from ArenaNet account data."]
        if let progress = opportunity.progress { parts.append("Progress: \(progress.current) of \(progress.complete).") }
        if let map = opportunity.mapName { parts.append("Validated map: \(map).") }
        return parts.joined(separator: " ")
    }

    private static func taskType(for method: AcquisitionMethodType) -> SessionTaskType {
        switch method {
        case .craft: .craft
        case .tradingPost: .buy
        case .gathering: .gather
        case .vendor, .mapCurrency: .vendor
        case .achievement: .achievement
        case .mysticForge: .mysticForge
        case .worldObjective: .navigate
        case .manual, .unknown: .manual
        }
    }

    private static func taskTitle(method: AcquisitionMethod, name: String, shortage: Int) -> String {
        switch method.type {
        case .gathering: "Gather \(name)"
        case .tradingPost: "Buy \(shortage) \(name)"
        case .craft: "Craft \(name)"
        case .vendor, .mapCurrency: "Get \(name) from a vendor"
        case .achievement: "Earn \(name) from an achievement"
        case .mysticForge: "Create \(name) in the Mystic Forge"
        case .worldObjective: "Visit \(name)"
        case .manual, .unknown: "Resolve \(name)"
        }
    }

    private static func reason(method: AcquisitionMethod, need: Need, shortage: Int, objectives: [MapObjective]) -> String {
        var parts = ["\(shortage) missing for \(need.goals.count == 1 ? need.goals[0].title : "\(need.goals.count) active goals")."]
        if !objectives.isEmpty { parts.append("\(objectives.count) matching mapped location\(objectives.count == 1 ? " is" : "s are") available.") }
        if let description = method.description { parts.append(description) }
        return parts.joined(separator: " ")
    }

    private static func fallbackMethod(for target: AcquisitionTarget) -> AcquisitionMethod {
        AcquisitionMethod(
            id: "engine:manual:\(target.key)", target: target, type: .manual,
            title: "Resolve manually", description: "No known acquisition method is available yet.",
            requirements: [.manual("User verifies how to satisfy this requirement")], location: nil, cost: nil,
            source: KnowledgeSource(
                type: .companionCurated, sourceID: "session-planner-fallback", sourceURL: nil,
                reviewedAt: nil, notes: "Generated unresolved requirement fallback."),
            confidence: .unknown, coverage: .exampleOnly, gatheringCategory: nil, markerSubtype: nil)
    }
}
