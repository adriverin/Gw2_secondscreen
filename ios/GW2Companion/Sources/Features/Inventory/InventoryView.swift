import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var search = ""
    @State private var sort: HoldingSort = .name
    @State private var inspected: InspectedItem?
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
            case .materials: MaterialStorageView(inspected: $inspected)
            case .shared: SharedInventoryView(inspected: $inspected)
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if account.isRefreshing && account.holdings.isEmpty {
            Label("Loading inventory…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).padding(8)
                .accessibilityIdentifier("inventory.state.loading")
        } else if let error = account.errorMessage, account.holdings.isEmpty, !account.inventoryLive {
            GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                .padding(.horizontal)
                .accessibilityIdentifier("inventory.state.error")
        } else if account.inventoryLive, let updated = account.inventoryUpdatedAt ?? account.accountLastRefreshedAt {
            HStack {
                Text("LIVE ACCOUNT RESPONSE • \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 8)
            .accessibilityIdentifier("inventory.state.live")
        } else if account.isStale {
            HStack {
                Label(account.cacheStatusText, systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("CACHED").font(.caption2.bold()).foregroundStyle(.orange)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal).padding(.top, 8)
            .accessibilityIdentifier("inventory.state.cached")
        } else if let updated = account.accountLastRefreshedAt {
            HStack {
                Text("LIVE ACCOUNT RESPONSE • \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 8)
            .accessibilityIdentifier("inventory.state.live")
        }
    }

    private var results: [HoldingSearchResult] {
        HoldingSearch.results(holdings: account.holdings, metadata: account.itemMetadata, query: search, sort: sort)
    }

    private var allSearch: some View {
        List {
            if let error = account.errorMessage, !account.inventoryLive, account.holdings.isEmpty {
                GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if let bank = account.domainStates[.bank], bank.phase == .failed, let message = bank.message {
                GWErrorBanner(message: "Bank: \(message)", stale: true) { Task { await account.refresh() } }
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
                GWSectionHeader(title: "Bank", subtitle: "\(occupied) occupied slots • \(account.dataSource.qaLabel)")
                if account.bankSlots.isEmpty {
                    if account.domainStates[.bank]?.phase == .failed {
                        Text(account.domainStates[.bank]?.message ?? "Couldn't refresh bank.")
                            .foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        Text("Bank is empty.").foregroundStyle(.secondary).padding(.top, 8)
                    }
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
                GWSectionHeader(title: "Shared Inventory", subtitle: "\(occupied) occupied slots • \(account.dataSource.qaLabel)")
                if account.sharedSlots.isEmpty {
                    if account.domainStates[.sharedInventory]?.phase == .failed {
                        Text(account.domainStates[.sharedInventory]?.message ?? "Couldn't refresh shared inventory.")
                            .foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        Text("Shared inventory is empty.").foregroundStyle(.secondary).padding(.top, 8)
                    }
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
    @Binding var inspected: InspectedItem?
    @AppStorage(MaterialStoragePreferences.showAllKey) private var showAll = false
    @State private var search = ""

    var body: some View {
        let presented = presentedSnapshot
        List {
            Section {
                Toggle("Show All Materials", isOn: $showAll)
                    .accessibilityIdentifier("inventory.materials.showAll")
                TextField("Search materials", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inventory.materials.search")
            } header: {
                Text("Material Storage")
            } footer: {
                Text(summaryText(presented))
            }
            if let presented {
                ForEach(presented.sections) { section in
                    Section(section.name) {
                        ForEach(section.rows) { row in
                            Button {
                                inspected = InspectedItem(
                                    item: account.itemMetadata[row.id] ?? ItemPlaceholder.metadata(id: row.id, name: row.name),
                                    quantity: row.count)
                            } label: {
                                MaterialStorageRowView(row: row, item: account.itemMetadata[row.id])
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inventory.material.\(row.name)")
                            .accessibilityIdentifier("inventory.item.\(row.name)")
                        }
                    }
                }
            } else if account.domainStates[.materials]?.phase == .loading || account.isRefreshing {
                Section {
                    ProgressView("Preparing material storage…")
                }
            }
        }
        .accessibilityIdentifier("inventory.materials")
        .refreshable { await account.refresh() }
        .overlay {
            if account.materialCategories.isEmpty && account.materials.isEmpty {
                ContentUnavailableView(
                    "No material categories", systemImage: "cube.box",
                    description: Text(account.domainStates[.materials]?.phase == .failed
                        ? (account.domainStates[.materials]?.message ?? "Material storage could not be refreshed.")
                        : "Material storage has not been loaded yet."))
            } else if let presented, presented.visibleRowCount == 0, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .task(id: account.inventoryUpdatedAt) {
            if account.materialSnapshot == nil, !account.materials.isEmpty || !account.materialCategories.isEmpty {
                account.rebuildMaterialSnapshot()
            }
        }
    }

    private var presentedSnapshot: MaterialStoragePresentedSnapshot? {
        guard let snapshot = account.materialSnapshot else { return nil }
        return MaterialStoragePresentation.present(snapshot: snapshot, showAll: showAll, query: search)
    }

    private func summaryText(_ presented: MaterialStoragePresentedSnapshot?) -> String {
        guard let presented else { return "Owned Only is the default view." }
        if presented.showAll {
            return "Showing all \(presented.totalRowCount.formatted()) materials. \(presented.ownedRowCount.formatted()) owned."
        }
        return "Owned Only • \(presented.visibleRowCount.formatted()) of \(presented.totalRowCount.formatted()) materials"
    }
}

private struct MaterialStorageRowView: View {
    let row: MaterialRowSnapshot
    let item: ItemMetadata?

    var body: some View {
        HStack {
            GWItemIcon(item: item ?? ItemPlaceholder.metadata(id: row.id, name: row.name), size: 40)
            Text(row.name)
            Spacer()
            Text(row.count.formatted()).monospacedDigit().bold()
        }
    }
}

struct InventorySlotCell: View {
    let slot: InventorySlot?
    let items: [Int: ItemMetadata]
    let onSelect: (InspectedItem) -> Void

    var body: some View {
        if let slot {
            let item = items[slot.id] ?? ItemPlaceholder.metadata(id: slot.id)
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
