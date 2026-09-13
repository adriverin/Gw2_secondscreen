import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var localError: String?
    @State private var walletSearch = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.connectionState == .loading && store.tokenInfo == nil { ProgressView("Loading account…") }
                else if store.connectionState == .disconnected { connectView }
                else { dashboard }
            }
            .navigationTitle("Account")
        }
    }

    private var connectView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 64)).foregroundStyle(GWPalette.accent)
                Text("Connect your Guild Wars 2 account").font(.title2.bold())
                Text("View your characters, equipment, builds and everything you own. Your key stays in this device's Keychain.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                SecureField("ArenaNet API key", text: $apiKey)
                    .textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Connect Account").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).tint(GWPalette.accent).disabled(apiKey.isEmpty || isConnecting)
                Link("Create an API key on account.arena.net", destination: URL(string: "https://account.arena.net/applications")!)
                    .font(.subheadline)
                Text("Use a key with account, characters, inventories, builds, and wallet permissions for the complete experience. The key is sent only to the official Guild Wars 2 API.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let error = localError ?? store.errorMessage {
                    GWErrorBanner(message: error, stale: false)
                }
            }
            .frame(maxWidth: 520).padding(28).frame(maxWidth: .infinity)
        }
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let error = store.errorMessage {
                    GWErrorBanner(message: error, stale: store.isStale) { Task { await store.refresh() } }
                }
                identityCard
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
        }
    }

    private var permissionsCard: some View {
        GWCard {
            GWSectionHeader(title: "API Permissions", subtitle: "Replace the key to change permissions")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], alignment: .leading, spacing: 9) {
                ForEach(AccountPermission.allCases) { permission in
                    let enabled = store.permissions.contains(permission)
                    Label(permission.title, systemImage: enabled ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline).foregroundStyle(enabled ? Color.primary : Color.secondary)
                        .accessibilityLabel("\(permission.title) permission \(enabled ? "enabled" : "not enabled")")
                }
            }
            .padding(.top, 12)
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await store.connect(apiKey: apiKey)
            apiKey = ""
            localError = nil
        } catch { localError = error.localizedDescription }
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
