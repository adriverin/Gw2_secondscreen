import Foundation

struct SessionPersistenceSnapshot: Codable {
    static let schemaVersion = 1
    let schemaVersion: Int
    var preferences: PlanningPreferences
    var userMethods: [AcquisitionMethod]
    var activeSession: ActiveSession?
    var history: [SessionHistoryEntry]
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var knowledgeMethods: [AcquisitionMethod] = []
    @Published private(set) var catalog: AcquisitionCatalog?
    @Published private(set) var knowledgeError: String?
    @Published var preferences = PlanningPreferences() { didSet { persist() } }
    @Published var parameters = SessionParameters()
    @Published private(set) var draftPlan: SessionPlan?
    @Published private(set) var activeSession: ActiveSession?
    @Published private(set) var history: [SessionHistoryEntry] = []
    @Published private(set) var userMethods: [AcquisitionMethod] = []
    @Published private(set) var mapChangePending: Int?

    private let knowledgeStore = AcquisitionKnowledgeStore()
    private let defaults: UserDefaults
    private var accountID: String?
    private var isRestoring = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore(accountID: nil)
    }

    func setAccountScope(_ id: String?) {
        guard accountID != id else { return }
        persist()
        accountID = id
        restore(accountID: id)
        Task { await mergeKnowledge() }
    }

    func deleteAllLocalSessionsAndHistory() {
        activeSession = nil
        draftPlan = nil
        history = []
        userMethods = []
        mapChangePending = nil
        persist()
    }

    func prepare(
        provider: any AcquisitionCatalogProvider = BundledCatalogProvider(),
        recipes: [Int: RecipeDefinition] = [:], prices: [Int: TimedCommercePrice] = [:]
    ) async {
        do {
            try await knowledgeStore.load(provider: provider)
            await knowledgeStore.replaceUserDeclared(with: userMethods)
            await knowledgeStore.replaceAPIDerived(with: AcquisitionMethodFactory.apiDerived(recipes: recipes, prices: prices))
            catalog = await knowledgeStore.catalogMetadata
            knowledgeMethods = await knowledgeStore.allMethods()
            knowledgeError = nil
        } catch {
            // User data and an existing plan remain usable offline even if the bundle is damaged.
            knowledgeError = error.userFacingMessage(fallback: "Acquisition data couldn’t be loaded. Your saved plans are still available.")
            await knowledgeStore.replaceUserDeclared(with: userMethods)
            await knowledgeStore.replaceAPIDerived(with: AcquisitionMethodFactory.apiDerived(recipes: recipes, prices: prices))
            knowledgeMethods = await knowledgeStore.allMethods()
        }
    }

    func refreshAPIDerived(recipes: [Int: RecipeDefinition], prices: [Int: TimedCommercePrice]) async {
        await knowledgeStore.replaceAPIDerived(with: AcquisitionMethodFactory.apiDerived(recipes: recipes, prices: prices))
        await mergeKnowledge()
    }

    func methods(for target: AcquisitionTarget) -> [AcquisitionMethod] {
        knowledgeMethods.filter { $0.target.key == target.key }
    }

    func addUserMethod(
        target: AcquisitionTarget, title: String, notes: String,
        mapID: Int?, currentPosition: ContinentPoint?
    ) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let location: AcquisitionLocation? = if let mapID, let currentPosition {
            AcquisitionLocation(
                mapID: mapID, continentX: currentPosition.x, continentY: currentPosition.y,
                objectiveID: nil, label: "Saved player position", locationPrecision: .exactCoordinate)
        } else if let mapID {
            AcquisitionLocation(
                mapID: mapID, continentX: nil, continentY: nil,
                objectiveID: nil, label: "User-selected map", locationPrecision: .mapOnly)
        } else { nil }
        let method = AcquisitionMethod(
            id: "user:\(UUID().uuidString)", target: target, type: .manual,
            title: trimmed, description: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            requirements: [], location: location, cost: nil,
            source: KnowledgeSource(
                type: .userDeclared, sourceID: nil, sourceURL: nil, reviewedAt: Date(),
                notes: "Saved locally by the player."),
            confidence: .userProvided, coverage: .exampleOnly,
            gatheringCategory: nil, markerSubtype: nil)
        userMethods.append(method)
        await knowledgeStore.addUserDeclared(method)
        await mergeKnowledge()
        persist()
    }

    func setGlobalPreference(_ level: AcquisitionPreferenceLevel, for method: AcquisitionMethodType) {
        preferences.global[method] = level
    }

    func chooseMethod(_ method: AcquisitionMethodType?, goalID: UUID, requirementID: String) {
        let key = PlanningPreferences.requirementKey(goalID: goalID, requirementID: requirementID)
        preferences.requirementOverrides[key] = method
    }

    func createPlan(context: SessionPlanningContext) {
        draftPlan = SessionPlanner.plan(context: context)
    }

    func startDraft(
        snapshot: SessionAccountSnapshot, todaySnapshot: TodayProgressSnapshot? = nil,
        playerPosition: ContinentPoint?
    ) {
        guard let draftPlan, !draftPlan.tasks.isEmpty else { return }
        activeSession = ActiveSession(
            id: UUID(), createdAt: Date(), endedAt: nil,
            planningHorizon: draftPlan.parameters.duration,
            initialMapID: draftPlan.currentMapID, initialPlayerPosition: playerPosition,
            initialAccountSnapshot: snapshot, latestAccountSnapshot: snapshot,
            initialTodaySnapshot: todaySnapshot, latestTodaySnapshot: todaySnapshot,
            tasks: draftPlan.tasks)
        mapChangePending = nil
        persist()
    }

    func updateTask(_ taskID: UUID, state: SessionTaskState? = nil, locked: Bool? = nil) {
        guard let index = activeSession?.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let state { activeSession?.tasks[index].state = state }
        if let locked { activeSession?.tasks[index].isLocked = locked }
        persist()
    }

    func updateAccountSnapshot(_ snapshot: SessionAccountSnapshot) {
        activeSession?.latestAccountSnapshot = snapshot
        persist()
    }

    func updateTodaySnapshot(_ snapshot: TodayProgressSnapshot?) {
        guard let snapshot else { return }
        activeSession?.latestTodaySnapshot = snapshot
        persist()
    }

    func replan(context: SessionPlanningContext) {
        guard let activeSession else {
            draftPlan = SessionPlanner.plan(context: context)
            return
        }
        self.activeSession = SessionPlanner.replan(activeSession, context: context)
        mapChangePending = nil
        persist()
    }

    func observeMapChange(_ mapID: Int?) {
        guard let activeSession, let mapID,
              let reference = activeSession.tasks.first(where: { $0.state == .pending })?.mapID ?? activeSession.initialMapID,
              reference != mapID else { return }
        mapChangePending = mapID
    }

    func keepCurrentPlanAfterMapChange() { mapChangePending = nil }

    func endSession(at date: Date = Date()) {
        guard var session = activeSession else { return }
        session.endedAt = date
        let maps = Set(session.tasks.compactMap { task in
            [.visited, .completed].contains(task.state) ? task.mapID : nil
        }).sorted()
        let todayChanges: [TodayProgressChange]?
        if let before = session.initialTodaySnapshot, let after = session.latestTodaySnapshot {
            todayChanges = TodayProgressDiff.changes(from: before, to: after)
        } else {
            todayChanges = nil
        }
        let entry = SessionHistoryEntry(
            id: session.id, startedAt: session.createdAt, endedAt: date,
            planningHorizon: session.planningHorizon,
            completedTaskCount: session.completedTaskCount, totalTaskCount: session.tasks.count,
            goalCount: session.helpedGoalIDs.count, mapsVisited: maps,
            objectiveVisits: session.tasks.filter { $0.state == .visited }.count,
            accountChanges: SessionAccountDiff.changes(
                from: session.initialAccountSnapshot, to: session.latestAccountSnapshot),
            todayChanges: todayChanges)
        history.insert(entry, at: 0)
        if history.count > 30 { history = Array(history.prefix(30)) }
        activeSession = nil
        draftPlan = nil
        mapChangePending = nil
        persist()
    }

    private func mergeKnowledge() async {
        knowledgeMethods = await knowledgeStore.allMethods()
        catalog = await knowledgeStore.catalogMetadata
    }

    private func key(accountID: String?) -> String {
        let raw = accountID ?? "local-anonymous"
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return "phase5.session.v1." + String(safe)
    }

    private func restore(accountID: String?) {
        isRestoring = true
        defer { isRestoring = false }
        guard let data = defaults.data(forKey: key(accountID: accountID)),
              let snapshot = try? JSONDecoder().decode(SessionPersistenceSnapshot.self, from: data),
              snapshot.schemaVersion == SessionPersistenceSnapshot.schemaVersion else {
            preferences = PlanningPreferences()
            userMethods = []
            activeSession = nil
            history = []
            return
        }
        preferences = snapshot.preferences
        userMethods = snapshot.userMethods
        activeSession = snapshot.activeSession
        history = snapshot.history
    }

    private func persist() {
        guard !isRestoring else { return }
        let snapshot = SessionPersistenceSnapshot(
            schemaVersion: SessionPersistenceSnapshot.schemaVersion,
            preferences: preferences, userMethods: userMethods,
            activeSession: activeSession, history: history)
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: key(accountID: accountID))
    }
}

enum SessionPlanningAdapter {
    @MainActor
    static func goals(
        from goals: [PlayerGoal], goalStore: GoalStore, account: AccountStore
    ) -> [PlanningGoal] {
        goals.map { goal in
            switch goal.type {
            case let .craftItem(itemID, quantity):
                let plan = goalStore.craftingPlan(for: goal, account: account)
                var requirements = plan?.flattenedRequirements.map { value in
                    PlanningRequirement(
                        id: value.id, target: target(for: value.requirement, quantity: value.requiredQuantity),
                        requiredQuantity: value.requiredQuantity,
                        name: name(for: value.requirement, goalStore: goalStore, account: account),
                        provenance: [.arenaNetPublic, .arenaNetAccount, .derived], craftReady: value.missingQuantity == 0)
                } ?? []
                let targetOwned = account.holdings.first(where: { $0.itemID == itemID })?.totalQuantity ?? 0
                if targetOwned < quantity {
                    requirements.append(PlanningRequirement(
                        id: "goal-target:\(itemID)", target: .item(id: itemID, quantity: quantity),
                        requiredQuantity: quantity, name: goal.title,
                        provenance: [.arenaNetPublic, .arenaNetAccount, .derived],
                        craftReady: plan?.flattenedRequirements.allSatisfy { $0.missingQuantity == 0 } == true))
                }
                return PlanningGoal(
                    id: goal.id, title: goal.title, priority: goal.priority,
                    requirements: requirements, linkedObjectives: goal.mapLinks.map(\.objective),
                    fallbackReason: requirements.isEmpty ? "The recipe dependency plan is not available yet." : nil)
            case .achievement:
                return PlanningGoal(
                    id: goal.id, title: goal.title, priority: goal.priority, requirements: [],
                    linkedObjectives: goal.mapLinks.map(\.objective),
                    fallbackReason: goal.mapLinks.isEmpty ? "Inspect the tracked achievement for its next incomplete step." : nil)
            case .custom:
                return PlanningGoal(
                    id: goal.id, title: goal.title, priority: goal.priority, requirements: [],
                    linkedObjectives: goal.mapLinks.map(\.objective),
                    fallbackReason: "Continue the next incomplete user-declared checklist step.")
            }
        }
    }

    @MainActor
    static func context(
        goals: [PlayerGoal], goalStore: GoalStore, account: AccountStore,
        objectives: [MapObjective], currentMapID: Int?, playerPosition: ContinentPoint?,
        methods: [AcquisitionMethod], preferences: PlanningPreferences,
        parameters: SessionParameters, opportunities: [AccountOpportunity] = [],
        opportunityLinks: [OpportunityID: TodayOpportunityLink] = [:]
    ) -> SessionPlanningContext {
        SessionPlanningContext(
            goals: self.goals(from: goals, goalStore: goalStore, account: account),
            holdings: Dictionary(uniqueKeysWithValues: account.holdings.map { ($0.itemID, $0.totalQuantity) }),
            currencies: Dictionary(uniqueKeysWithValues: account.wallet.map { ($0.id, $0.value) }),
            acquisitionMethods: methods, preferences: preferences, parameters: parameters,
            currentMapID: currentMapID, playerPosition: playerPosition, mapObjectives: objectives,
            opportunities: opportunities, opportunityLinks: opportunityLinks)
    }

    @MainActor
    static func snapshot(account: AccountStore, tasks: [SessionTask], at date: Date = Date()) -> SessionAccountSnapshot {
        let itemIDs = Set(tasks.compactMap { $0.target?.kind == .item ? $0.target?.numericID : nil })
        let currencyIDs = Set(tasks.compactMap { $0.target?.kind == .currency ? $0.target?.numericID : nil })
        let holdings = Dictionary(uniqueKeysWithValues: account.holdings.filter { itemIDs.contains($0.itemID) }.map { ($0.itemID, $0.totalQuantity) })
        let currencies = Dictionary(uniqueKeysWithValues: account.wallet.filter { currencyIDs.contains($0.id) }.map { ($0.id, $0.value) })
        return SessionAccountSnapshot(timestamp: date, relevantHoldings: holdings, relevantCurrencies: currencies)
    }

    private static func target(for requirement: Requirement, quantity: Int) -> AcquisitionTarget {
        switch requirement {
        case let .item(id): .item(id: id, quantity: quantity)
        case let .currency(id): .currency(id: id, quantity: quantity)
        case let .guildUpgrade(id): .custom("guild-upgrade:\(id)", quantity: quantity)
        case let .unknown(type, id): .custom("unknown:\(type):\(id)", quantity: quantity)
        }
    }

    @MainActor
    private static func name(for requirement: Requirement, goalStore: GoalStore, account: AccountStore) -> String {
        switch requirement {
        case let .item(id): goalStore.craftableItems[id]?.name ?? account.itemMetadata[id]?.name ?? goalStore.achievementItems[id]?.name ?? "Item \(id)"
        case let .currency(id): account.currencies[id]?.name ?? "Currency \(id)"
        case let .guildUpgrade(id): "Guild Upgrade \(id)"
        case let .unknown(type, id): "\(type) \(id)"
        }
    }
}
