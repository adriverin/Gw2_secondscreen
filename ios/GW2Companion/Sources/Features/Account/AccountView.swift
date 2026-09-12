import SwiftUI

private struct WalletDisplay: Identifiable {
    let entry: WalletEntry
    let metadata: CurrencyMetadata?
    var id: Int { entry.id }
}

struct AccountView: View {
    let api: GW2APIClient
    @State private var apiKey = ""
    @State private var tokenInfo: TokenInfo?
    @State private var wallet: [WalletDisplay] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let usefulPermissions = ["account", "characters", "inventories", "wallet", "tradingpost", "progression"]

    var body: some View {
        NavigationStack {
            Form {
                if let tokenInfo {
                    Section {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(tokenInfo.name).font(.headline)
                    }
                    Section("Permissions") {
                        ForEach(usefulPermissions, id: \.self) { permission in
                            Label(permission, systemImage: tokenInfo.permissions.contains(permission) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(tokenInfo.permissions.contains(permission) ? .primary : .secondary)
                        }
                    }
                    if tokenInfo.permissions.contains("wallet") {
                        Section("Wallet") {
                            if wallet.isEmpty { Text("Pull to refresh wallet data.").foregroundStyle(.secondary) }
                            ForEach(wallet) { value in
                                HStack {
                                    AsyncImage(url: value.metadata?.icon) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "circle.dashed") }
                                        .frame(width: 28, height: 28)
                                    Text(value.metadata?.name ?? "Currency \(value.id)")
                                    Spacer()
                                    if value.entry.id == 1 {
                                        CoinAmountView(value: value.entry.value)
                                    } else {
                                        Text(value.entry.value.formatted()).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    Section { Button("Disconnect API key", role: .destructive) { Task { await disconnect() } } }
                } else {
                    Section("Connect Guild Wars 2 Account") {
                        Text("To show your characters and inventory, enter a Guild Wars 2 API key.")
                            .foregroundStyle(.secondary)
                        SecureField("API key", text: $apiKey)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Connect") { Task { await connect() } }.disabled(apiKey.isEmpty || isLoading)
                    }
                    Section {
                        Link("Create a key on account.arena.net", destination: URL(string: "https://account.arena.net/applications")!)
                    } footer: {
                        Text("The key stays in this iPhone's Keychain and is sent only to api.guildwars2.com. It is never sent to the PC bridge.")
                    }
                }
                if isLoading { Section { ProgressView() } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Account")
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    private func connect() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tokenInfo = try await api.validateAndSave(apiKey: apiKey)
            apiKey = ""
            errorMessage = nil
            await loadWalletIfAllowed()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tokenInfo = try await api.savedTokenInfo()
            errorMessage = nil
            await loadWalletIfAllowed()
        } catch { tokenInfo = nil; errorMessage = error.localizedDescription }
    }

    private func loadWalletIfAllowed() async {
        guard tokenInfo?.permissions.contains("wallet") == true else { wallet = []; return }
        do { wallet = try await api.wallet().map { WalletDisplay(entry: $0.0, metadata: $0.1) } }
        catch { errorMessage = error.localizedDescription }
    }

    private func disconnect() async {
        do { try await api.disconnect(); tokenInfo = nil; wallet = []; errorMessage = nil }
        catch { errorMessage = "The saved API key could not be removed." }
    }
}

private struct CoinAmountView: View {
    let value: Int
    private var amount: CoinAmount { CoinAmount(copperValue: value) }

    var body: some View {
        HStack(spacing: 5) {
            denomination(amount.gold, suffix: "g", color: Color(red: 0.93, green: 0.70, blue: 0.20))
            denomination(amount.silver, suffix: "s", color: Color(white: 0.76))
            denomination(amount.copper, suffix: "c", color: Color(red: 0.75, green: 0.42, blue: 0.23))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(amount.accessibilityLabel)
    }

    private func denomination(_ number: Int, suffix: String, color: Color) -> some View {
        HStack(spacing: 1) {
            Text("\(number)")
            Text(suffix).foregroundStyle(color)
        }
    }
}
