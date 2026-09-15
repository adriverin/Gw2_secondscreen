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
                                legendaryRow(item)
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

    private func legendaryRow(_ item: LegendaryBrowserItem) -> some View {
        HStack {
            if let icon = item.icon {
                CachedAsyncImage(url: icon) {
                    Image(systemName: "sparkles.rectangle.stack").foregroundStyle(GWPalette.accent)
                }.frame(width: 40, height: 40)
            } else {
                Image(systemName: "sparkles.rectangle.stack").foregroundStyle(GWPalette.accent).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                HStack(spacing: 8) {
                    Text(ownershipText(item.ownership)).font(.caption)
                        .foregroundStyle(item.ownership == .notOwned ? Color.secondary : Color.green)
                    Text(item.availability.title).font(.caption).foregroundStyle(.secondary)
                }
            }
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
                Text(item.name).font(.headline)
                if let type = item.weaponType { Text(type).foregroundStyle(.secondary) }
                Text(item.availability.title)
                Text(ownershipLabel)
                    .foregroundStyle(item.ownership == .notOwned ? Color.secondary : Color.green)
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
                Button("Create Legendary Goal") {
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
            ownershipCard(plan)
            coverageCard(plan)
            GWSectionHeader(title: "Top-level requirements", subtitle: plan.progress.label)
            ForEach(plan.topLevel) { node in
                LegendaryRequirementCard(node: node, onInspectPrice: onInspectPrice)
            }
            GWCard {
                Text(plan.materialSummary).font(.subheadline)
                Text("Percentages are omitted because gameplay-gated steps are not inferred.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let estimate = store.estimatedBuyNow(for: plan) {
                GWCard {
                    GWSectionHeader(
                        title: "Tradable missing materials",
                        subtitle: "Estimated buy-now from current lowest sells only")
                    LabeledContent("Estimated buy-now", value: estimate.amount.formatted)
                    Text("Account-bound requirements are listed separately and are not given fake market prices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !plan.accountBoundMissing.isEmpty {
                GWSectionHeader(title: "Account-bound requirements", subtitle: "Cannot be purchased on the Trading Post")
                ForEach(plan.accountBoundMissing) { node in
                    GWCard {
                        Label("\(node.name)  \(node.missingQuantity) missing", systemImage: "lock")
                        Text(node.acquisition.title).font(.caption).foregroundStyle(.secondary)
                        if let notes = node.notes {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !plan.pricesUnavailableItemIDs.isEmpty {
                GWErrorBanner(
                    message: "Some tradable materials have no current sell listings or could not be priced.",
                    stale: false)
            }
        } else {
            GWCard { Text("Building legendary plan…").foregroundStyle(.secondary) }
        }
    }

    private func ownershipCard(_ plan: LegendaryProgressPlan) -> some View {
        GWCard {
            if plan.ownership == .armory {
                Label("Owned in Legendary Armory ✓", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Armory ownership does not mean this item was crafted on this account.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if plan.ownership == .holdings {
                Label("Owned in account holdings ✓", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(plan.progress.label, systemImage: "sparkles.rectangle.stack")
            }
        }
    }

    private func coverageCard(_ plan: LegendaryProgressPlan) -> some View {
        GWCard {
            LabeledContent("Plan coverage", value: plan.coverageTitle)
            Text("Curated mystic-forge, vendor, and crafting relationships only. World completion, WvW reward-track progress, and clover yield are never inferred.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LegendaryRequirementCard: View {
    let node: LegendaryProgressNode
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
                        Text("\(node.status.title) • \(node.acquisition.title) • \(node.binding == .tradable ? "Tradable" : "Account bound")")
                            .font(.caption).foregroundStyle(.secondary)
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
                ForEach(node.children) { child in
                    LegendaryRequirementCard(node: child, onInspectPrice: onInspectPrice)
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
