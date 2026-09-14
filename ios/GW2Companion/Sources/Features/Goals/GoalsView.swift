import SwiftUI
import UIKit

struct GoalsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showingAddGoal = false
    @State private var showingArchive = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    goalList
                        .frame(minWidth: 285, idealWidth: 320, maxWidth: 360)
                    Divider()
                    if let id = store.selectedGoalID {
                        NavigationStack { GoalDetailView(goalID: id) }
                    } else {
                        GWEmptyState(
                            title: "Choose a goal", message: "Select a goal or create one to begin planning.",
                            symbol: "target", actionTitle: "Add Goal") { showingAddGoal = true }
                    }
                }
            } else {
                NavigationStack { goalList }
            }
        }
        .sheet(isPresented: $showingAddGoal) { AddGoalView() }
        .task {
            store.setAccountScope(account.account?.id)
            async let achievements: Void = store.prepareAchievements()
            async let recipes: Void = store.prepareRecipes()
            async let progress: Void = account.refreshGoalAccountData()
            _ = await (achievements, recipes, progress)
            await sessions.refreshAPIDerived(recipes: store.recipes, prices: store.marketPrices)
            for goal in store.activeGoals {
                if case let .achievement(id) = goal.type { await store.loadAchievement(id: id) }
            }
        }
    }

    private var goalList: some View {
        List(selection: $store.selectedGoalID) {
            Section {
                if store.activeGoals.isEmpty {
                    ContentUnavailableView(
                        "No Active Goals", systemImage: "target",
                        description: Text("Track an achievement, plan a craft, or add a custom checklist."))
                } else {
                    ForEach(store.activeGoals) { goal in
                        if sizeClass == .regular {
                            GoalRow(goal: goal).tag(goal.id)
                        } else {
                            NavigationLink { GoalDetailView(goalID: goal.id) } label: { GoalRow(goal: goal) }
                        }
                    }
                }
            } header: { Text("Active") }

            if !store.pausedGoals.isEmpty {
                Section("Paused") {
                    ForEach(store.pausedGoals) { goal in
                        if sizeClass == .regular {
                            GoalRow(goal: goal).tag(goal.id)
                        } else {
                            NavigationLink { GoalDetailView(goalID: goal.id) } label: { GoalRow(goal: goal) }
                        }
                    }
                }
            }

            if !store.archivedGoals.isEmpty {
                Section {
                    DisclosureGroup("Completed & Archived", isExpanded: $showingArchive) {
                        ForEach(store.archivedGoals) { goal in
                            if sizeClass == .regular {
                                GoalRow(goal: goal).tag(goal.id)
                            } else {
                                NavigationLink { GoalDetailView(goalID: goal.id) } label: { GoalRow(goal: goal) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { navigation.selectedTab = .session } label: {
                    Label("Plan Session", systemImage: "checklist")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddGoal = true } label: { Label("Add Goal", systemImage: "plus") }
            }
        }
        .refreshable {
            await account.refresh()
            await account.refreshGoalAccountData()
        }
    }
}

private struct GoalRow: View {
    let goal: PlayerGoal
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        let progress = store.progress(for: goal, account: account)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).foregroundStyle(GWPalette.accent)
                Text(goal.title).font(.headline).lineLimit(2)
                Spacer()
                if goal.priority == .high { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
            }
            HStack {
                Text(goal.type.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(progress.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .accessibilityLabel(progress.label)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch goal.type {
        case .achievement: "trophy.fill"
        case .craftItem: "hammer.fill"
        case .custom: "checklist"
        }
    }
}

struct GoalDetailView: View {
    let goalID: UUID
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var sessions: SessionStore
    @State private var selectedRequirement: FlattenedRequirement?
    @State private var linkBitIndex: Int?
    @State private var showingLinkPicker = false
    @State private var showingDiagnostics = false

    var body: some View {
        Group {
            if let goal = store.goals.first(where: { $0.id == goalID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(goal)
                        switch goal.type {
                        case .achievement: achievementContent(goal)
                        case .craftItem: craftingContent(goal)
                        case .custom: customContent(goal)
                        }
                        actionsSection(goal)
                        calculationSection(goal)
                    }
                    .padding()
                    .frame(maxWidth: 850, alignment: .topLeading)
                }
                .navigationTitle(goal.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { statusMenu(goal) }
                .sheet(item: $selectedRequirement) { RequirementDetailView(requirement: $0, goalID: goal.id) }
                .sheet(isPresented: $showingLinkPicker) {
                    ObjectiveLinkPicker(goalID: goal.id, achievementBitIndex: linkBitIndex)
                }
                .task(id: taskID(goal)) {
                    if case let .achievement(id) = goal.type {
                        await store.loadAchievement(id: id)
                        if let tracking = store.achievementTracking(for: goal, account: account) {
                            await store.refreshPrices(for: tracking)
                        }
                    }
                    if let plan = store.craftingPlan(for: goal, account: account) {
                        await store.refreshPrices(for: plan)
                    }
                    await sessions.refreshAPIDerived(recipes: store.recipes, prices: store.marketPrices)
                }
            } else {
                GWEmptyState(title: "Goal unavailable", message: "This goal is no longer in the active account scope.", symbol: "target")
            }
        }
    }

    private func header(_ goal: PlayerGoal) -> some View {
        let progress = store.progress(for: goal, account: account)
        return GWCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title).font(.title2.bold())
                    Text(progress.label).font(.headline).foregroundStyle(GWPalette.accent)
                }
                Spacer()
                GWBadge(text: goal.priority.title, color: goal.priority == .high ? .orange : GWPalette.accent)
            }
            if progress.total > 0 {
                ProgressView(value: progress.fraction).accessibilityLabel(progress.label)
            }
            if let source = goal.sourceReference {
                Label(source.provenance.title, systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func achievementContent(_ goal: PlayerGoal) -> some View {
        if let tracking = store.achievementTracking(for: goal, account: account) {
            GWCard {
                HStack(alignment: .top) {
                    CachedAsyncImage(url: tracking.definition.icon) {
                        Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(GWPalette.accent)
                    }.frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(tracking.definition.totalPoints) achievement points").font(.headline)
                        if !tracking.definition.description.isEmpty {
                            Text(tracking.definition.description.gwPlainText).foregroundStyle(.secondary)
                        }
                        Text(tracking.definition.requirement.gwPlainText)
                    }
                }
            }

            if !tracking.progressAvailable {
                GWErrorBanner(
                    message: "Connect a key with progression permission to see your account progress.",
                    stale: false)
            }

            GWSectionHeader(title: "Objectives", subtitle: "Completion comes only from ArenaNet account progress")
            ForEach(tracking.bits) { bit in
                GWCard {
                    HStack(alignment: .top) {
                        Image(systemName: bit.isComplete == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(bit.isComplete == true ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(bit.title)
                            if let owned = bit.ownershipHint {
                                Text(owned ? "Unlock owned" : "Unlock not found")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let link = goal.mapLinks.first(where: { $0.achievementBitIndex == bit.index }) {
                                Label(link.objective.name, systemImage: "mappin.and.ellipse")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("No map location available")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if bit.isComplete != true {
                            if let link = goal.mapLinks.first(where: { $0.achievementBitIndex == bit.index }) {
                                Menu {
                                    Button("Edit Link") { linkBitIndex = bit.index; showingLinkPicker = true }
                                    Button("Remove Link", role: .destructive) {
                                        store.removeMapLink(link.id, from: goal.id)
                                    }
                                } label: { Image(systemName: "ellipsis.circle") }
                            } else {
                                Button("Link Map Location") { linkBitIndex = bit.index; showingLinkPicker = true }
                                    .font(.caption)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            loadingCard(store.achievementState)
        }
    }

    @ViewBuilder
    private func craftingContent(_ goal: PlayerGoal) -> some View {
        if let plan = store.craftingPlan(for: goal, account: account) {
            if !account.permissions.contains(.inventories) {
                GWErrorBanner(
                    message: "Account inventory unavailable. Showing total recipe requirements only.",
                    stale: false)
            }
            if plan.targetAlreadyOwned {
                GWCard {
                    Label("Target already owned", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("ArenaNet account holdings contain \(plan.targetOwnedQuantity) of the target. This does not reveal how it was obtained.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            recipeOptions(goal, plan: plan)

            GWSectionHeader(title: "Dependency Tree", subtitle: "Recipe expansion with account supply allocated at each node")
            GWCard {
                CraftRequirementTree(node: plan.root)
            }

            GWSectionHeader(title: "Missing Materials", subtitle: "Consolidated globally; account supply is allocated once")
            let missing = plan.flattenedRequirements.filter { $0.missingQuantity > 0 }
            if missing.isEmpty {
                GWCard { Label("All flattened requirements are ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            } else {
                ForEach(missing) { requirement in
                    Button { selectedRequirement = requirement } label: {
                        GWCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(requirementDisplayName(requirement.requirement)).font(.headline)
                                    Text("\(requirement.ownedQuantity) owned • \(requirement.missingQuantity) missing")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(requirement.missingQuantity)").font(.title3.bold())
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                    .accessibilityLabel("\(requirementDisplayName(requirement.requirement)), \(requirement.missingQuantity) missing, \(requirement.ownedQuantity) owned")
                }
            }

            if let estimate = store.estimatedBuyNow(for: plan) {
                GWCard {
                    GWSectionHeader(title: "Current-Price Comparison", subtitle: "Observable lowest sell offers only")
                    LabeledContent("Craft from purchased ingredients", value: estimate.amount.formatted)
                    if let direct = store.estimatedDirectTargetBuyNow(for: plan) {
                        LabeledContent("Buy target directly", value: direct.amount.formatted)
                    }
                    Text("Checked \(estimate.checkedAt.formatted(date: .omitted, time: .shortened))\(estimate.stale ? " • stale cache" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Current-price comparison only; not a claim of true value or optimal play.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error = store.priceError {
                GWErrorBanner(message: "Market prices unavailable: \(error). The material plan remains available.", stale: false)
            }
        } else {
            loadingCard(store.recipeState)
        }
    }

    @ViewBuilder
    private func recipeOptions(_ goal: PlayerGoal, plan: CraftingPlan) -> some View {
        if case let .craftItem(itemID, _) = goal.type,
           let ids = store.recipeIndex?.recipesProducing(itemID: itemID), !ids.isEmpty {
            GWCard {
                GWSectionHeader(title: "Recipe", subtitle: ids.count > 1 ? "Multiple recipes are available" : nil)
                ForEach(ids, id: \.self) { id in
                    if let recipe = store.recipes[id] {
                        let selected = plan.root.recipeID == id
                        Button {
                            store.selectRecipe(id, outputItemID: itemID, for: goal.id)
                        } label: {
                            HStack {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text("Recipe \(id)")
                                    Text("\(recipe.disciplines.joined(separator: ", ")) \(recipe.minRating)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                        let capability = RecipeCapabilityEngine.capability(
                            recipe: recipe, characters: account.characters,
                            unlockedRecipeIDs: account.unlockedRecipeIDs,
                            unlockPermissionAvailable: account.permissions.contains(.unlocks))
                        Text(capabilityText(capability))
                            .font(.caption).foregroundStyle(capability.disciplineSatisfied ? .green : .secondary)
                        if let chatLink = recipe.chatLink {
                            Button("Copy Chat Link") { UIPasteboard.general.string = chatLink }
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func customContent(_ goal: PlayerGoal) -> some View {
        if !goal.notes.isEmpty { GWCard { Text(goal.notes) } }
        GWSectionHeader(title: "Checklist", subtitle: "User-declared progress")
        if goal.checklist.isEmpty {
            GWCard { Text("No checklist items. Use the status menu to complete this manual goal.").foregroundStyle(.secondary) }
        } else {
            ForEach(goal.checklist) { item in
                Button { store.toggleChecklistItem(goalID: goal.id, itemID: item.id) } label: {
                    GWCard {
                        Label(item.title, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isComplete ? .green : .primary)
                    }
                }.buttonStyle(.plain)
            }
        }
        if !goal.mapLinks.isEmpty {
            GWSectionHeader(title: "Linked Map Locations", subtitle: "User declared")
            ForEach(goal.mapLinks) { link in
                GWCard {
                    HStack {
                        Label(link.objective.name, systemImage: "mappin.and.ellipse")
                        Spacer()
                        Button(role: .destructive) { store.removeMapLink(link.id, from: goal.id) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        Button("Link Current Map Objective") {
            linkBitIndex = nil
            showingLinkPicker = true
        }.buttonStyle(.bordered)
    }

    @ViewBuilder
    private func actionsSection(_ goal: PlayerGoal) -> some View {
        let actions = suggestedActions(goal)
        GWSectionHeader(title: "What Can I Do Now?", subtitle: "Conservative, deterministic suggestions")
        ForEach(actions.prefix(6)) { action in
            GWCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.title).font(.headline)
                        Text(action.reason).font(.caption).foregroundStyle(.secondary)
                        Text("Why this? • \(action.confidence.rawValue) • score \(action.score)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if [.navigate, .gather].contains(action.type), !action.objectiveIDs.isEmpty {
                        Button("Navigate") { navigate(action, goal: goal) }
                            .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                    } else if action.type == .craft, let itemID = action.itemID,
                              let item = store.craftableItems[itemID] ?? store.achievementItems[itemID] {
                        Button("Plan") { store.addCraftingGoal(item: item, quantity: 1, priority: goal.priority) }
                            .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                    }
                }
            }
        }
    }

    private func calculationSection(_ goal: PlayerGoal) -> some View {
        DisclosureGroup("Calculation & Diagnostics", isExpanded: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 7) {
                LabeledContent("Goal type", value: goal.type.title)
                LabeledContent("Goal ID", value: goal.id.uuidString)
                if let source = goal.sourceReference {
                    LabeledContent("Source", value: source.apiPath ?? source.provenance.title)
                }
                if let plan = store.craftingPlan(for: goal, account: account) {
                    LabeledContent("Graph nodes", value: "\(plan.nodeCount)")
                    LabeledContent("Graph depth", value: "\(plan.maximumDepth)")
                    LabeledContent("Flattened requirements", value: "\(plan.flattenedRequirements.count)")
                    LabeledContent("Graph safeguards", value: "\(plan.issues.count) notices")
                }
                ForEach(suggestedActions(goal)) { action in
                    Text("\(action.score) • \(action.title): \(action.reason)").font(.caption)
                }
                if let refreshed = account.accountLastRefreshedAt {
                    LabeledContent("Account refreshed", value: refreshed.formatted())
                }
            }.padding(.top, 10)
        }
        .padding()
        .background(GWPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    @ToolbarContentBuilder
    private func statusMenu(_ goal: PlayerGoal) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Priority", selection: Binding(
                    get: { goal.priority }, set: { store.setPriority($0, for: goal.id) })) {
                    ForEach(GoalPriority.allCases) { Text($0.title).tag($0) }
                }
                Button("Pin as Active") { store.setStatus(.active, for: goal.id) }
                Button("Unpin and Pause") { store.setStatus(.paused, for: goal.id) }
                if case .custom = goal.type {
                    Button("Complete") { store.setStatus(.completed, for: goal.id) }
                }
                Button("Archive", role: .destructive) { store.setStatus(.archived, for: goal.id) }
                Button("Refresh Account") { Task { await account.refresh() } }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func suggestedActions(_ goal: PlayerGoal) -> [SuggestedAction] {
        var names = store.craftableItems.mapValues(\.name)
        account.itemMetadata.forEach { names[$0.key] = $0.value.name }
        store.achievementItems.forEach { names[$0.key] = $0.value.name }
        return SuggestedActionEngine.actions(
            for: goal, craftingPlan: store.craftingPlan(for: goal, account: account),
            achievement: store.achievementTracking(for: goal, account: account),
            context: SuggestedActionContext(
                currentMapID: telemetry.latest?.map?.id,
                playerPosition: playerPoint, mapObjectives: objectives.objectives,
                prices: store.marketPrices, itemNames: names,
                craftableItemIDs: Set(store.recipeIndex?.recipeIDsByOutputItem.keys.map { $0 } ?? [])))
    }

    private func navigate(_ action: SuggestedAction, goal: PlayerGoal) {
        let linked = goal.mapLinks.map(\.objective)
        let all = objectives.objectives + linked
        let wanted = action.objectiveIDs.compactMap { id in all.first { $0.id == id } }
        if action.type == .gather { objectives.applyPreset(.gather) }
        objectives.startGoalRoute(name: goal.title, objectives: wanted)
        navigation.selectedTab = .map
    }

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }

    private func taskID(_ goal: PlayerGoal) -> String {
        "\(goal.id)-\(goal.selectedRecipeIDs)-\(account.accountLastRefreshedAt?.timeIntervalSince1970 ?? 0)-\(store.recipeIndex?.builtAt.timeIntervalSince1970 ?? 0)"
    }

    private func requirementDisplayName(_ requirement: Requirement) -> String {
        switch requirement {
        case let .item(id):
            store.craftableItems[id]?.name ?? account.itemMetadata[id]?.name ?? store.achievementItems[id]?.name ?? "Item \(id)"
        case let .currency(id): account.currencies[id]?.name ?? "Currency \(id)"
        case let .guildUpgrade(id): "Guild Upgrade \(id)"
        case let .unknown(type, id): "\(type) \(id)"
        }
    }

    private func loadingCard(_ state: GoalMetadataLoadState) -> some View {
        GWCard {
            switch state {
            case .idle: Text("Waiting to load…")
            case let .loading(message): ProgressView(message)
            case .ready: Text("No data was returned.")
            case let .unavailable(message): Label(message, systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func capabilityText(_ capability: CraftingCapability) -> String {
        let discipline = capability.discipline ?? "Required discipline"
        let skill = capability.disciplineSatisfied
            ? "Can craft: \(discipline) \(capability.highestRating) • \(capability.characterName ?? "account")"
            : "Requires \(discipline) \(capability.requiredRating); highest \(capability.highestRating)"
        return "\(skill) • recipe \(capability.recipeAvailability.rawValue)"
    }
}

private struct CraftRequirementTree: View {
    let node: CraftRequirementNode
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(node.children) { child in
                        CraftRequirementTree(node: child)
                            .padding(.leading, 8)
                    }
                }
                .padding(.top, 8)
            } label: {
                row
            }
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(displayName).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(node.ownedQuantity) owned • \(node.missingQuantity) missing")
                    .font(.caption)
                    .foregroundStyle(node.missingQuantity == 0 ? .green : .secondary)
            }
            HStack(spacing: 5) {
                Text("\(node.requiredQuantity) required")
                if let recipeID = node.recipeID {
                    Text("• Recipe \(recipeID)")
                }
                if !node.issues.isEmpty {
                    Text("• \(node.issues.count) notice\(node.issues.count == 1 ? "" : "s")")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        switch node.requirement {
        case let .item(id):
            store.craftableItems[id]?.name ?? account.itemMetadata[id]?.name ?? store.achievementItems[id]?.name ?? "Item \(id)"
        case let .currency(id): account.currencies[id]?.name ?? "Currency \(id)"
        case let .guildUpgrade(id): "Guild Upgrade \(id)"
        case let .unknown(type, id): "\(type) \(id)"
        }
    }
}

struct RequirementDetailView: View {
    let requirement: FlattenedRequirement
    let goalID: UUID
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddMethod = false

    var body: some View {
        NavigationStack {
            List {
                Section("Requirement") {
                    LabeledContent("Total required", value: "\(requirement.requiredQuantity)")
                    LabeledContent("Owned allocated", value: "\(requirement.ownedQuantity)")
                    LabeledContent("Missing", value: "\(requirement.missingQuantity)")
                }
                if case let .item(id) = requirement.requirement,
                   let holding = account.holdings.first(where: { $0.itemID == id }) {
                    Section("Your Account Holdings") {
                        ForEach(holding.locations) { location in
                            LabeledContent(location.location.title, value: "\(location.quantity)")
                        }
                    }
                }
                Section("Why?") {
                    ForEach(requirement.provenance.dependencies) { dependency in
                        VStack(alignment: .leading) {
                            LabeledContent(dependency.label, value: dependency.detail)
                            Text(dependency.provenance.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if case let .item(id) = requirement.requirement,
                   let estimate = MarketCalculator.buyNow(price: store.marketPrices[id], quantity: requirement.missingQuantity) {
                    Section("Market") {
                        LabeledContent("Lowest sell offer", value: CoinAmount(copperValue: estimate.unitCopper).formatted)
                        LabeledContent("Estimated buy-now cost", value: estimate.amount.formatted)
                        Text("\(requirement.missingQuantity) × \(CoinAmount(copperValue: estimate.unitCopper).formatted), checked \(estimate.checkedAt.formatted(date: .omitted, time: .shortened)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Ways To Get It") {
                    let values = sessions.methods(for: target)
                    if values.isEmpty {
                        Text("No known acquisition methods. Add a local note or resolve this requirement manually.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(values) { method in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(method.title).font(.headline)
                                    Text(method.type.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use for this goal") {
                                    sessions.chooseMethod(method.type, goalID: goalID, requirementID: requirement.id)
                                }.font(.caption)
                            }
                            if let description = method.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(method.source.displayTitle) • \(method.coverage.rawValue) coverage")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Button("Add acquisition method") { showingAddMethod = true }
                }
            }
            .navigationTitle(displayName)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingAddMethod) {
                AddAcquisitionMethodView(target: target)
            }
        }
    }

    private var target: AcquisitionTarget {
        switch requirement.requirement {
        case let .item(id): .item(id: id, quantity: max(1, requirement.missingQuantity))
        case let .currency(id): .currency(id: id, quantity: max(1, requirement.missingQuantity))
        case let .guildUpgrade(id): .custom("guild-upgrade:\(id)", quantity: max(1, requirement.missingQuantity))
        case let .unknown(type, id): .custom("unknown:\(type):\(id)", quantity: max(1, requirement.missingQuantity))
        }
    }

    private var displayName: String {
        switch requirement.requirement {
        case let .item(id):
            store.craftableItems[id]?.name ?? account.itemMetadata[id]?.name ?? store.achievementItems[id]?.name ?? "Item \(id)"
        case let .currency(id): account.currencies[id]?.name ?? "Currency \(id)"
        case let .guildUpgrade(id): "Guild Upgrade \(id)"
        case let .unknown(type, id): "\(type) \(id)"
        }
    }
}

private struct AddAcquisitionMethodView: View {
    let target: AcquisitionTarget
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var includeCurrentMap = false
    @State private var includeCurrentPosition = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Method") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if telemetry.latest?.map?.id != nil {
                    Section("Location") {
                        Toggle("Save current map", isOn: $includeCurrentMap)
                        Toggle("Save exact current position", isOn: $includeCurrentPosition)
                            .disabled(playerPoint == nil)
                        Text("Exact coordinates are saved only when live telemetry provides them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Acquisition Method")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await sessions.addUserMethod(
                                target: target, title: title, notes: notes,
                                mapID: includeCurrentMap || includeCurrentPosition ? telemetry.latest?.map?.id : nil,
                                currentPosition: includeCurrentPosition ? playerPoint : nil)
                            dismiss()
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }
}

private struct ObjectiveLinkPicker: View {
    let goalID: UUID
    let achievementBitIndex: Int?
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if let current = currentPositionObjective {
                    Section("Manual Location") {
                        Button { select(current) } label: {
                            Label("Use Current Player Position", systemImage: "location.fill")
                        }
                        Text("This coordinate comes from live telemetry; the achievement link itself is user-declared.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Existing Map Objectives") {
                    ForEach(objectives.search(search)) { objective in
                        Button { select(objective) } label: {
                            VStack(alignment: .leading) {
                                Text(objective.name)
                                Text("\(objective.type.title) • map \(objective.mapId)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Link Map Location")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }

    private func select(_ objective: MapObjective) {
        store.link(objective, to: goalID, achievementBitIndex: achievementBitIndex)
        dismiss()
    }

    private var currentPositionObjective: MapObjective? {
        guard let mapID = telemetry.latest?.map?.id, telemetry.latest?.positionAvailable == true,
              let player = telemetry.latest?.player else { return nil }
        return MapObjective(
            id: MapObjectiveID("user:\(UUID().uuidString)"), mapId: mapID,
            name: "User-selected location", type: .custom,
            continentX: player.continentX, continentY: player.continentY,
            source: .user, chatLink: nil, level: nil,
            description: "Saved from live player position", state: .unknown)
    }
}
