import SwiftUI

struct SessionPlannerView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var today: TodayStore
    @State private var selectedTask: SessionTask?
    @State private var showingPreferences = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            Group {
                if let active = sessions.activeSession {
                    activeSession(active)
                } else {
                    planner
                }
            }
            .navigationTitle(sessions.activeSession == nil ? "Plan My Session" : "Your Session")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Session history")
                    Button { showingPreferences = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Planning preferences")
                }
            }
            .sheet(item: $selectedTask) { SessionTaskDetailView(task: $0) }
            .sheet(isPresented: $showingPreferences) { PlanningPreferencesView() }
            .sheet(isPresented: $showingHistory) { SessionHistoryView() }
            .task {
                await sessions.prepare(recipes: goals.recipes, prices: goals.marketPrices)
            }
            .onChange(of: telemetry.latest?.map?.id) { _, value in sessions.observeMapChange(value) }
        }
    }

    private var planner: some View {
        List {
            Section("Planning Horizon") {
                Picker("Duration", selection: $sessions.parameters.duration) {
                    ForEach(SessionDuration.allCases) { Text($0.title).tag($0) }
                }
                Text("This is a planning horizon, not a promise of real-world task duration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Focus") {
                Picker("Goals", selection: Binding(
                    get: { sessions.parameters.selectedGoalIDs == nil ? "all" : "selected" },
                    set: { value in
                        sessions.parameters.selectedGoalIDs = value == "all" ? nil : Set(goals.activeGoals.map(\.id))
                    })) {
                    Text("All active goals").tag("all")
                    Text("Selected goals").tag("selected")
                }
                if sessions.parameters.selectedGoalIDs != nil {
                    ForEach(goals.activeGoals) { goal in
                        Toggle(goal.title, isOn: Binding(
                            get: { sessions.parameters.selectedGoalIDs?.contains(goal.id) == true },
                            set: { enabled in
                                if enabled { sessions.parameters.selectedGoalIDs?.insert(goal.id) }
                                else { sessions.parameters.selectedGoalIDs?.remove(goal.id) }
                            }))
                    }
                }
                Toggle("Stay near current map", isOn: $sessions.parameters.stayNearCurrentMap)
                methodToggle("Gathering", .gathering)
                methodToggle("Crafting", .craft)
                methodToggle("Trading Post", .tradingPost)
                methodToggle("Achievement objectives", .worldObjective)
                methodToggle("Manual / unknown", .manual)
            }
            Section {
                Button("Create Plan") { createPlan() }
                    .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                    .disabled(goals.activeGoals.isEmpty && today.opportunities.allSatisfy { $0.state.isComplete || $0.state == .unknown })
                if goals.activeGoals.isEmpty && today.opportunities.isEmpty {
                    Text("Activate a goal or refresh Today opportunities before planning.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = sessions.knowledgeError {
                Section("Acquisition Catalog") {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Text("Cached sessions and user-declared methods remain available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let plan = sessions.draftPlan {
                Section {
                    if plan.tasks.isEmpty {
                        ContentUnavailableView(
                            "No useful tasks found", systemImage: "checklist.unchecked",
                            description: Text("Enable another acquisition method, select another goal, or refresh account data."))
                    } else {
                        ForEach(Array(plan.tasks.enumerated()), id: \.element.id) { index, task in
                            taskRow(task, number: index + 1, active: false)
                        }
                        Button("Start Session") {
                            let snapshot = SessionPlanningAdapter.snapshot(account: account, tasks: plan.tasks)
                            sessions.startDraft(
                                snapshot: snapshot, todaySnapshot: today.progressSnapshot,
                                playerPosition: playerPoint)
                        }
                        .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                    }
                } header: {
                    Text("Your Session")
                } footer: {
                    Text("\(plan.diagnostics.candidateCount) candidates • \(plan.diagnostics.selectedCount) selected • \(plan.diagnostics.planningDurationMilliseconds.formatted(.number.precision(.fractionLength(1)))) ms")
                }
            }
            dataDetails
            privacy
        }
    }

    private func activeSession(_ active: ActiveSession) -> some View {
        List {
            if let changedMap = sessions.mapChangePending {
                Section {
                    Label("You changed to map \(changedMap).", systemImage: "map")
                    Button("Update Session Plan") { sessions.replan(context: context()) }
                    Button("Keep Current Plan") { sessions.keepCurrentPlanAfterMapChange() }
                }
            }
            if let next = active.tasks.first(where: { $0.state == .pending }) {
                Section("Next") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(next.title).font(.title3.bold())
                        Text(next.reason).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if next.mapID != nil || !next.mapObjectiveIDs.isEmpty {
                                Button("Open Map") { startMapTask(next) }
                                    .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                            }
                            Button("Why this?") { selectedTask = next }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Tasks") {
                ForEach(Array(active.tasks.enumerated()), id: \.element.id) { index, task in
                    VStack(alignment: .leading, spacing: 8) {
                        taskRow(task, number: index + 1, active: true)
                        HStack {
                            if task.state == .pending || task.state == .doLater {
                                Button(task.type == .gather || task.type == .navigate ? "Mark Visited" : "Complete") {
                                    sessions.updateTask(task.id, state: task.type == .gather || task.type == .navigate ? .visited : .completed)
                                }
                                Button("Skip") { sessions.updateTask(task.id, state: .skipped) }
                                Button("Do Later") { sessions.updateTask(task.id, state: .doLater) }
                            }
                            Button(task.isLocked ? "Unlock" : "Lock") {
                                sessions.updateTask(task.id, locked: !task.isLocked)
                            }
                        }.font(.caption)
                    }
                }
            }
            Section {
                Button("Refresh Progress") {
                    Task {
                        await account.refresh()
                        await today.refresh()
                        if let tasks = sessions.activeSession?.tasks {
                            sessions.updateAccountSnapshot(SessionPlanningAdapter.snapshot(account: account, tasks: tasks))
                            sessions.updateTodaySnapshot(today.progressSnapshot)
                            sessions.replan(context: context())
                        }
                    }
                }
                Button("Recalculate Plan") { sessions.replan(context: context()) }
                Button("End Session") { sessions.endSession() }
                    .foregroundStyle(.red)
            } footer: {
                Text("A visit does not prove a gathering yield. Refresh Progress compares account quantities without inferring why they changed.")
            }
            dataDetails
        }
    }

    private func taskRow(_ task: SessionTask, number: Int, active: Bool) -> some View {
        Button { selectedTask = task } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)").font(.headline).foregroundStyle(GWPalette.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title).font(.headline).foregroundStyle(.primary)
                        if task.isLocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    if let quantity = task.quantity { Text("\(quantity) missing").font(.caption).foregroundStyle(.secondary) }
                    Text("Helps: \(task.benefitTitles.isEmpty ? "Today" : task.benefitTitles.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(active ? task.state.rawValue.capitalized : "Score \(task.scoreBreakdown.total) • Why this?")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func methodToggle(_ title: String, _ method: AcquisitionMethodType) -> some View {
        Toggle(title, isOn: Binding(
            get: { sessions.parameters.enabledMethods.contains(method) },
            set: { enabled in
                if enabled { sessions.parameters.enabledMethods.insert(method) }
                else { sessions.parameters.enabledMethods.remove(method) }
            }))
    }

    private var dataDetails: some View {
        Section("Data Used For This Plan") {
            LabeledContent("Account holdings", value: account.accountLastRefreshedAt.map(relativeTime) ?? "Unavailable")
            LabeledContent("Recipes", value: goals.recipeIndex == nil ? "Unavailable" : "ArenaNet API")
            LabeledContent("Current position", value: playerPoint == nil ? "Unavailable" : "Live from your PC")
            LabeledContent("Gathering locations", value: "Companion curated • partial")
            LabeledContent("Prices", value: goals.marketPrices.isEmpty ? "Stale / unavailable" : "ArenaNet API")
            if let catalog = sessions.catalog {
                LabeledContent("Catalog", value: catalog.catalogVersion)
                LabeledContent("Coverage", value: catalog.coverage.rawValue)
            }
        }
    }

    private var privacy: some View {
        Section("Privacy") {
            Text("Your live gameplay telemetry stays between your PC and device. Session plans and history remain local.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func createPlan() {
        sessions.createPlan(context: context())
    }

    private func context() -> SessionPlanningContext {
        SessionPlanningAdapter.context(
            goals: goals.activeGoals, goalStore: goals, account: account,
            objectives: objectives.objectives + goals.activeGoals.flatMap { $0.mapLinks.map(\.objective) },
            currentMapID: telemetry.latest?.map?.id, playerPosition: playerPoint,
            methods: sessions.knowledgeMethods, preferences: sessions.preferences,
            parameters: sessions.parameters, opportunities: today.opportunities,
            opportunityLinks: today.opportunityLinks)
    }

    private func startMapTask(_ task: SessionTask) {
        let linked = goals.activeGoals.flatMap { $0.mapLinks.map(\.objective) }
        let all = objectives.objectives + linked + today.userLinkedObjectives
        var route = task.mapObjectiveIDs.compactMap { id in all.first { $0.id == id } }
        if route.isEmpty, let methodID = task.acquisitionMethodID,
           let method = sessions.knowledgeMethods.first(where: { $0.id == methodID }),
           let location = method.location, let mapID = location.mapID,
           let x = location.continentX, let y = location.continentY {
            route = [MapObjective(
                id: MapObjectiveID("acquisition:\(method.id)"), mapId: mapID,
                name: method.title, type: .custom, continentX: x, continentY: y,
                source: method.source.type == .userDeclared ? .user : .bundledGathering,
                chatLink: nil, level: nil, description: method.description, state: .unknown)]
        }
        if task.type == .gather { objectives.applyPreset(.gather) }
        if !route.isEmpty { objectives.startGoalRoute(name: task.title, objectives: route) }
        navigation.selectedTab = .map
    }

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }

    private func relativeTime(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

struct SessionTaskDetailView: View {
    let task: SessionTask
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Why this?") {
                    Text(task.reason)
                    LabeledContent("Planning score", value: "\(task.scoreBreakdown.total)")
                }
                Section("Score Breakdown") {
                    ForEach(task.scoreBreakdown.contributions) { contribution in
                        VStack(alignment: .leading, spacing: 3) {
                            LabeledContent(contribution.factor, value: contribution.value.formatted(.number.sign(strategy: .always())))
                            Text(contribution.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Goals") {
                    if task.relatedGoalTitles.isEmpty { Text("No goal source") }
                    else { ForEach(task.relatedGoalTitles, id: \.self) { Text($0) } }
                }
                if let opportunities = task.relatedOpportunityTitles, !opportunities.isEmpty {
                    Section("Today Opportunities") {
                        ForEach(opportunities, id: \.self) { Text($0) }
                    }
                }
                Section("Sources") {
                    ForEach(Array(task.knowledgeSources.enumerated()), id: \.offset) { _, source in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.displayTitle)
                            if let reviewed = source.reviewedAt {
                                Text("Reviewed \(reviewed.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let notes = source.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let coverage = task.coverage {
                        LabeledContent("Coverage", value: coverage.rawValue.capitalized)
                    }
                }
                Section("Diagnostics") {
                    LabeledContent("Candidate ID", value: task.id.uuidString)
                    LabeledContent("Deduplication key", value: task.deduplicationKey)
                    LabeledContent("Acquisition method", value: task.acquisitionMethodID ?? "None")
                    LabeledContent("Map", value: task.mapID.map(String.init) ?? "None")
                }
            }
            .navigationTitle(task.title)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct PlanningPreferencesView: View {
    @EnvironmentObject private var sessions: SessionStore
    @Environment(\.dismiss) private var dismiss
    private let methods: [AcquisitionMethodType] = [.gathering, .tradingPost, .craft, .vendor, .mysticForge, .manual]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(methods) { method in
                        Picker(method.title, selection: Binding(
                            get: { sessions.preferences.global[method, default: .neutral] },
                            set: { sessions.setGlobalPreference($0, for: method) })) {
                            ForEach(AcquisitionPreferenceLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                } header: {
                    Text("Planning Preferences")
                } footer: {
                    Text("Preferences affect ranking, not availability. Requirement override > goal override > global preference > default.")
                }
                Section("Today Preferences") {
                    ForEach([
                        OpportunityType.wizardVaultDaily, .wizardVaultWeekly, .worldBoss,
                        .mapChest, .dailyCrafting, .raidEncounter, .dungeonPath
                    ], id: \.self) { type in
                        Picker(type.title, selection: Binding(
                            get: { sessions.preferences.activities[type, default: .neutral] },
                            set: { sessions.preferences.activities[type] = $0 })) {
                            ForEach(AcquisitionPreferenceLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
            }
            .navigationTitle("Preferences")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct SessionHistoryView: View {
    @EnvironmentObject private var sessions: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if sessions.history.isEmpty {
                    ContentUnavailableView("No Recent Sessions", systemImage: "clock")
                }
                ForEach(sessions.history) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("\(entry.completedTaskCount) of \(entry.totalTaskCount) tasks • \(entry.goalCount) goals")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(entry.accountChanges) { change in
                            Text("\(change.kind.rawValue.capitalized) \(change.numericID): account quantity changed \(change.delta.formatted(.number.sign(strategy: .always())))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(entry.todayChanges ?? []) { change in
                            Text("\(change.label): \(change.before) → \(change.after) changed during this session")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Recent Sessions")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct ActiveSessionCompactView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var navigation: AppNavigation
    @Binding var isExpanded: Bool

    var body: some View {
        if let active = sessions.activeSession {
            VStack(alignment: .leading, spacing: 8) {
                Button { isExpanded.toggle() } label: {
                    HStack {
                        Text("Session").font(.subheadline.bold())
                        if let next = active.tasks.first(where: { $0.state == .pending }) {
                            Text(next.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Session expanded" : "Session collapsed")
                if isExpanded {
                    if let next = active.tasks.first(where: { $0.state == .pending }) {
                        Text("Next: \(next.title)").font(.subheadline.bold()).lineLimit(2)
                        Text("Helps \(next.relatedGoalIDs.count) goal\(next.relatedGoalIDs.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("Plan complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button("Open Session") { navigation.selectedTab = .session }
                        .buttonStyle(.borderedProminent).tint(GWPalette.accent)
                }
            }.padding(12)
        }
    }
}
