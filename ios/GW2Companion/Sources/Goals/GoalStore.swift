import Foundation

enum GoalMetadataLoadState: Equatable {
    case idle
    case loading(String)
    case ready
    case cached(String)
    case unavailable(String)
}

enum GoalPersistence {
    private static let prefix = "phase4.goals.v1."

    static func scopeKey(accountID: String?) -> String {
        let raw = accountID ?? "local-anonymous"
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return prefix + String(safe)
    }

    static func load(accountID: String?, defaults: UserDefaults) -> [PlayerGoal] {
        guard let data = defaults.data(forKey: scopeKey(accountID: accountID)),
              let snapshot = try? JSONDecoder().decode(GoalScopeSnapshot.self, from: data),
              snapshot.schemaVersion == GoalScopeSnapshot.schemaVersion else { return [] }
        return snapshot.goals
    }

    static func save(_ goals: [PlayerGoal], accountID: String?, defaults: UserDefaults) {
        let snapshot = GoalScopeSnapshot(schemaVersion: GoalScopeSnapshot.schemaVersion, goals: goals)
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: scopeKey(accountID: accountID))
    }
}

@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var goals: [PlayerGoal] = []
    @Published private(set) var achievementGroups: [AchievementGroup] = []
    @Published private(set) var achievementCategories: [AchievementCategory] = []
    @Published private(set) var achievements: [Int: AchievementDefinition] = [:]
    @Published private(set) var achievementItems: [Int: ItemMetadata] = [:]
    @Published private(set) var achievementSkins: [Int: SkinMetadata] = [:]
    @Published private(set) var achievementMinis: [Int: MiniMetadata] = [:]
    @Published private(set) var recipes: [Int: RecipeDefinition] = [:]
    @Published private(set) var recipeIndex: RecipeOutputIndex?
    @Published private(set) var craftableItems: [Int: ItemMetadata] = [:]
    @Published private(set) var marketPrices: [Int: TimedCommercePrice] = [:]
    @Published private(set) var pricesUpdatedAt: Date?
    @Published private(set) var achievementState: GoalMetadataLoadState = .idle
    @Published private(set) var recipeState: GoalMetadataLoadState = .idle
    @Published private(set) var priceError: String?
    @Published var selectedGoalID: UUID?

    private let api: GW2APIClient
    private let cache: MetadataDiskCache
    private let defaults: UserDefaults
    private var accountID: String?
    private var didPrepareAchievements = false
    private var didPrepareAchievementSearch = false
    private var didPrepareRecipes = false

    init(
        api: GW2APIClient, cache: MetadataDiskCache = MetadataDiskCache(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.cache = cache
        self.defaults = defaults
        goals = GoalPersistence.load(accountID: nil, defaults: defaults)
    }

    var activeGoals: [PlayerGoal] {
        goals.filter { $0.status == .active }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt < $1.createdAt
        }
    }

    var pausedGoals: [PlayerGoal] { goals.filter { $0.status == .paused }.sorted { $0.createdAt < $1.createdAt } }
    var archivedGoals: [PlayerGoal] { goals.filter { [.archived, .completed].contains($0.status) }.sorted { $0.createdAt > $1.createdAt } }
    var selectedGoal: PlayerGoal? { selectedGoalID.flatMap { id in goals.first { $0.id == id } } }

    func setAccountScope(_ id: String?) {
        guard accountID != id else { return }
        GoalPersistence.save(goals, accountID: accountID, defaults: defaults)
        accountID = id
        goals = GoalPersistence.load(accountID: id, defaults: defaults)
        selectedGoalID = activeGoals.first?.id
    }

    func add(_ goal: PlayerGoal) {
        goals.append(goal)
        selectedGoalID = goal.id
        persist()
    }

    func deleteAllLocalGoals() {
        goals = []
        selectedGoalID = nil
        persist()
    }

    func trackAchievement(_ achievement: AchievementDefinition, priority: GoalPriority = .normal) {
        if let existing = goals.first(where: { $0.type == .achievement(achievement.id) && $0.status != .archived }) {
            selectedGoalID = existing.id
            return
        }
        add(PlayerGoal(
            title: achievement.name, type: .achievement(achievement.id), priority: priority,
            sourceReference: GoalSourceReference(
                apiPath: "/v2/achievements/\(achievement.id)", apiID: achievement.id,
                provenance: .arenaNetPublic)))
    }

    func addCraftingGoal(item: ItemMetadata, quantity: Int, priority: GoalPriority = .normal) {
        add(PlayerGoal(
            title: item.name, type: .craftItem(itemID: item.id, quantity: max(1, quantity)),
            priority: priority, sourceReference: GoalSourceReference(
                apiPath: "/v2/items/\(item.id)", apiID: item.id, provenance: .arenaNetPublic)))
    }

    func addCustomGoal(
        title: String, notes: String, priority: GoalPriority,
        checklistTitles: [String]
    ) {
        add(PlayerGoal(
            title: title, type: .custom, priority: priority,
            sourceReference: GoalSourceReference(apiPath: nil, apiID: nil, provenance: .userDeclared),
            notes: notes,
            checklist: checklistTitles.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ManualChecklistItem(title: $0) }))
    }

    func update(_ goal: PlayerGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
        persist()
    }

    func setStatus(_ status: GoalStatus, for goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].status = status
        persist()
    }

    func setPriority(_ priority: GoalPriority, for goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].priority = priority
        persist()
    }

    func toggleChecklistItem(goalID: UUID, itemID: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let itemIndex = goals[goalIndex].checklist.firstIndex(where: { $0.id == itemID }) else { return }
        goals[goalIndex].checklist[itemIndex].isComplete.toggle()
        persist()
    }

    func link(_ objective: MapObjective, to goalID: UUID, achievementBitIndex: Int? = nil) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].mapLinks.removeAll { $0.achievementBitIndex == achievementBitIndex }
        goals[index].mapLinks.append(GoalMapLink(achievementBitIndex: achievementBitIndex, objective: objective))
        persist()
    }

    func removeMapLink(_ linkID: UUID, from goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].mapLinks.removeAll { $0.id == linkID }
        persist()
    }

    func selectRecipe(_ recipeID: Int, outputItemID: Int, for goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }),
              recipeIndex?.recipesProducing(itemID: outputItemID).contains(recipeID) == true else { return }
        goals[index].selectedRecipeIDs[outputItemID] = recipeID
        persist()
    }

    func prepareAchievements() async {
        guard !didPrepareAchievements else { return }
        didPrepareAchievements = true
        achievementState = .loading("Loading achievement categories…")
        do {
            async let groups = api.achievementGroups()
            async let categories = api.achievementCategories()
            achievementGroups = try await groups
            achievementCategories = try await categories
            achievementState = .ready
        } catch {
            didPrepareAchievements = false
            achievementState = .unavailable(error.userFacingMessage(fallback: "Achievement data couldn’t be loaded. Try again later."))
        }
    }

    func loadAchievements(in category: AchievementCategory) async {
        achievementState = .loading("Loading \(category.name)…")
        do {
            let loaded = try await api.achievements(ids: category.achievements)
            achievements.merge(loaded) { _, new in new }
            await resolveAchievementBits(in: Array(loaded.values))
            achievementState = .ready
        } catch {
            achievementState = .unavailable(error.userFacingMessage(fallback: "Achievement data couldn’t be loaded. Try again later."))
        }
    }

    func loadAchievement(id: Int) async {
        guard achievements[id] == nil else { return }
        do {
            let loaded = try await api.achievements(ids: [id])
            achievements.merge(loaded) { _, new in new }
            await resolveAchievementBits(in: Array(loaded.values))
        } catch {
            achievementState = .unavailable(error.userFacingMessage(fallback: "Achievement data couldn’t be loaded. Try again later."))
        }
    }

    /// Full definitions are loaded only when the user actually searches. This keeps app launch
    /// and ordinary category browsing light while making subsequent keystrokes entirely local.
    func prepareAchievementSearchIndex() async {
        guard !didPrepareAchievementSearch else { return }
        didPrepareAchievementSearch = true
        achievementState = .loading("Building local achievement search index…")
        do {
            let ids = Array(Set(achievementCategories.flatMap(\.achievements))).sorted()
            let loaded = try await api.achievements(ids: ids)
            achievements.merge(loaded) { _, new in new }
            await resolveAchievementBits(in: Array(loaded.values))
            achievementState = .ready
        } catch {
            didPrepareAchievementSearch = false
            achievementState = .unavailable(error.userFacingMessage(fallback: "Achievement data couldn’t be loaded. Try again later."))
        }
    }

    func prepareRecipes() async {
        guard !didPrepareRecipes else { return }
        didPrepareRecipes = true
        recipeState = .loading("Preparing crafting catalog…")
        if let saved = await cache.load(RecipeOutputIndex.self, named: "recipe-output-index-v1"),
           saved.schemaVersion == RecipeOutputIndex.schemaVersion {
            recipeIndex = saved
            recipeState = .ready
        }
        recipes = await api.cachedRecipes()
        if !recipes.isEmpty {
            recipeIndex = RecipeOutputIndex(recipes: recipes)
            recipeState = .ready
            await loadCraftableItemMetadata()
        }
        do {
            let ids = try await api.recipeIDs()
            let batches = GW2APIClient.chunks(of: ids, size: 200)
            var collected = recipes
            for (index, batch) in batches.enumerated() {
                let percent = batches.isEmpty ? 0 : Int((Double(index) / Double(max(batches.count, 1))) * 100)
                if recipeIndex == nil {
                    recipeState = .loading("Preparing crafting catalog… \(percent)%")
                }
                if let part = try? await api.recipes(ids: batch, priority: .low) {
                    collected.merge(part) { _, new in new }
                    recipes = collected
                    recipeIndex = RecipeOutputIndex(recipes: collected)
                    if index == 0 || index.isMultiple(of: 5) {
                        await loadCraftableItemMetadata()
                    }
                }
            }
            recipes = collected
            let built = RecipeOutputIndex(recipes: collected)
            recipeIndex = built
            await cache.save(built, named: "recipe-output-index-v1")
            if recipeIndex == nil || (recipeIndex?.recipeIDsByOutputItem.isEmpty ?? true && collected.isEmpty) {
                didPrepareRecipes = false
                recipeState = .unavailable("Couldn't build the crafting catalog.")
                return
            }
            recipeState = .loading("Preparing crafting catalog… indexing items")
            await loadCraftableItemMetadata()
            recipeState = .ready
        } catch {
            if recipeIndex != nil {
                if error as? GW2APIError == .networkUnavailable {
                    recipeState = .cached("Offline — using saved catalog")
                } else {
                    recipeState = .cached("Couldn't update catalog — using saved catalog")
                }
            } else {
                didPrepareRecipes = false
                recipeState = .unavailable(error.userFacingMessage(fallback: "Couldn't build the crafting catalog."))
            }
        }
    }

    func searchAchievements(_ query: String) -> [AchievementDefinition] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var categoryByAchievement: [Int: String] = [:]
        for category in achievementCategories {
            for id in category.achievements {
                categoryByAchievement[id, default: ""] += " " + category.name.lowercased()
            }
        }
        return achievements.values.filter { achievement in
            needle.isEmpty || [achievement.name, achievement.description, achievement.requirement]
                .contains { $0.lowercased().contains(needle) } ||
                (categoryByAchievement[achievement.id]?.contains(needle) ?? false)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func searchCraftableItems(_ query: String) -> [ItemMetadata] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return craftableItems.values.filter {
            !$0.name.isEmpty && $0.name.localizedCaseInsensitiveContains(needle)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func craftingPlan(for goal: PlayerGoal, account: AccountStore) -> CraftingPlan? {
        guard case let .craftItem(itemID, quantity) = goal.type, let recipeIndex else { return nil }
        return CraftingPlanner.build(
            targetItemID: itemID, quantity: quantity, recipes: recipes, index: recipeIndex,
            selectedRecipeIDs: goal.selectedRecipeIDs, holdings: account.holdings,
            wallet: account.wallet, holdingsAvailable: account.permissions.contains(.inventories),
            calculatedAt: account.accountLastRefreshedAt ?? Date())
    }

    func achievementTracking(for goal: PlayerGoal, account: AccountStore) -> AchievementTrackingState? {
        guard case let .achievement(id) = goal.type, let definition = achievements[id] else { return nil }
        return AchievementTrackingEngine.merge(
            definition: definition, progress: account.achievementProgress[id],
            progressPermissionAvailable: account.permissions.contains(.progression),
            items: achievementItems, skins: achievementSkins, minis: achievementMinis,
            unlockedSkinIDs: account.unlockedSkinIDs, unlockedMiniIDs: account.unlockedMiniIDs,
            unlockPermissionAvailable: account.permissions.contains(.unlocks))
    }

    func progress(for goal: PlayerGoal, account: AccountStore) -> GoalProgress {
        switch goal.type {
        case .achievement:
            return achievementTracking(for: goal, account: account)?.goalProgress ?? GoalProgress(
                ready: 0, total: 0, label: "Loading achievement…", isAuthoritativeCompletion: false)
        case .craftItem:
            return craftingPlan(for: goal, account: account)?.progress ?? GoalProgress(
                ready: 0, total: 0, label: "Building recipe plan…", isAuthoritativeCompletion: false)
        case .custom:
            let ready = goal.checklist.filter(\.isComplete).count
            let total = goal.checklist.count
            return GoalProgress(
                ready: ready, total: total,
                label: total == 0 ? "Manual goal" : "\(ready) of \(total) checklist items complete",
                isAuthoritativeCompletion: false)
        }
    }

    func refreshPrices(for plan: CraftingPlan, force: Bool = false) async {
        var ids = plan.flattenedRequirements.compactMap { requirement -> Int? in
            guard requirement.missingQuantity > 0, case let .item(id) = requirement.requirement else { return nil }
            return id
        }
        ids.append(plan.targetItemID)
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await api.commercePrices(ids: ids, force: force)
            marketPrices.merge(loaded) { _, new in new }
            pricesUpdatedAt = Date()
            priceError = nil
        } catch {
            priceError = error.userFacingMessage(fallback: "Trading Post prices couldn’t be refreshed. Showing saved prices where possible.")
        }
    }

    func refreshPrices(for achievement: AchievementTrackingState, force: Bool = false) async {
        let ids = achievement.bits.compactMap { bit -> Int? in
            guard bit.isComplete != true, case let .item(id) = bit.bit else { return nil }
            return id
        }
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await api.commercePrices(ids: ids, force: force)
            marketPrices.merge(loaded) { _, new in new }
            pricesUpdatedAt = Date()
            priceError = nil
        } catch {
            priceError = error.userFacingMessage(fallback: "Trading Post prices couldn’t be refreshed. Showing saved prices where possible.")
        }
    }

    func estimatedBuyNow(for plan: CraftingPlan) -> MarketEstimate? {
        var total: Int64 = 0
        var oldest = Date()
        var stale = false
        var count = 0
        for requirement in plan.flattenedRequirements where requirement.missingQuantity > 0 {
            guard case let .item(id) = requirement.requirement,
                  let estimate = MarketCalculator.buyNow(
                    price: marketPrices[id], quantity: requirement.missingQuantity) else { continue }
            let result = total.addingReportingOverflow(estimate.copper)
            guard !result.overflow else { return nil }
            total = result.partialValue
            oldest = min(oldest, estimate.checkedAt)
            stale = stale || estimate.stale
            count += 1
        }
        return count > 0 ? MarketEstimate(
            copper: total, unitCopper: 0, quantity: count, checkedAt: oldest, stale: stale) : nil
    }

    func estimatedDirectTargetBuyNow(for plan: CraftingPlan) -> MarketEstimate? {
        MarketCalculator.buyNow(
            price: marketPrices[plan.targetItemID],
            quantity: max(0, plan.targetQuantity - plan.targetOwnedQuantity))
    }

    private func loadCraftableItemMetadata() async {
        guard let recipeIndex else { return }
        let ids = Array(recipeIndex.recipeIDsByOutputItem.keys)
        let loaded = (try? await api.items(ids: ids, priority: .low)) ?? [:]
        var merged = craftableItems
        merged.merge(loaded) { _, new in new }
        for id in ids where merged[id] == nil {
            merged[id] = ItemPlaceholder.metadata(id: id)
        }
        craftableItems = merged
    }

    private func resolveAchievementBits(in values: [AchievementDefinition]) async {
        let bits = values.flatMap { $0.bits ?? [] }
        let itemIDs = bits.compactMap(\.referencedItemID)
        let skinIDs = bits.compactMap(\.referencedSkinID)
        let miniIDs = bits.compactMap(\.referencedMiniID)
        async let items = try? api.items(ids: itemIDs)
        async let skins = try? api.skins(ids: skinIDs)
        async let minis = try? api.minis(ids: miniIDs)
        let loaded = await (items, skins, minis)
        if let values = loaded.0 { achievementItems.merge(values) { _, new in new } }
        if let values = loaded.1 { achievementSkins.merge(values) { _, new in new } }
        if let values = loaded.2 { achievementMinis.merge(values) { _, new in new } }
    }

    private func persist() {
        GoalPersistence.save(goals, accountID: accountID, defaults: defaults)
    }
}
