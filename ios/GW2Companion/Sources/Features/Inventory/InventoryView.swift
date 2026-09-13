import SwiftUI

struct InventoryView: View {
    enum Scope: String, CaseIterable { case all = "All Items"; case materials = "Materials" }
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var search = ""
    @State private var sort: HoldingSort = .name
    @State private var scope: Scope = .all
    @State private var inspected: InspectedItem?

    private var results: [HoldingSearchResult] {
        HoldingSearch.results(holdings: account.holdings, metadata: account.itemMetadata, query: search, sort: sort)
    }

    var body: some View {
        NavigationStack {
            Group {
                if account.connectionState == .loading && account.holdings.isEmpty {
                    ProgressView("Indexing account inventory…")
                } else if account.connectionState == .disconnected {
                    GWEmptyState(
                        title: "Connect your Guild Wars 2 account",
                        message: "Find an item across every character, your bank, shared inventory and material storage.",
                        symbol: "magnifyingglass",
                        actionTitle: "Connect Account",
                        action: { navigation.selectedTab = .account })
                } else if !account.permissions.contains(.inventories) {
                    GWEmptyState(
                        title: "Inventory access isn't enabled",
                        message: "Create an API key with the inventories permission.",
                        symbol: "shippingbox.and.arrow.backward")
                } else if account.holdings.isEmpty && account.errorMessage != nil {
                    GWEmptyState(
                        title: "Inventory unavailable",
                        message: account.errorMessage ?? "Couldn't load your inventory.",
                        symbol: "wifi.exclamationmark",
                        actionTitle: "Try Again") { Task { await account.refresh() } }
                } else {
                    content
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $search, prompt: "Search all items")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Scope", selection: $scope) { ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) { ForEach(HoldingSort.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                }
            }
            .sheet(item: $inspected) { ItemDetailView(inspected: $0, metadata: account.itemMetadata) }
        }
    }

    @ViewBuilder private var content: some View {
        if scope == .materials { materialsList }
        else {
            List {
                if let error = account.errorMessage {
                    GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    ForEach(results) { result in
                        Button { inspected = InspectedItem(item: result.item, quantity: result.holding.totalQuantity) } label: {
                            HoldingRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(results.count.formatted()) unique items")
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .refreshable { await account.refresh() }
        }
    }

    private var materialsList: some View {
        let materialIDs = Set(account.materials.filter { $0.count > 0 }.map(\.id))
        let matching = Dictionary(uniqueKeysWithValues: results.filter { materialIDs.contains($0.id) }.map { ($0.id, $0) })
        let categories = account.materialCategories.values.sorted { $0.order < $1.order }
        return List {
            if let error = account.errorMessage {
                GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            ForEach(categories) { category in
                let values = category.items.compactMap { matching[$0] }
                if !values.isEmpty {
                    Section(category.name) {
                        ForEach(values) { result in
                            Button { inspected = InspectedItem(item: result.item, quantity: result.holding.totalQuantity) } label: {
                                HoldingRow(result: result, compact: true)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .overlay { if matching.isEmpty { ContentUnavailableView.search(text: search) } }
        .refreshable { await account.refresh() }
    }
}

private struct HoldingRow: View {
    let result: HoldingSearchResult
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GWItemIcon(item: result.item, size: compact ? 40 : 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.item.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text(result.holding.totalQuantity.formatted()).font(.headline).monospacedDigit()
                }
                if !compact {
                    Text("\(result.holding.totalQuantity.formatted()) total")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(result.holding.locations) { value in
                        HStack {
                            Text(value.location.title)
                            Spacer()
                            Text(value.quantity.formatted()).monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let material = result.holding.locations.first(where: { $0.location == .materialStorage }) {
                    Text("\(material.quantity.formatted()) in Material Storage")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.item.name), \(result.holding.totalQuantity) total, \(result.holding.locations.map { "\($0.quantity) in \($0.location.title)" }.joined(separator: ", "))")
    }
}
