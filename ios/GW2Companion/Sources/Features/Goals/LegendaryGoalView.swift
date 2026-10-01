import SwiftUI

struct LegendaryBrowserView: View {
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var query = ""

    var body: some View {
        let items = store.searchLegendaries(query, account: account)
        let grouped = Dictionary(grouping: items, by: \.category)
        List {
            switch store.legendaryState {
            case let .loading(message):
                Section { ProgressView(message) }
            case let .cached(message):
                Section { Label(message, systemImage: "clock.arrow.circlepath") }
            case let .unavailable(message):
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            case .ready, .idle:
                EmptyView()
            }
            ForEach(LegendaryBrowserCategory.allCases) { category in
                let rows = grouped[category] ?? []
                if !rows.isEmpty {
                    Section(category.title) {
                        ForEach(rows) { item in
                            NavigationLink { LegendaryGoalEditorView(item: item) } label: {
                                legendaryRow(item, plan: store.legendaryPlan(itemID: item.itemID, account: account))
                            }
                        }
                    }
                }
            }
            if items.isEmpty, store.legendaryCatalog != nil {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Legendary")
        .searchable(text: $query, prompt: "Sunrise, staff, 30703")
        .task {
            await store.prepareLegendaries()
        }
    }

    private func legendaryRow(_ item: LegendaryBrowserItem, plan: LegendaryProgressPlan?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon = item.icon {
                CachedAsyncImage(url: icon) {
                    Image(systemName: "sparkles.rectangle.stack").foregroundStyle(GWPalette.accent)
                }.frame(width: 52, height: 52)
            } else {
                Image(systemName: "sparkles.rectangle.stack").foregroundStyle(GWPalette.accent).frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.headline)
                Text(legendaryType(item)).font(.caption).foregroundStyle(.secondary)
                if item.ownership != .notOwned {
                    Label(ownershipText(item.ownership), systemImage: "checkmark.seal.fill")
                        .font(.caption.bold()).foregroundStyle(.green)
                } else if let plan {
                    Text("\(plan.topLevelReadyCount) / \(plan.topLevelTotalCount) major requirements ready")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if let copper = plan.estimatedBuyNowCopper {
                            Text("Tradable ≈ \(CoinAmount(copperValue: copper).compactFormatted)")
                        }
                        if !plan.accountBoundMissing.isEmpty {
                            Text("Account-bound \(plan.accountBoundMissing.count)")
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(item.availability.title).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func legendaryType(_ item: LegendaryBrowserItem) -> String {
        if let weaponType = item.weaponType { return "Legendary \(weaponType)" }
        switch item.category {
        case .weapons: return "Legendary Weapon"
        case .armor: return "Legendary Armor"
        case .trinkets: return "Legendary Trinket or Back Item"
        case .upgradeComponents: return "Legendary Rune or Sigil"
        case .other: return "Legendary Item"
        }
    }

    private func ownershipText(_ state: LegendaryOwnershipState) -> String {
        switch state {
        case .armory: "Owned"
        case .holdings: "In holdings"
        case .notOwned: "Not owned"
        }
    }
}

private struct LegendaryGoalEditorView: View {
    let item: LegendaryBrowserItem
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var priority = GoalPriority.normal

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    if let icon = item.icon {
                        CachedAsyncImage(url: icon) { Image(systemName: "sparkles.rectangle.stack") }
                            .frame(width: 58, height: 58)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name.uppercased()).font(.title3.bold())
                        if let type = item.weaponType { Text("Legendary \(type)").foregroundStyle(.secondary) }
                    }
                }
                Text(item.availability.title)
                Text(ownershipLabel)
                    .foregroundStyle(item.ownership == .notOwned ? Color.secondary : Color.green)
            }
            if item.availability != .none {
                Section {
                    NavigationLink(item.ownership.planActionTitle) {
                        LegendaryBrowserPlanView(item: item)
                    }
                }
            }
            if item.availability == .none {
                Section {
                    Text("This legendary is listed by ArenaNet, but a curated acquisition plan is not included yet.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(GoalPriority.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Button(item.ownership == .notOwned ? "Create Legendary Goal" : "Keep as Goal") {
                    store.addLegendaryGoal(itemID: item.itemID, name: item.name, priority: priority)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(item.availability == .none)
            }
        }
        .navigationTitle("Legendary Goal")
    }

    private var ownershipLabel: String {
        switch item.ownership {
        case .armory: "Owned in Legendary Armory ✓"
        case .holdings: "Owned in account holdings ✓"
        case .notOwned: "Not owned"
        }
    }
}

struct LegendaryGoalContent: View {
    let goal: PlayerGoal
    let onInspectPrice: (ItemMetadata, Int) -> Void

    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        if let plan = store.legendaryPlan(for: goal, account: account) {
            LegendaryPlanPresentation(plan: plan, onInspectPrice: onInspectPrice)
        } else {
            GWCard { Text("Building legendary plan…").foregroundStyle(.secondary) }
        }
    }
}

private struct LegendaryBrowserPlanView: View {
    let item: LegendaryBrowserItem
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var priceInspection: PriceInspection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let plan = store.legendaryPlan(itemID: item.itemID, account: account) {
                    LegendaryPlanPresentation(plan: plan) { item, quantity in
                        priceInspection = PriceInspection(item: item, quantity: quantity)
                    }
                } else {
                    ProgressView("Building legendary plan…")
                }
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $priceInspection) { inspection in
            TradingPostPriceSheet(item: inspection.item, quantity: inspection.quantity)
        }
        .task(id: item.itemID) {
            if let plan = store.legendaryPlan(itemID: item.itemID, account: account) {
                await store.refreshPrices(for: plan)
            }
        }
    }
}

private struct LegendaryPlanPresentation: View {
    let plan: LegendaryProgressPlan
    let onInspectPrice: (ItemMetadata, Int) -> Void
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var showCompleted = false

    var body: some View {
        ownershipCard
        summaryCard
        tradableCard
        accountBoundSection
        readyNowSection
        GWSectionHeader(title: "Dependency plan", subtitle: "Completed branches are collapsed by default")
        Toggle("Show completed", isOn: $showCompleted)
            .accessibilityIdentifier("legendary.showCompleted")
        let visible = plan.visibleTopLevel(showCompleted: showCompleted)
        if visible.isEmpty {
            GWCard {
                Text("All major branches are complete.")
                Text("Turn on Show completed to inspect the full dependency graph.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(visible) { node in
            LegendaryRequirementCard(
                node: node, showCompleted: showCompleted,
                onInspectPrice: onInspectPrice)
        }
        coverageCard
        if !plan.pricesUnavailableItemIDs.isEmpty {
            GWErrorBanner(
                message: "Some tradable materials have no current sell listings or could not be priced.",
                stale: false)
        }
    }

    private var ownershipCard: some View {
        GWCard {
            if plan.ownership == .armory {
                Text(plan.name.uppercased()).font(.title2.bold())
                Label("Owned in Legendary Armory ✓", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                GWBadge(text: "OWNED", color: .green, symbol: "checkmark")
                Text("Armory ownership does not mean this item was crafted on this account.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if plan.ownership == .holdings {
                Text(plan.name.uppercased()).font(.title2.bold())
                Label("Owned in account holdings ✓", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(plan.name.uppercased()).font(.title2.bold())
                Label(plan.progress.label, systemImage: "sparkles.rectangle.stack")
            }
        }
    }

    private var summaryCard: some View {
        GWCard {
            GWSectionHeader(title: "Major Requirements", subtitle: "\(plan.topLevelReadyCount) / \(plan.topLevelTotalCount) ready")
            ProgressView(value: Double(plan.topLevelReadyCount), total: Double(max(1, plan.topLevelTotalCount)))
            LabeledContent("Tradable missing", value: "\(plan.tradableMissing.count) requirements")
            LabeledContent("Account-bound", value: "\(plan.accountBoundMissing.count) requirements")
            LabeledContent("Ready now", value: "\(plan.sessionNodes.filter { $0.status == .readyToCraft }.count) components")
        }
    }

    @ViewBuilder private var tradableCard: some View {
        if !plan.tradableMissing.isEmpty || plan.estimatedBuyNowCopper != nil {
            GWCard {
                GWSectionHeader(title: "Tradable", subtitle: "Current lowest sell offers only")
                if let estimate = store.estimatedBuyNow(for: plan) {
                    LabeledContent("Buy missing", value: "≈ \(estimate.amount.compactFormatted)")
                }
                Text("This is separate from account-bound requirements and is not a total legendary value.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var accountBoundSection: some View {
        if !plan.accountBoundMissing.isEmpty {
            GWSectionHeader(title: "Account-bound", subtitle: "Cannot be purchased on the Trading Post")
            ForEach(plan.accountBoundMissing) { node in
                GWCard {
                    HStack {
                        GWBadge(text: "ACCOUNT-BOUND", color: .orange, symbol: "lock")
                        Spacer()
                        Text("\(node.missingQuantity) missing").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(node.name).font(.headline)
                    Text(node.acquisition.title).font(.caption).foregroundStyle(.secondary)
                    if let notes = node.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    @ViewBuilder private var readyNowSection: some View {
        let ready = plan.sessionNodes.filter { $0.status == .readyToCraft }
        if !ready.isEmpty {
            GWSectionHeader(title: "Ready Now", subtitle: "Known ingredients are satisfied")
            ForEach(ready) { node in
                GWCard {
                    GWBadge(text: "READY", color: .green, symbol: "hammer.fill")
                    Text(node.name).font(.headline)
                }
            }
        }
    }

    private var coverageCard: some View {
        GWCard {
            LabeledContent("Plan coverage", value: plan.coverageTitle)
            Text("Curated mystic-forge, vendor, and crafting relationships only. World completion, WvW reward-track progress, and clover yield are never inferred.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LegendaryRequirementCard: View {
    let node: LegendaryProgressNode
    let showCompleted: Bool
    let onInspectPrice: (ItemMetadata, Int) -> Void
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var expanded = false

    var body: some View {
        GWCard {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top) {
                    Image(systemName: symbol).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name).font(.headline)
                        HStack(spacing: 5) {
                            GWBadge(text: node.actionStatusTitle.uppercased(), color: color, symbol: symbol)
                            if node.binding == .tradable { Text("Tradable") }
                            else { Text("Account-bound") }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        Text("\(node.ownedQuantity) owned • \(node.missingQuantity) missing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !node.children.isEmpty {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }.buttonStyle(.plain)
            if node.binding == .tradable, node.missingQuantity > 0 {
                Button("Price") {
                    let item = store.legendaryItems[node.itemID]
                        ?? account.itemMetadata[node.itemID]
                        ?? ItemPlaceholder.metadata(id: node.itemID)
                    onInspectPrice(item, node.missingQuantity)
                }
                .buttonStyle(.bordered)
            }
            if let notes = node.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            if expanded {
                ForEach(node.visibleChildren(showCompleted: showCompleted)) { child in
                    LegendaryRequirementCard(
                        node: child, showCompleted: showCompleted,
                        onInspectPrice: onInspectPrice)
                        .padding(.leading, 10)
                }
            }
        }
    }

    private var symbol: String {
        switch node.status {
        case .owned: "checkmark.circle.fill"
        case .readyToCraft: "hammer.fill"
        case .missing: "circle"
        case .accountBoundManual: "lock"
        case .unknownManual: "questionmark.circle"
        }
    }

    private var color: Color {
        switch node.status {
        case .owned: .green
        case .readyToCraft: GWPalette.accent
        case .missing: .primary
        case .accountBoundManual, .unknownManual: .orange
        }
    }
}
