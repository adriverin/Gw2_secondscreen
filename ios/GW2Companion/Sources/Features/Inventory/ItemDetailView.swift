import SwiftUI

struct InspectedItem: Identifiable {
    let id = UUID()
    let item: ItemMetadata
    let quantity: Int
    let stats: SelectedItemStats?
    let skinID: Int?
    let upgrades: [Int]
    let infusions: [Int]
    let binding: String?
    let boundTo: String?

    init(item: ItemMetadata, quantity: Int = 1, slot: InventorySlot? = nil) {
        self.item = item
        self.quantity = quantity
        stats = slot?.stats
        skinID = slot?.skin
        upgrades = slot?.upgrades ?? []
        infusions = slot?.infusions ?? []
        binding = slot?.binding
        boundTo = slot?.boundTo
    }

    init(item: ItemMetadata, equipment: CharacterEquipment) {
        self.item = item
        quantity = 1
        stats = equipment.stats
        skinID = equipment.skin
        upgrades = equipment.upgrades ?? []
        infusions = equipment.infusions ?? []
        binding = equipment.binding
        boundTo = equipment.boundTo
    }
}

struct ItemDetailView: View {
    let inspected: InspectedItem
    let metadata: [Int: ItemMetadata]
    var skins: [Int: SkinMetadata] = [:]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var priceLoading = true

    private var attributes: [ItemAttribute] {
        if let selected = inspected.stats?.attributes {
            return selected.map { ItemAttribute(attribute: $0.key, modifier: $0.value) }
                .sorted { $0.attribute < $1.attribute }
        }
        return inspected.item.details?.infixUpgrade?.attributes ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        GWItemIcon(item: inspected.item, size: 94)
                        Text(GWPresentation.itemName(inspected.item)).font(.title3.bold()).multilineTextAlignment(.center)
                        HStack {
                            Text(inspected.item.rarity).foregroundStyle(GWPalette.rarity(inspected.item.rarity))
                            if let type = itemType { Text("• \(type)") }
                            if let level = inspected.item.level, level > 0 { Text("• Level \(level)") }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }

                if !attributes.isEmpty {
                    Section("Attributes") {
                        ForEach(attributes) { attribute in
                            LabeledContent(displayAttribute(attribute.attribute), value: "+\(attribute.modifier)")
                        }
                    }
                }

                if let skinID = inspected.skinID, let skin = skins[skinID] {
                    Section("Skin") { metadataRow(name: skin.name, icon: skin.icon, rarity: skin.rarity) }
                }

                if !inspected.upgrades.isEmpty {
                    Section("Upgrades") {
                        ForEach(inspected.upgrades, id: \.self) { id in
                            if let item = metadata[id] { metadataRow(name: item.name, icon: item.icon, rarity: item.rarity) }
                            else { Text("Item details unavailable").foregroundStyle(.secondary) }
                        }
                    }
                }

                if !inspected.infusions.isEmpty {
                    Section("Infusions") {
                        ForEach(inspected.infusions, id: \.self) { id in
                            if let item = metadata[id] { metadataRow(name: item.name, icon: item.icon, rarity: item.rarity) }
                            else { Text("Infusion details unavailable").foregroundStyle(.secondary) }
                        }
                    }
                }

                if let holding = account.holdings.first(where: { $0.itemID == inspected.item.id }) {
                    Section("You own") {
                        LabeledContent("Total", value: holding.totalQuantity.formatted()).monospacedDigit()
                        ForEach(holding.locations) { location in
                            LabeledContent(location.location.title, value: location.quantity.formatted()).monospacedDigit()
                        }
                    }
                } else if inspected.quantity > 1 {
                    Section { LabeledContent("Quantity", value: inspected.quantity.formatted()) }
                }
                let related = goals.activeGoals.filter { goal in
                    if case let .craftItem(id, _) = goal.type, id == inspected.item.id { return true }
                    if let plan = goals.legendaryPlan(for: goal, account: account) {
                        return plan.sessionNodes.contains { $0.itemID == inspected.item.id }
                    }
                    return goals.craftingPlan(for: goal, account: account)?.flattenedRequirements.contains { requirement in
                        if case let .item(id) = requirement.requirement { return id == inspected.item.id }
                        return false
                    } == true
                }
                if !related.isEmpty {
                    Section("Used by your goals") {
                        ForEach(related) { goal in
                            Button(goal.title) { goals.selectedGoalID = goal.id; navigation.show(.goals); dismiss() }
                        }
                    }
                }

                marketSection

                if inspected.binding != nil || inspected.boundTo != nil || !(inspected.item.flags ?? []).isEmpty {
                    Section("Binding") {
                        if let binding = inspected.binding { Text(binding.replacingOccurrences(of: "Account", with: "Account Bound")) }
                        if let boundTo = inspected.boundTo { LabeledContent("Bound to", value: boundTo) }
                        ForEach(inspected.item.flags?.filter { $0.contains("Bound") } ?? [], id: \.self) {
                            Text($0.replacingOccurrences(of: "AccountBound", with: "Account Bound"))
                        }
                    }
                }

                if let description = inspected.item.description?.gwPlainText, !description.isEmpty {
                    Section("Description") { Text(description == "Metadata for this item has not loaded yet." ? "Some item details are not available yet." : description).foregroundStyle(.secondary) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task(id: inspected.item.id) {
                priceLoading = true
                await goals.refreshOwnedItemPrice(itemID: inspected.item.id)
                priceLoading = false
            }
        }
    }

    @ViewBuilder
    private var marketSection: some View {
        let values = OwnedItemMarketValues(
            item: inspected.item, quantity: inspected.quantity,
            price: goals.marketPrices[inspected.item.id])
        Section("Market") {
            if values.sellState == .nonTradable || values.buyState == .nonTradable {
                Text("Not tradable").foregroundStyle(.secondary)
            } else {
                if let sell = values.sellNow {
                    LabeledContent("Sell now · each", value: CoinAmount(copperValue: sell.unitCopper).compactFormatted)
                    LabeledContent("Estimated stack · sell", value: sell.amount.compactFormatted)
                } else {
                    LabeledContent("Sell now", value: priceLoading ? "Checking price…" : (values.sellState == .noBuyOrders ? "No current buy orders" : "Price unavailable"))
                }
                if let buy = values.buyNow {
                    LabeledContent("Buy now · each", value: CoinAmount(copperValue: buy.unitCopper).compactFormatted)
                    LabeledContent("Estimated stack · buy", value: buy.amount.compactFormatted)
                } else {
                    LabeledContent("Buy now", value: priceLoading ? "Checking price…" : (values.buyState == .noSellOrders ? "No current sell offers" : "Price unavailable"))
                }
                if let updatedAt = values.updatedAt {
                    LabeledContent("Updated", value: updatedAt.formatted(date: .omitted, time: .shortened))
                } else if priceLoading {
                    GWLoadingRows(count: 1)
                }
            }
        }
    }

    private var itemType: String? {
        guard let type = inspected.item.details?.type ?? inspected.item.type else { return nil }
        // ArenaNet type names are identifiers; display readable words in the item hero.
        return type.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    private func displayAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "ConditionDamage", with: "Condition Damage")
            .replacingOccurrences(of: "HealingPower", with: "Healing Power")
    }

    private func metadataRow(name: String, icon: URL?, rarity: String?) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: icon) { RoundedRectangle(cornerRadius: 6).fill(.quaternary) }
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(name)
                if let rarity { Text(rarity).font(.caption).foregroundStyle(GWPalette.rarity(rarity)) }
            }
        }
    }
}
