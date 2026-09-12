import Foundation

enum GW2APIError: LocalizedError {
    case invalidAPIKey
    case missingPermission(String)
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "API key invalid. Create a new key on account.arena.net."
        case let .missingPermission(permission): "Your API key does not include the \(permission) permission."
        case .invalidResponse: "The Guild Wars 2 API returned an unexpected response."
        case let .server(code): "The Guild Wars 2 API returned HTTP \(code)."
        }
    }
}

actor GW2APIClient {
    private let session: URLSession
    private let credentials: CredentialStore
    private let diskCache: MetadataDiskCache
    private let baseURL = URL(string: "https://api.guildwars2.com/v2/")!
    private var itemCache: [Int: ItemMetadata] = [:]
    private var currencyCache: [Int: CurrencyMetadata] = [:]
    private var mapCache: [Int: GW2MapMetadata] = [:]
    private var loadedItemCache = false
    private var loadedCurrencyCache = false
    private var loadedMapCache = false

    init(session: URLSession = .shared, credentials: CredentialStore = CredentialStore(), diskCache: MetadataDiskCache = MetadataDiskCache()) {
        self.session = session
        self.credentials = credentials
        self.diskCache = diskCache
    }

    func validateAndSave(apiKey: String) async throws -> TokenInfo {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GW2APIError.invalidAPIKey }
        let info: TokenInfo = try await request("tokeninfo", apiKey: trimmed)
        try credentials.saveAPIKey(trimmed)
        return info
    }

    func savedTokenInfo() async throws -> TokenInfo? {
        guard let key = try credentials.getAPIKey() else { return nil }
        return try await request("tokeninfo", apiKey: key)
    }

    func disconnect() throws { try credentials.deleteAPIKey() }

    func characters() async throws -> [GW2Character] {
        try await authenticatedRequest("characters?page=0&page_size=200")
    }

    func characterInventory(name: String) async throws -> [InventorySlot] {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let response: CharacterInventoryResponse = try await authenticatedRequest("characters/\(encoded)/inventory")
        return response.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }
    }

    func bank() async throws -> [InventorySlot] {
        let slots: [InventorySlot?] = try await authenticatedRequest("account/bank")
        return slots.compactMap { $0 }
    }

    func sharedInventory() async throws -> [InventorySlot] {
        let slots: [InventorySlot?] = try await authenticatedRequest("account/inventory")
        return slots.compactMap { $0 }
    }

    func materials() async throws -> [InventorySlot] {
        let materials: [AccountMaterial] = try await authenticatedRequest("account/materials")
        return materials.filter { $0.count > 0 }.map { InventorySlot(id: $0.id, count: $0.count) }
    }

    func wallet() async throws -> [(WalletEntry, CurrencyMetadata?)] {
        if !loadedCurrencyCache {
            currencyCache = await diskCache.load([Int: CurrencyMetadata].self, named: "currencies") ?? [:]
            loadedCurrencyCache = true
        }
        let entries: [WalletEntry] = try await authenticatedRequest("account/wallet")
        let missing = entries.map(\.id).filter { currencyCache[$0] == nil }
        if !missing.isEmpty {
            let metadata: [CurrencyMetadata] = try await request("currencies?ids=\(Self.batchedIDs(missing).joined(separator: ","))")
            metadata.forEach { currencyCache[$0.id] = $0 }
            await diskCache.save(currencyCache, named: "currencies")
        }
        return entries.map { ($0, currencyCache[$0.id]) }
    }

    func displayItems(_ slots: [InventorySlot]) async throws -> [DisplayInventoryItem] {
        if !loadedItemCache {
            itemCache = await diskCache.load([Int: ItemMetadata].self, named: "items") ?? [:]
            loadedItemCache = true
        }
        var totals: [Int: Int] = [:]
        slots.forEach { totals[$0.id, default: 0] += $0.count }
        let missing = totals.keys.filter { itemCache[$0] == nil }
        for batch in Self.chunks(of: Array(missing), size: 200) {
            let items: [ItemMetadata] = try await request("items?ids=\(batch.map(String.init).joined(separator: ","))")
            items.forEach { itemCache[$0.id] = $0 }
        }
        if !missing.isEmpty { await diskCache.save(itemCache, named: "items") }
        return totals.compactMap { id, count in itemCache[id].map { DisplayInventoryItem(metadata: $0, quantity: count) } }
            .sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
    }

    func map(id: Int) async throws -> GW2MapMetadata {
        if !loadedMapCache {
            mapCache = await diskCache.load([Int: GW2MapMetadata].self, named: "maps") ?? [:]
            loadedMapCache = true
        }
        if let cached = mapCache[id] { return cached }
        let metadata: GW2MapMetadata = try await request("maps/\(id)")
        mapCache[id] = metadata
        await diskCache.save(mapCache, named: "maps")
        return metadata
    }

    static func batchedIDs(_ ids: [Int]) -> [String] {
        Array(Set(ids)).sorted().map(String.init)
    }

    static func chunks(of ids: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }

    private func authenticatedRequest<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let key = try credentials.getAPIKey() else { throw GW2APIError.invalidAPIKey }
        return try await request(path, apiKey: key)
    }

    private func request<T: Decodable & Sendable>(_ path: String, apiKey: String? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw GW2APIError.invalidResponse }
        var request = URLRequest(url: url)
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GW2APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GW2APIError.invalidAPIKey }
            if http.statusCode == 403 { throw GW2APIError.missingPermission("required") }
            throw GW2APIError.server(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
