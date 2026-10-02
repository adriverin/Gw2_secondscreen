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
            case .loading:
                Section { GWLoadingRows(count: 3) }
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
        .searchable(text: $query, prompt: "Search legendary items")
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
                        .font(.caption.bold()).foregroundStyle(GWPalette.success)
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
                        Text(item.name).font(GWTypography.screen)
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
    var onWork: (() -> Void)? = nil

    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        if let plan = store.legendaryPlan(for: goal, account: account) {
            LegendaryPlanPresentation(plan: plan, onInspectPrice: onInspectPrice, onWork: onWork)
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
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showCompleted = false
    @State private var showOwnedPlan = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onWork: (() -> Void)? = nil

    var body: some View {
        hero
        if plan.ownership == .notOwned || showOwnedPlan {
        GWSectionHeader(title: "Major requirements")
        Toggle("Show completed", isOn: $showCompleted)
            .accessibilityIdentifier("legendary.showCompleted")
        let visible = plan.visibleTopLevel(showCompleted: showCompleted)
        if visible.isEmpty {
            GWCard {
                Text("All major branches are complete.")
                Text("Show completed to review your requirements.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(visible) { node in
            LegendaryRequirementCard(
                node: node, showCompleted: showCompleted,
                onInspectPrice: onInspectPrice)
        }
        } else {
            Button("View Full Plan") { showOwnedPlan = true; showCompleted = true }
                .buttonStyle(.bordered).frame(minHeight: 44)
        }
        coverageCard
        if !plan.pricesUnavailableItemIDs.isEmpty {
            GWErrorBanner(
                message: "Some tradable materials have no current sell listings or could not be priced.",
                stale: false)
        }
    }

    private var hero: some View {
        let item = store.legendaryItems[plan.targetItemID] ?? account.itemMetadata[plan.targetItemID]
        let definition = store.legendaryCatalog?.plan(for: plan.targetItemID)
        return GWPlainSection {
            HStack(spacing: 12) {
                if let item { GWItemIcon(item: item, size: 58) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name).font(GWTypography.hero)
                    Text(definition?.weaponType.map { "Legendary \($0)" } ?? "Legendary")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if plan.ownership != .notOwned {
                Label(plan.ownership == .armory ? "Owned in Legendary Armory ✓" : "Owned in account holdings ✓",
                      systemImage: "checkmark.seal.fill").foregroundStyle(GWPalette.success)
            } else {
                Text("\(plan.topLevelReadyCount) of \(plan.topLevelTotalCount) major requirements ready")
                    .font(.headline).foregroundStyle(.primary)
                    .accessibilityIdentifier("legendary.primaryProgress")
                ProgressView(value: Double(plan.topLevelReadyCount), total: Double(max(1, plan.topLevelTotalCount)))
                    .accessibilityHidden(true)
                HStack(spacing: 18) {
                    Text("\(plan.tradableMissing.count) Tradable")
                    Text("\(plan.accountBoundMissing.count) Account-bound")
                    Text("\(plan.sessionNodes.filter { $0.status == .readyToCraft }.count) Ready now")
                }.font(.caption).foregroundStyle(.secondary)
                if let estimate = store.estimatedBuyNow(for: plan) {
                    LabeledContent("Estimated tradable missing", value: "≈ \(estimate.amount.compactFormatted)")
                        .font(.subheadline)
                }
                Button("What should I work on?") {
                    if let onWork { onWork() } else { navigation.selectedTab = .session }
                }.buttonStyle(GWPrimaryButtonStyle())
            }
        }
    }


    private var coverageCard: some View {
        DisclosureGroup("About this plan") {
            Text("Some acquisition steps may be missing. This plan includes known crafting, vendor and Mystic Forge requirements. World completion and reward-track progress must be checked in game.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, GWSpacing.small)
        }.font(.subheadline).padding(.vertical, GWSpacing.small)
    }

}

private struct LegendaryRequirementCard: View {
    let node: LegendaryProgressNode
    let showCompleted: Bool
    let onInspectPrice: (ItemMetadata, Int) -> Void
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(GWPresentation.motion(reduced: reduceMotion)) { expanded.toggle() } } label: {
                HStack(alignment: .top) {
                    Image(systemName: symbol).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 4) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: GWSpacing.small) {
                                Text(node.name).font(.headline)
                                GWBadge(text: statusTitle, color: color)
                            }
                            VStack(alignment: .leading, spacing: GWSpacing.xSmall) {
                                Text(node.name).font(.headline)
                                GWBadge(text: statusTitle, color: color)
                            }
                        }
                        Text("\(node.ownedQuantity) owned · \(node.missingQuantity) missing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !node.children.isEmpty {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(.tertiary)
                    }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("legendary.requirement.\(node.itemID)")
            if expanded, node.binding == .tradable, node.missingQuantity > 0 {
                Button("Price") {
                    let item = store.legendaryItems[node.itemID]
                        ?? account.itemMetadata[node.itemID]
                        ?? ItemPlaceholder.metadata(id: node.itemID)
                    onInspectPrice(item, node.missingQuantity)
                }
                .buttonStyle(.bordered)
            }
            if expanded, let notes = node.notes {
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
        .padding(.vertical, GWSpacing.xSmall)
    }

    private var statusTitle: String {
        switch node.status {
        case .owned: "OWNED"
        case .readyToCraft: "READY"
        case .accountBoundManual: "ACCOUNT-BOUND"
        case .unknownManual: "MANUAL"
        case .missing:
            if node.binding == .tradable { "BUY" }
            else if node.acquisition == .craft || node.acquisition == .mysticForge { "CRAFT" }
            else { "EARN" }
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
