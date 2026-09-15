import SwiftUI

struct TodayDashboardView: View {
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var sessions: SessionStore
    @State private var filter: TodayFilter = .all
    @State private var showingRewards = false
    @State private var showingDiagnostics = false
    @AppStorage("developer.mode.enabled") private var developerMode = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                summarySection
                claimableSection
                quickWinsSection
                planningSection
                opportunitySections
                if today.snapshot?.hasProgressionPermission == false { permissionSection }
            }
            .navigationTitle("Today")
            .refreshable { await today.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if developerMode {
                        Button { showingDiagnostics = true } label: { Image(systemName: "ladybug") }
                            .accessibilityLabel("Today diagnostics")
                    }
                    Button { Task { await today.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(today.loadState == .loading)
                        .accessibilityLabel("Refresh Today")
                }
            }
            .sheet(isPresented: $showingRewards) { VaultRewardsView() }
            .sheet(isPresented: $showingDiagnostics) { TodayDiagnosticsView() }
            .task {
                DeveloperDiagnostics.shared.recordTodayScreenAppeared()
                await today.refreshIfNeeded()
            }
        }
    }

    @ViewBuilder private var statusSection: some View {
        if today.loadState == .loading && today.snapshot == nil {
            Section { HStack { ProgressView(); Text("Loading today's account state…") } }
        } else if let error = today.errorMessage {
            Section {
                Label(today.isStale ? "Offline • cached Today data" : "Today unavailable", systemImage: "wifi.slash")
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        } else if today.isStale {
            Section { Label("Offline • cached Today data", systemImage: "clock.badge.exclamationmark") }
        }
        if let updated = today.lastUpdatedAt {
            Section {
                LabeledContent("Last updated", value: updated, format: .relative(presentation: .named))
                LabeledContent("Data source", value: today.dataSource.qaLabel)
            }
        }
    }

    private var summarySection: some View {
        Section {
            if let season = today.snapshot?.season {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WIZARD'S VAULT").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(season.title).font(.headline)
                }
            }
            if let meta = today.snapshot?.dailyMeta {
                summaryRow(
                    "Wizard's Vault Daily", value: "\(meta.progress.current) / \(meta.progress.complete)",
                    symbol: meta.state.isComplete ? "checkmark.circle.fill" : "circle.dotted")
                    .accessibilityLabel("Wizard's Vault daily, \(meta.progress.current) of \(meta.progress.complete) complete")
            }
            if let meta = today.snapshot?.weeklyMeta {
                summaryRow(
                    "Weekly", value: "\(meta.progress.current) / \(meta.progress.complete) toward meta",
                    symbol: meta.state.isComplete ? "checkmark.circle.fill" : "calendar.badge.clock")
            }
            summaryRow("Active Goals", value: "\(goals.activeGoals.count)", symbol: "target")
            summaryRow(
                "Current Map",
                value: telemetry.latest?.map.map { "Map \($0.id) • LIVE" } ?? "Not connected",
                symbol: "map")
            if let balance = today.snapshot?.astralAcclaimBalance {
                summaryRow("Astral Acclaim", value: balance.formatted(), symbol: "sparkles")
            } else {
                summaryRow("Astral Acclaim", value: "Balance unavailable", symbol: "sparkles")
            }
            Button("Browse Vault Rewards") { showingRewards = true }
        } header: { Text("Today") }
    }

    @ViewBuilder private var claimableSection: some View {
        let claimable = today.snapshot?.claimable ?? []
        let claimableMetas = [today.snapshot?.dailyMeta, today.snapshot?.weeklyMeta]
            .compactMap { $0 }.filter { $0.state.isClaimable }
        if !claimable.isEmpty || !claimableMetas.isEmpty {
            Section("Ready to Claim") {
                ForEach(claimable) { opportunity in
                    Label(opportunity.title, systemImage: "gift.fill")
                    Text("Ready to claim in game").font(.caption).foregroundStyle(.orange)
                }
                ForEach(claimableMetas, id: \.resetScope) { meta in
                    VStack(alignment: .leading) {
                        Label("\(meta.resetScope == .daily ? "Daily" : "Weekly") meta reward", systemImage: "gift.fill")
                        Text("Ready to claim in game").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("Rewards can only be claimed inside Guild Wars 2.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var quickWinsSection: some View {
        let wins = quickWins
        if !wins.isEmpty {
            Section("Quick Wins") {
                ForEach(wins) { opportunity in
                    NavigationLink { OpportunityDetailView(opportunity: opportunity) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(opportunity.state.isClaimable ? "Claim reward in game" : opportunity.title).font(.headline)
                            Text(quickWinReason(opportunity)).font(.caption).foregroundStyle(.secondary)
                            Text("Why this?").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var planningSection: some View {
        Section {
            if sessions.activeSession != nil {
                NavigationLink { SessionPlannerView() } label: {
                    Label("Open Active Session", systemImage: "play.circle.fill")
                }
            } else {
                NavigationLink { SessionPlannerView() } label: {
                    Label("Plan My Session", systemImage: "checklist")
                }
            }
        } footer: {
            Text("The existing deterministic planner combines active goals, Today opportunities, current map, and your preferences.")
        }
    }

    @ViewBuilder private var opportunitySections: some View {
        Section {
            Picker("Today filter", selection: $filter) {
                ForEach(TodayFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ForEach(groupedOpportunities, id: \.0) { group in
            Section(group.0) {
                if group.1.allSatisfy(\.state.isComplete), !group.1.isEmpty {
                    Label("All supported opportunities complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                ForEach(group.1) { opportunity in
                    NavigationLink { OpportunityDetailView(opportunity: opportunity) } label: {
                        OpportunityRow(opportunity: opportunity)
                    }
                }
            }
        }
    }

    private var permissionSection: some View {
        Section {
            Label("See your daily and weekly progress", systemImage: "key")
            Text("Add the Progression permission to your Guild Wars 2 API key. Public checklists remain visible, but account completion is not inferred.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filtered: [AccountOpportunity] {
        today.opportunities.filter { value in
            switch filter {
            case .all: true
            case .daily: value.resetScope == .daily
            case .weekly: value.resetScope == .weekly
            case .vault: [.wizardVaultDaily, .wizardVaultWeekly, .wizardVaultSpecial].contains(value.type)
            case .pve: value.activity == .pve
            }
        }
    }

    private var groupedOpportunities: [(String, [AccountOpportunity])] {
        OpportunityType.allCases.compactMap { type in
            let values = filtered.filter { $0.type == type }
            return values.isEmpty ? nil : (type.title.uppercased(), values)
        }
    }

    private var quickWins: [AccountOpportunity] {
        Array(today.opportunities.filter { opportunity in
            if opportunity.state.isClaimable { return true }
            guard opportunity.resetScope == .daily, opportunity.state == .incomplete,
                  let progress = opportunity.progress else { return false }
            return progress.fraction >= 0.75
        }.prefix(3))
    }

    private func quickWinReason(_ opportunity: AccountOpportunity) -> String {
        if opportunity.state.isClaimable { return "ArenaNet reports the reward complete and unclaimed." }
        if let progress = opportunity.progress { return "Daily objective is \(progress.current) of \(progress.complete) complete." }
        return "Current daily opportunity."
    }

    private func summaryRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

private struct OpportunityRow: View {
    let opportunity: AccountOpportunity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(opportunity.title).font(.subheadline.bold())
                if let subtitle = opportunity.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                if let progress = opportunity.progress {
                    ProgressView(value: Double(progress.current), total: Double(max(1, progress.complete)))
                    Text("\(progress.current) / \(progress.complete)").font(.caption)
                }
                if let acclaim = opportunity.reward?.astralAcclaim { Text("\(acclaim) Astral Acclaim").font(.caption).foregroundStyle(.secondary) }
                if opportunity.state.isClaimable { Text("Ready to claim in game").font(.caption.bold()).foregroundStyle(.orange) }
                else if opportunity.state == .completeClaimed { Text("Claimed").font(.caption).foregroundStyle(.green) }
                else if opportunity.state == .unknown { Text("Account completion unavailable").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbol: String {
        switch opportunity.state {
        case .completeUnclaimed: "gift.fill"
        case .completeClaimed, .completed: "checkmark.circle.fill"
        case .incomplete: "circle"
        case .unavailable: "nosign"
        case .unknown: "questionmark.circle"
        }
    }
    private var color: Color { opportunity.state.isClaimable ? .orange : (opportunity.state.isComplete ? .green : .secondary) }
    private var accessibilityLabel: String {
        var values = [opportunity.title]
        if let progress = opportunity.progress { values.append("\(progress.current) of \(progress.complete) progress") }
        if let acclaim = opportunity.reward?.astralAcclaim { values.append("\(acclaim) Astral Acclaim") }
        values.append(opportunity.state.accessibilityTitle)
        return values.joined(separator: ", ")
    }
}

private struct OpportunityDetailView: View {
    let opportunity: AccountOpportunity
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var objectives: MapObjectiveStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        List {
            Section {
                LabeledContent("State", value: opportunity.state.accessibilityTitle.capitalized)
                LabeledContent("Reset scope", value: opportunity.resetScope.title)
                LabeledContent("Activity", value: opportunity.activity.rawValue)
                if let progress = opportunity.progress { LabeledContent("Progress", value: "\(progress.current) / \(progress.complete)") }
                if let map = opportunity.mapName { LabeledContent("Map", value: map) }
            }
            if opportunity.state.isClaimable {
                Section { Text("Claim this reward inside Guild Wars 2. The public API is read-only for rewards.") }
            }
            Section("Sources") {
                ForEach(opportunity.provenance) { Text($0.title) }
            }
            Section("Linked Location") {
                if let link = today.opportunityLinks[opportunity.id] {
                    LabeledContent("Map", value: link.mapName ?? "Map \(link.mapID)")
                    LabeledContent("Source", value: link.provenance.title)
                    if let objective = link.objective {
                        Button("Show on Map") {
                            objectives.startGoalRoute(name: opportunity.title, objectives: [objective])
                            navigation.selectedTab = .map
                        }
                    }
                    Button("Remove Link", role: .destructive) { today.removeLink(for: opportunity.id) }
                } else {
                    Text("Locations are never inferred from objective text.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let mapID = telemetry.latest?.map?.id {
                        Button("Link Current Map") {
                            today.linkToMap(opportunity, mapID: mapID, mapName: "Map \(mapID)")
                        }
                        if let point = playerPoint {
                            Button("Link Current Position") {
                                today.linkToCurrentPosition(opportunity, mapID: mapID, position: point)
                            }
                        }
                    }
                    if !objectives.objectives.isEmpty {
                        Menu("Link Existing Map Objective") {
                            ForEach(objectives.objectives.prefix(50)) { objective in
                                Button(objective.name) { today.link(opportunity, to: objective) }
                            }
                        }
                    }
                }
            }
            Section("Diagnostics") {
                LabeledContent("Opportunity ID", value: opportunity.id.rawValue)
                LabeledContent("API identifier", value: opportunity.sourceIdentifier)
            }
        }
        .navigationTitle(opportunity.title)
    }

    private var playerPoint: ContinentPoint? {
        guard telemetry.latest?.positionAvailable == true, let player = telemetry.latest?.player else { return nil }
        return ContinentPoint(x: player.continentX, y: player.continentY)
    }
}

private struct VaultRewardsView: View {
    @EnvironmentObject private var today: TodayStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let wished = rewards.filter { today.isWished($0.id) }
                if !wished.isEmpty {
                    Section("Wanted Rewards") { ForEach(wished) { rewardRow($0, showArithmetic: true) } }
                }
                ForEach(grouped, id: \.0) { group in
                    Section(group.0) { ForEach(group.1) { rewardRow($0, showArithmetic: false) } }
                }
            }
            .navigationTitle("Vault Rewards")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var rewards: [VaultRewardListing] { today.snapshot?.vaultRewards ?? [] }
    private var grouped: [(String, [VaultRewardListing])] {
        Dictionary(grouping: rewards, by: { $0.type.rawValue }).map { ($0.key, $0.value) }
            .sorted { ($0.1.first?.type.sortOrder ?? 9) < ($1.1.first?.type.sortOrder ?? 9) }
    }

    private func rewardRow(_ reward: VaultRewardListing, showArithmetic: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CachedAsyncImage(url: reward.icon) { Image(systemName: "gift") }
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(reward.itemName).font(.headline)
                Text("Cost: \(reward.cost) Astral Acclaim")
                if let limit = reward.purchaseLimit { Text("Purchased: \(reward.purchased ?? 0) / \(limit)") }
                else { Text("Unlimited reward") }
                if reward.isLimitReached { Text("Purchase limit reached").foregroundStyle(.secondary) }
                if showArithmetic, let balance = today.snapshot?.astralAcclaimBalance {
                    Text(balance >= reward.cost ? "Remaining after purchase: \(balance - reward.cost)" : "Need \(reward.cost - balance) more Astral Acclaim")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.font(.caption)
            Spacer()
            Button { today.toggleWish(reward.id) } label: {
                Image(systemName: today.isWished(reward.id) ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(today.isWished(reward.id) ? "Remove from wanted rewards" : "Add to wanted rewards")
        }
    }
}

private struct TodayDiagnosticsView: View {
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var sessions: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = today.snapshot {
                    Section("Refresh") {
                        LabeledContent("Last Today refresh", value: snapshot.timestamp.formatted())
                        LabeledContent("Stale", value: today.isStale ? "Yes" : "No")
                        LabeledContent("Vault season", value: snapshot.season?.title ?? "Unavailable")
                    }
                    Section("Counts") {
                        LabeledContent("Daily objectives", value: "\(snapshot.diagnostics.dailyObjectiveCount)")
                        LabeledContent("Weekly objectives", value: "\(snapshot.diagnostics.weeklyObjectiveCount)")
                        LabeledContent("Special objectives", value: "\(snapshot.diagnostics.specialObjectiveCount)")
                        LabeledContent("Claimable", value: "\(snapshot.diagnostics.claimableCount)")
                        LabeledContent("Session candidates", value: "\(sessions.draftPlan?.diagnostics.candidateCount ?? 0)")
                        LabeledContent("Today-derived candidates", value: "\(sessions.draftPlan?.diagnostics.todayDerivedCandidateCount ?? 0)")
                    }
                    diagnosticIDs("World boss IDs", snapshot.diagnostics.worldBossIDs)
                    diagnosticIDs("Map chest IDs", snapshot.diagnostics.mapChestIDs)
                    diagnosticIDs("Daily crafting IDs", snapshot.diagnostics.dailyCraftingIDs)
                    diagnosticIDs("Raid event IDs", snapshot.diagnostics.raidEventIDs)
                    diagnosticIDs("Dungeon path IDs", snapshot.diagnostics.dungeonPathIDs)
                    diagnosticIDs("Unknown IDs", snapshot.diagnostics.unknownIDs)
                } else {
                    ContentUnavailableView("No Today diagnostics", systemImage: "ladybug")
                }
            }
            .navigationTitle("Today Diagnostics")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func diagnosticIDs(_ title: String, _ values: [String]) -> some View {
        Section(title) { Text(values.isEmpty ? "None" : values.joined(separator: "\n")).font(.caption.monospaced()) }
    }
}

struct TodayCompactView: View {
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var navigation: AppNavigation
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { isExpanded.toggle() } label: {
                HStack {
                    Text("Today")
                    if let daily = today.snapshot?.dailyMeta {
                        Text("\(daily.progress.current)/\(daily.progress.complete) Daily")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline.bold())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Today expanded" : "Today collapsed")
            if isExpanded {
                if let weekly = today.snapshot?.weeklyMeta {
                    Text("Weekly \(weekly.progress.current) / \(weekly.progress.complete)").font(.caption)
                }
                if let claimable = today.snapshot?.diagnostics.claimableCount, claimable > 0 {
                    Text("\(claimable) ready to claim in game").font(.caption).foregroundStyle(.orange)
                }
                Button("Plan Session") { navigation.selectedTab = .session }
                    .buttonStyle(.borderedProminent).tint(GWPalette.accent)
            }
        }.padding(12)
    }
}
