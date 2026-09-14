import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var search = ""
    @State private var sort: HoldingSort = .name
    @State private var inspected: InspectedItem?
    @State private var showAllMaterials = false
    @State private var showingReplaceKey = false

    var body: some View {
        NavigationStack {
            Group {
                if account.connectionState == .loading && account.holdings.isEmpty && account.bankSlots.isEmpty {
                    loadingState
                } else if account.connectionState == .disconnected && account.tokenInfo == nil {
                    GWEmptyState(
                        title: "Connect your Guild Wars 2 account",
                        message: "Find an item across every character, your bank, shared inventory and material storage.",
                        symbol: "magnifyingglass",
                        actionTitle: "Connect Account",
                        action: { navigation.selectedTab = .account })
                } else if !account.permissions.contains(.inventories) {
                    missingPermission
                } else {
                    hub
                }
            }
            .navigationTitle("Inventory")
            .sheet(item: $inspected) { ItemDetailView(inspected: $0, metadata: account.itemMetadata) }
            .sheet(isPresented: $showingReplaceKey) {
                NavigationStack { AccountSetupForm(connected: { showingReplaceKey = false }) }
            }
        }
        .accessibilityIdentifier("inventory.hub")
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView("Indexing account inventory…")
            Text("Never loaded").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("inventory.state.loading")
    }

    private var missingPermission: some View {
        GWEmptyState(
            title: "Inventory access isn't enabled",
            message: "Your current Guild Wars 2 API key does not include the “inventories” permission.\n\nThis is required for character inventories, bank, material storage, and shared inventory.",
            symbol: "shippingbox.and.arrow.backward",
            actionTitle: "Replace API Key",
            action: { showingReplaceKey = true })
        .accessibilityIdentifier("inventory.state.missing-permission")
    }

    private var hub: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InventoryHubSection.allCases) { section in
                        Button(section.title) { navigation.inventorySection = section }
                            .buttonStyle(.bordered)
                            .tint(navigation.inventorySection == section ? GWPalette.accent : .secondary)
                            .accessibilityIdentifier("inventory.section.\(section.rawValue)")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .accessibilityIdentifier("inventory.sections")

            statusBanner

            switch navigation.inventorySection {
            case .all: allSearch
            case .characters: charactersList
            case .bank: BankStorageView(inspected: $inspected)
            case .materials: MaterialStorageView(search: $search, showAll: $showAllMaterials, inspected: $inspected)
            case .shared: SharedInventoryView(inspected: $inspected)
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if account.isRefreshing && account.holdings.isEmpty {
            Label("Loading inventory…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).padding(8)
                .accessibilityIdentifier("inventory.state.loading")
        } else if let error = account.errorMessage, account.holdings.isEmpty {
            GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                .padding(.horizontal)
                .accessibilityIdentifier("inventory.state.error")
        } else if account.isStale {
            HStack {
                Label(account.cacheStatusText, systemImage: "clock.arrow.circlepath")
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal).padding(.top, 8)
            .accessibilityIdentifier("inventory.state.cached")
        } else if let updated = account.accountLastRefreshedAt {
            HStack {
                Text("Last updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 8)
        }
    }

    private var results: [HoldingSearchResult] {
        HoldingSearch.results(holdings: account.holdings, metadata: account.itemMetadata, query: search, sort: sort)
    }

    private var allSearch: some View {
        List {
            if let error = account.errorMessage {
                GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                TextField("Search all inventory", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inventory.search.field")
            }
            Section {
                ForEach(results) { result in
                    Button { inspected = InspectedItem(item: result.item, quantity: result.holding.totalQuantity) } label: {
                        HoldingRow(result: result)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inventory.item.\(result.item.name)")
                }
            } header: {
                Text(search.isEmpty
                     ? "\(results.count.formatted()) unique items"
                     : "Search all inventory")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(HoldingSort.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
        }
        .overlay {
            if results.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if results.isEmpty && account.holdings.isEmpty && account.errorMessage == nil {
                ContentUnavailableView("No items stored", systemImage: "shippingbox", description: Text("Bank, material storage, shared inventory, and character bags are empty."))
                    .accessibilityIdentifier("inventory.state.empty")
            }
        }
        .refreshable { await account.refresh() }
    }

    private var charactersList: some View {
        List {
            if !account.permissions.contains(.characters) {
                Text("Character inventories also need the “characters” permission.")
                    .foregroundStyle(.secondary)
            }
            ForEach(account.characters) { character in
                NavigationLink(value: CharacterRoute(name: character.name, section: .inventory)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(character.name)
                            Text("\(account.eliteSpecializationName(for: character) ?? character.profession) • Level \(character.level)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.fill")
                    }
                }
                .accessibilityIdentifier("inventory.character.\(character.name)")
            }
        }
        .navigationDestination(for: CharacterRoute.self) { route in
            if let character = account.characters.first(where: { $0.name == route.name }) {
                CharacterInventoryDestination(character: character)
            } else {
                GWEmptyState(title: "Character unavailable", message: "Refresh your account data and try again.", symbol: "person.slash")
            }
        }
        .refreshable { await account.refresh() }
    }
}

private struct CharacterInventoryDestination: View {
    let character: GW2Character
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ScrollView {
            CharacterInventorySection(
                detail: account.characterDetails[character.name] ?? CharacterDetailData(),
                fallbackItems: account.itemMetadata)
                .padding()
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await account.loadCharacterDetails(character) }
        .refreshable { await account.loadCharacterDetails(character, force: true) }
    }
}

struct BankStorageView: View {
    @EnvironmentObject private var account: AccountStore
    @Binding var inspected: InspectedItem?

    var body: some View {
        let occupied = account.bankSlots.compactMap { $0 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GWSectionHeader(title: "Bank", subtitle: "\(occupied) occupied slots")
                if account.bankSlots.isEmpty {
                    Text("Bank is empty.").foregroundStyle(.secondary).padding(.top, 8)
                } else {
                    slotGrid(account.bankSlots, items: account.itemMetadata)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("inventory.bank")
        .refreshable { await account.refresh() }
    }

    private func slotGrid(_ slots: [InventorySlot?], items: [Int: ItemMetadata]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 9)], spacing: 9) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                InventorySlotCell(slot: slot, items: items) { inspected = $0 }
            }
        }
    }
}

struct SharedInventoryView: View {
    @EnvironmentObject private var account: AccountStore
    @Binding var inspected: InspectedItem?

    var body: some View {
        let occupied = account.sharedSlots.compactMap { $0 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GWSectionHeader(title: "Shared Inventory", subtitle: "\(occupied) occupied slots")
                if account.sharedSlots.isEmpty {
                    Text("Shared inventory is empty.").foregroundStyle(.secondary).padding(.top, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 9)], spacing: 9) {
                        ForEach(Array(account.sharedSlots.enumerated()), id: \.offset) { _, slot in
                            InventorySlotCell(slot: slot, items: account.itemMetadata) { inspected = $0 }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("inventory.shared")
        .refreshable { await account.refresh() }
    }
}

struct MaterialStorageView: View {
    @EnvironmentObject private var account: AccountStore
    @Binding var search: String
    @Binding var showAll: Bool
    @Binding var inspected: InspectedItem?

    var body: some View {
        let categories = account.materialCategories.values.sorted { $0.order < $1.order }
        let materialsByID = Dictionary(uniqueKeysWithValues: account.materials.map { ($0.id, $0) })
        List {
            Section {
                Toggle("Show owned only", isOn: Binding(get: { !showAll }, set: { showAll = !$0 }))
            } header: {
                Text("Material Storage")
            }
            ForEach(categories) { category in
                let values = category.items.compactMap { itemID -> (AccountMaterial, ItemMetadata)? in
                    guard let material = materialsByID[itemID] else { return nil }
                    if !showAll && material.count <= 0 { return nil }
                    guard let item = account.itemMetadata[itemID] else { return nil }
                    if !search.isEmpty && !item.name.localizedCaseInsensitiveContains(search) { return nil }
                    return (material, item)
                }
                if !values.isEmpty {
                    Section(category.name) {
                        ForEach(values, id: \.0.id) { material, item in
                            Button {
                                inspected = InspectedItem(item: item, quantity: material.count)
                            } label: {
                                HStack {
                                    GWItemIcon(item: item, size: 40)
                                    Text(item.name)
                                    Spacer()
                                    Text(material.count.formatted()).monospacedDigit().bold()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inventory.material.\(item.name)")
                            .accessibilityIdentifier("inventory.item.\(item.name)")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("inventory.materials")
        .refreshable { await account.refresh() }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView("No material categories", systemImage: "cube.box", description: Text("Material storage has not been loaded yet."))
            }
        }
    }
}

struct InventorySlotCell: View {
    let slot: InventorySlot?
    let items: [Int: ItemMetadata]
    let onSelect: (InspectedItem) -> Void

    var body: some View {
        if let slot, let item = items[slot.id] {
            Button { onSelect(InspectedItem(item: item, quantity: slot.count, slot: slot)) } label: {
                ZStack(alignment: .bottomTrailing) {
                    GWItemIcon(item: item, size: 52)
                    if slot.count > 1 {
                        Text(slot.count.formatted()).font(.caption2.bold()).padding(3)
                            .background(.black.opacity(0.8), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), quantity \(slot.count)")
            .accessibilityIdentifier("inventory.item.\(item.name)")
        } else if slot != nil {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.45)).frame(width: 52, height: 52)
                .overlay(Image(systemName: "shippingbox").foregroundStyle(.tertiary))
                .accessibilityLabel("Unknown item")
        } else {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.45)).frame(width: 52, height: 52)
                .accessibilityLabel("Empty slot")
        }
    }
}

struct HoldingRow: View {
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
