import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var localError: String?
    @State private var walletSearch = ""
    @State private var showingReplaceKey = false
    @State private var showingInventoryPermissionHelp = false

    var body: some View {
        NavigationStack {
            Group {
                if store.connectionState == .loading && store.tokenInfo == nil { ProgressView("Loading account…") }
                else if store.connectionState == .disconnected { connectView }
                else { dashboard }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showingReplaceKey) {
                NavigationStack { AccountSetupForm(connected: { showingReplaceKey = false }) }
            }
        }
    }

    private var connectView: some View {
        AccountSetupForm(connected: {})
            .frame(maxWidth: 520).padding(28).frame(maxWidth: .infinity)
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let error = store.errorMessage {
                    GWErrorBanner(message: error, stale: store.isStale) { Task { await store.refresh() } }
                }
                identityCard
                if !missingPermissions.isEmpty { limitedPermissionsCard }
                summaryGrid
                if store.permissions.contains(.wallet) { walletCard }
                inventoryCard
                permissionsCard
                Button("Disconnect Account", role: .destructive) {
                    Task {
                        do { try await store.disconnect() }
                        catch { localError = "The saved API key could not be removed." }
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .frame(maxWidth: 920).padding().frame(maxWidth: .infinity)
        }
        .refreshable { await store.refresh() }
        .toolbar {
            if store.isRefreshing { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
            else if store.isStale { ToolbarItem(placement: .topBarTrailing) { GWBadge(text: "SAVED", color: .orange, symbol: "clock") } }
        }
    }

    private var identityCard: some View {
        GWCard {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(GWPalette.accent)
                Text(store.account?.name ?? store.tokenInfo?.name ?? "Guild Wars 2 Account")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                GWBadge(text: "CONNECTED", color: .green, symbol: "checkmark.circle.fill")
            }
            HStack(spacing: 7) {
                if let world = store.world { Text(world.name) }
                if let account = store.account {
                    Text("• \(account.world >= 2_000 ? "EU" : "NA")")
                    if let years = accountAge(created: account.created) { Text("• \(years) years") }
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
            SummaryTile(title: "Characters", value: store.summary.characterCount.formatted(), detail: "\(store.summary.maxLevelCharacterCount) at level 80", symbol: "person.2.fill")
            SummaryTile(title: "Playtime", value: formattedPlaytime(store.summary.totalPlaytime), detail: "Across all characters", symbol: "clock.fill")
            SummaryTile(title: "Deaths", value: store.summary.totalDeaths.formatted(), detail: "Across all characters", symbol: "heart.slash.fill")
            SummaryTile(title: "Collection", value: store.summary.uniqueItemCount.formatted(), detail: "Unique stored items", symbol: "shippingbox.fill")
        }
    }

    private var walletCard: some View {
        let values = store.wallet.filter { entry in
            walletSearch.isEmpty || (store.currencies[entry.id]?.name.localizedCaseInsensitiveContains(walletSearch) ?? false)
        }.sorted { lhs, rhs in
            let left = store.currencies[lhs.id]?.order ?? lhs.id
            let right = store.currencies[rhs.id]?.order ?? rhs.id
            return left < right
        }
        return GWCard {
            GWSectionHeader(title: "Wallet", subtitle: "\(store.wallet.count) currencies")
            TextField("Search currencies", text: $walletSearch)
                .textFieldStyle(.roundedBorder).padding(.vertical, 8)
            ForEach(values.prefix(walletSearch.isEmpty ? 8 : values.count)) { entry in
                let currency = store.currencies[entry.id]
                HStack(spacing: 11) {
                    CachedAsyncImage(url: currency?.icon) { Circle().fill(.quaternary) }
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text(currency?.name ?? "Currency \(entry.id)")
                        if !walletSearch.isEmpty, let description = currency?.description, !description.isEmpty {
                            Text(description.gwPlainText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    if entry.id == 1 { CoinAmountView(value: entry.value) }
                    else { Text(entry.value.formatted()).monospacedDigit().bold() }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var inventoryCard: some View {
        GWCard {
            GWSectionHeader(title: "Account Inventory")
            HStack {
                Label("\(store.holdings.reduce(0) { $0 + $1.totalQuantity }.formatted()) items", systemImage: "shippingbox")
                Spacer()
                Label("\(store.materials.filter { $0.count > 0 }.count) materials", systemImage: "cube.box")
            }
            .font(.subheadline).padding(.top, 12)
            Button("Open Inventory") { navigation.showInventory(.all) }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
    }

    private var permissionsCard: some View {
        GWCard {
            GWSectionHeader(title: "API Permissions", subtitle: "Replace the key to change permissions")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], alignment: .leading, spacing: 9) {
                ForEach(AccountPermission.allCases) { permission in
                    let enabled = store.permissions.contains(permission)
                    Button {
                        if permission == .inventories && !enabled { showingInventoryPermissionHelp = true }
                    } label: {
                        Label("\(permission.title)    \(enabled ? "✓" : "Missing")",
                              systemImage: enabled ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline).foregroundStyle(enabled ? Color.primary : Color.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(permission.title) permission \(enabled ? "enabled" : "missing")")
                    .accessibilityIdentifier("permission.\(permission.rawValue)")
                }
            }
            .padding(.top, 12)
            .alert("Inventories permission missing", isPresented: $showingInventoryPermissionHelp) {
                Button("Replace API Key") { showingReplaceKey = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text("The inventories permission is required for character inventories, bank, material storage, and shared inventory.")
            }
        }
    }

    private var missingPermissions: [AccountPermission] {
        [.account, .characters, .inventories, .builds, .progression, .unlocks, .wallet]
            .filter { !store.permissions.contains($0) }
    }

    private var limitedPermissionsCard: some View {
        GWCard {
            Label("Connected with limited permissions", systemImage: "exclamationmark.circle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("Unrelated features remain available. Missing permissions:")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(missingPermissions) { permission in
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title).bold()
                    Text(permission.affectedFeatures).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 5)
            }
            Button("Replace API Key") { showingReplaceKey = true }.buttonStyle(.bordered)
                .padding(.top, 6)
        }
    }

    private func accountAge(created: String) -> Int? {
        guard let date = ISO8601DateFormatter().date(from: created) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }

    private func formattedPlaytime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3_600)
        let thousands = (Double(hours) / 1_000).formatted(.number.precision(.fractionLength(1)))
        return hours >= 1_000 ? "\(thousands)k h" : "\(hours.formatted()) h"
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        GWCard {
            Image(systemName: symbol).foregroundStyle(GWPalette.accent).font(.title2)
            Text(value).font(.title2.bold()).monospacedDigit().padding(.top, 5)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CoinAmountView: View {
    let value: Int
    private var amount: CoinAmount { CoinAmount(copperValue: value) }

    var body: some View {
        HStack(spacing: 5) {
            denomination(amount.gold, suffix: "g", color: Color(red: 0.93, green: 0.70, blue: 0.20))
            denomination(amount.silver, suffix: "s", color: Color(white: 0.76))
            denomination(amount.copper, suffix: "c", color: Color(red: 0.75, green: 0.42, blue: 0.23))
        }
        .monospacedDigit().accessibilityElement(children: .ignore).accessibilityLabel(amount.accessibilityLabel)
    }

    private func denomination(_ number: Int, suffix: String, color: Color) -> some View {
        HStack(spacing: 1) { Text("\(number)"); Text(suffix).foregroundStyle(color) }
    }
}
