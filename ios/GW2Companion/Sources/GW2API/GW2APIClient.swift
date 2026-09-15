import Foundation

enum GW2APIError: LocalizedError, Equatable {
    case invalidAPIKey
    case missingPermission(String)
    case invalidResponse
    case decodeFailed(path: String)
    case server(Int)
    case rateLimited
    case serviceUnavailable
    case networkUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "This API key is invalid or has been revoked. Create or paste a new key."
        case let .missingPermission(permission): "Your API key does not include the \(permission) permission."
        case .invalidResponse, .decodeFailed:
            "ArenaNet returned data this version of the app could not read. Your saved data is still available."
        case .server: "ArenaNet is temporarily unavailable. Showing saved data where possible."
        case .rateLimited: "ArenaNet is temporarily limiting requests. Showing your saved data."
        case .serviceUnavailable: "ArenaNet is temporarily unavailable. Try again in a few minutes."
        case .networkUnavailable: "The internet connection is unavailable. Showing your saved data."
        case .timedOut: "ArenaNet took too long to respond. Showing your saved data."
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
    private var professionCache: [String: ProfessionMetadata] = [:]
    private var specializationCache: [Int: SpecializationMetadata] = [:]
    private var traitCache: [Int: TraitMetadata] = [:]
    private var skillCache: [Int: SkillMetadata] = [:]
    private var skinCache: [Int: SkinMetadata] = [:]
    private var miniCache: [Int: MiniMetadata] = [:]
    private var achievementCache: [Int: AchievementDefinition] = [:]
    private var recipeCache: [Int: RecipeDefinition] = [:]
    private var commercePriceCache: [Int: TimedCommercePrice] = [:]
    private var materialCategoryCache: [Int: MaterialCategoryMetadata] = [:]
    private var mapCache: [Int: GW2MapMetadata] = [:]
    private var floorCache: [String: GW2FloorMetadata] = [:]

    private var loadedCaches: Set<String> = []
    private var inFlightBatches: [String: Task<Data, Error>] = [:]
    private let scheduler = APIRequestScheduler()
    private(set) var lastUnresolvedMetadataIDs: [String: [Int]] = [:]

    init(
        session: URLSession = .shared,
        credentials: CredentialStore = CredentialStore(),
        diskCache: MetadataDiskCache = MetadataDiskCache()
    ) {
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

    func account() async throws -> GW2Account { try await authenticatedRequest("account") }

    func world(id: Int) async throws -> GW2World { try await request("worlds/\(id)") }

    func characters() async throws -> [GW2Character] {
        try await authenticatedLossyArray("characters?page=0&page_size=200", priority: .high)
    }

    func characterInventoryResponse(name: String) async throws -> CharacterInventoryResponse {
        try await authenticatedRequest("characters/\(Self.encodedPath(name))/inventory", priority: .high)
    }

    func characterInventory(name: String) async throws -> [InventorySlot] {
        let response = try await characterInventoryResponse(name: name)
        return response.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }
    }

    func equipmentTabs(character name: String) async throws -> [EquipmentTab] {
        try await authenticatedLossyArray(
            "characters/\(Self.encodedPath(name))/equipmenttabs?tabs=all", priority: .high)
    }

    func buildTabs(character name: String) async throws -> [BuildTab] {
        try await authenticatedLossyArray(
            "characters/\(Self.encodedPath(name))/buildtabs?tabs=all", priority: .high)
    }

    func bank() async throws -> [InventorySlot] {
        try await bankSlots().compactMap { $0 }
    }

    func bankSlots() async throws -> [InventorySlot?] {
        try await authenticatedSparseArray("account/bank", priority: .high)
    }

    func sharedInventory() async throws -> [InventorySlot] {
        try await sharedInventorySlots().compactMap { $0 }
    }

    func sharedInventorySlots() async throws -> [InventorySlot?] {
        try await authenticatedSparseArray("account/inventory", priority: .high)
    }

    func accountMaterials() async throws -> [AccountMaterial] {
        try await authenticatedLossyArray("account/materials", priority: .high)
    }

    func legendaryArmoryDefinitions() async throws -> [LegendaryArmoryDefinition] {
        try await request("legendaryarmory?ids=all", priority: .low)
    }

    func accountLegendaryArmory() async throws -> [AccountLegendaryArmorySlot] {
        try await authenticatedLossyArray("account/legendaryarmory", priority: .high)
    }

    func materials() async throws -> [InventorySlot] {
        try await accountMaterials().filter { $0.count > 0 }.map {
            InventorySlot(id: $0.id, count: $0.count, binding: $0.binding)
        }
    }

    func walletEntries() async throws -> [WalletEntry] {
        try await authenticatedLossyArray("account/wallet", priority: .high)
    }

    func wallet() async throws -> [(WalletEntry, CurrencyMetadata?)] {
        let entries = try await walletEntries()
        let metadata = try await currencies(ids: entries.map(\.id))
        return entries.map { ($0, metadata[$0.id]) }
    }

    func displayItems(_ slots: [InventorySlot]) async throws -> [DisplayInventoryItem] {
        var totals: [Int: Int] = [:]
        var representative: [Int: InventorySlot] = [:]
        for slot in slots {
            totals[slot.id, default: 0] += slot.count
            representative[slot.id] = representative[slot.id] ?? slot
        }
        let metadata = try await items(ids: Array(totals.keys))
        return totals.compactMap { id, count in
            metadata[id].map { DisplayInventoryItem(metadata: $0, quantity: count, slot: representative[id]) }
        }
        .sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
    }

    func items(ids: [Int], priority: APIRequestPriority = .normal) async throws -> [Int: ItemMetadata] {
        itemCache = await loadedIntCache(itemCache, name: "items")
        itemCache = try await filledIntCache(
            itemCache, ids: ids, endpoint: "items", name: "items", priority: priority)
        return itemCache.filter { Set(ids).contains($0.key) }
    }

    func currencies(ids: [Int], priority: APIRequestPriority = .normal) async throws -> [Int: CurrencyMetadata] {
        currencyCache = await loadedIntCache(currencyCache, name: "currencies")
        currencyCache = try await filledIntCache(
            currencyCache, ids: ids, endpoint: "currencies", name: "currencies", priority: priority)
        return currencyCache.filter { Set(ids).contains($0.key) }
    }

    func professions(ids: [String]) async throws -> [String: ProfessionMetadata] {
        if !loadedCaches.contains("professions") {
            professionCache = await diskCache.load([String: ProfessionMetadata].self, named: "professions") ?? [:]
            loadedCaches.insert("professions")
        }
        let wanted = Array(Set(ids)).sorted()
        let missing = wanted.filter { professionCache[$0] == nil }
        for batch in Self.chunks(of: missing, size: 200) {
            let encoded = batch.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
            let values: [ProfessionMetadata] = try await request("professions?ids=\(encoded.joined(separator: ","))")
            values.forEach { professionCache[$0.id] = $0 }
        }
        if !missing.isEmpty { await diskCache.save(professionCache, named: "professions") }
        return professionCache.filter { Set(wanted).contains($0.key) }
    }

    func specializations(ids: [Int]) async throws -> [Int: SpecializationMetadata] {
        specializationCache = await loadedIntCache(specializationCache, name: "specializations")
        specializationCache = try await filledIntCache(
            specializationCache, ids: ids, endpoint: "specializations", name: "specializations")
        return specializationCache.filter { Set(ids).contains($0.key) }
    }

    func traits(ids: [Int]) async throws -> [Int: TraitMetadata] {
        traitCache = await loadedIntCache(traitCache, name: "traits")
        traitCache = try await filledIntCache(traitCache, ids: ids, endpoint: "traits", name: "traits")
        return traitCache.filter { Set(ids).contains($0.key) }
    }

    func skills(ids: [Int]) async throws -> [Int: SkillMetadata] {
        skillCache = await loadedIntCache(skillCache, name: "skills")
        skillCache = try await filledIntCache(skillCache, ids: ids, endpoint: "skills", name: "skills")
        return skillCache.filter { Set(ids).contains($0.key) }
    }

    func skins(ids: [Int]) async throws -> [Int: SkinMetadata] {
        skinCache = await loadedIntCache(skinCache, name: "skins")
        skinCache = try await filledIntCache(skinCache, ids: ids, endpoint: "skins", name: "skins")
        return skinCache.filter { Set(ids).contains($0.key) }
    }

    func minis(ids: [Int]) async throws -> [Int: MiniMetadata] {
        miniCache = await loadedIntCache(miniCache, name: "minis")
        miniCache = try await filledIntCache(miniCache, ids: ids, endpoint: "minis", name: "minis")
        return miniCache.filter { Set(ids).contains($0.key) }
    }

    func achievementGroups() async throws -> [AchievementGroup] {
        if let cached = await diskCache.load([AchievementGroup].self, named: "achievement-groups-v1"), !cached.isEmpty {
            return cached.sorted { $0.order < $1.order }
        }
        let loaded: [AchievementGroup] = try await request("achievements/groups?ids=all")
        await diskCache.save(loaded, named: "achievement-groups-v1")
        return loaded.sorted { $0.order < $1.order }
    }

    func achievementCategories() async throws -> [AchievementCategory] {
        if let cached = await diskCache.load([AchievementCategory].self, named: "achievement-categories-v1"), !cached.isEmpty {
            return cached.sorted { $0.order < $1.order }
        }
        let loaded: [AchievementCategory] = try await request("achievements/categories?ids=all")
        await diskCache.save(loaded, named: "achievement-categories-v1")
        return loaded.sorted { $0.order < $1.order }
    }

    func achievements(ids: [Int]) async throws -> [Int: AchievementDefinition] {
        achievementCache = await loadedIntCache(achievementCache, name: "achievements-v1")
        achievementCache = try await filledIntCache(
            achievementCache, ids: ids, endpoint: "achievements", name: "achievements-v1")
        return achievementCache.filter { Set(ids).contains($0.key) }
    }

    func accountAchievements() async throws -> [AccountAchievementProgress] {
        try await authenticatedLossyArray("account/achievements")
    }

    func recipeIDs() async throws -> [Int] { try await request("recipes", priority: .low) }

    func recipes(
        ids: [Int],
        priority: APIRequestPriority = .low,
        progress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [Int: RecipeDefinition] {
        recipeCache = await loadedIntCache(recipeCache, name: "recipes-v1")
        recipeCache = try await filledIntCache(
            recipeCache, ids: ids, endpoint: "recipes", name: "recipes-v1",
            priority: priority, progress: progress)
        return recipeCache.filter { Set(ids).contains($0.key) }
    }

    func cachedRecipes() async -> [Int: RecipeDefinition] {
        recipeCache = await loadedIntCache(recipeCache, name: "recipes-v1")
        return recipeCache
    }

    func accountRecipeIDs() async throws -> [Int] { try await authenticatedRequest("account/recipes") }
    func accountSkinIDs() async throws -> [Int] { try await authenticatedRequest("account/skins") }
    func accountMiniIDs() async throws -> [Int] { try await authenticatedRequest("account/minis") }

    // MARK: - Today / account-current opportunities

    func wizardVaultSeason(language: String = "en") async throws -> WizardVaultSeason {
        try await request("wizardsvault?lang=\(Self.encodedQuery(language))")
    }

    func wizardVaultObjectives(ids: [Int], language: String = "en") async throws -> [WizardVaultObjectiveMetadata] {
        guard !ids.isEmpty else { return [] }
        return try await request(
            "wizardsvault/objectives?ids=\(Self.batchedIDs(ids).joined(separator: ","))&lang=\(Self.encodedQuery(language))")
    }

    func wizardVaultListings(ids: [Int], language: String = "en") async throws -> [WizardVaultListingMetadata] {
        guard !ids.isEmpty else { return [] }
        return try await request(
            "wizardsvault/listings?ids=\(Self.batchedIDs(ids).joined(separator: ","))&lang=\(Self.encodedQuery(language))")
    }

    func worldBossIDs() async throws -> [String] { try await request("worldbosses") }
    func mapChestIDs() async throws -> [String] { try await request("mapchests") }
    func dailyCraftingIDs() async throws -> [String] { try await request("dailycrafting") }
    func raids(language: String = "en") async throws -> [RaidDefinition] {
        try await request("raids?ids=all&lang=\(Self.encodedQuery(language))")
    }
    func dungeons(language: String = "en") async throws -> [DungeonDefinition] {
        try await request("dungeons?ids=all&lang=\(Self.encodedQuery(language))")
    }

    func wizardVaultDaily() async throws -> WizardVaultAccountPeriod {
        try await authenticatedRequest("account/wizardsvault/daily", priority: .high)
    }
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod {
        try await authenticatedRequest("account/wizardsvault/weekly", priority: .high)
    }
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial {
        try await authenticatedRequest("account/wizardsvault/special", priority: .high)
    }
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing] {
        try await authenticatedRequest("account/wizardsvault/listings", priority: .high)
    }
    func accountWorldBossIDs() async throws -> [String] { try await authenticatedRequest("account/worldbosses") }
    func accountMapChestIDs() async throws -> [String] { try await authenticatedRequest("account/mapchests") }
    func accountDailyCraftingIDs() async throws -> [String] { try await authenticatedRequest("account/dailycrafting") }
    func accountRaidEventIDs() async throws -> [String] { try await authenticatedRequest("account/raids") }
    func accountDungeonPathIDs() async throws -> [String] { try await authenticatedRequest("account/dungeons") }

    func todayItems(ids: [Int]) async throws -> [Int: ItemMetadata] { try await items(ids: ids) }
    func todayCurrencies(ids: [Int]) async throws -> [Int: CurrencyMetadata] { try await currencies(ids: ids) }
    func todayWallet() async throws -> [WalletEntry] { try await walletEntries() }

    /// Trading Post data is intentionally short-lived. Stale records remain usable as explicitly
    /// stale fallback data when the network is unavailable.
    func commercePrices(
        ids: [Int], force: Bool = false, now: Date = Date(), ttl: TimeInterval = 300,
        priority: APIRequestPriority = .normal
    ) async throws -> [Int: TimedCommercePrice] {
        commercePriceCache = await loadedIntCache(commercePriceCache, name: "commerce-prices-v1")
        let wanted = Array(Set(ids)).sorted()
        let staleOrMissing = wanted.filter { id in
            guard !force, let cached = commercePriceCache[id] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) > ttl
        }
        do {
            if priority == .high, let first = staleOrMissing.first {
                try await fetchCommerceBatch([first], now: now, priority: .high)
                let rest = Array(staleOrMissing.dropFirst())
                for batch in Self.chunks(of: rest, size: 200) {
                    try await fetchCommerceBatch(batch, now: now, priority: .normal)
                }
            } else {
                for batch in Self.chunks(of: staleOrMissing, size: 200) {
                    try await fetchCommerceBatch(batch, now: now, priority: priority)
                }
            }
            if !staleOrMissing.isEmpty {
                await diskCache.save(commercePriceCache, named: "commerce-prices-v1")
            }
        } catch {
            let fallback = commercePriceCache.filter { Set(wanted).contains($0.key) }
            if fallback.isEmpty { throw error }
        }
        for id in wanted where commercePriceCache[id] == nil {
            commercePriceCache[id] = TimedCommercePrice(
                price: CommercePrice(
                    id: id, whitelisted: nil,
                    buys: CommerceListingSummary(quantity: 0, unitPrice: 0),
                    sells: CommerceListingSummary(quantity: 0, unitPrice: 0)),
                fetchedAt: now)
        }
        return commercePriceCache.filter { Set(wanted).contains($0.key) }
    }

    private func fetchCommerceBatch(_ batch: [Int], now: Date, priority: APIRequestPriority) async throws {
        guard !batch.isEmpty else { return }
        let query = batch.map(String.init).joined(separator: ",")
        do {
            let values: [CommercePrice] = try await request("commerce/prices?ids=\(query)", priority: priority)
            values.forEach { commercePriceCache[$0.id] = TimedCommercePrice(price: $0, fetchedAt: now) }
            let returned = Set(values.map(\.id))
            for id in batch where !returned.contains(id) {
                commercePriceCache[id] = TimedCommercePrice(
                    price: CommercePrice(
                        id: id, whitelisted: nil,
                        buys: CommerceListingSummary(quantity: 0, unitPrice: 0),
                        sells: CommerceListingSummary(quantity: 0, unitPrice: 0)),
                    fetchedAt: now)
            }
        } catch {
            if batch.count == 1 {
                let id = batch[0]
                commercePriceCache[id] = TimedCommercePrice(
                    price: CommercePrice(
                        id: id, whitelisted: nil,
                        buys: CommerceListingSummary(quantity: 0, unitPrice: 0),
                        sells: CommerceListingSummary(quantity: 0, unitPrice: 0)),
                    fetchedAt: now)
                return
            }
            for id in batch {
                try await fetchCommerceBatch([id], now: now, priority: priority)
            }
        }
    }

    func materialCategories(ids: [Int]) async throws -> [Int: MaterialCategoryMetadata] {
        materialCategoryCache = await loadedIntCache(materialCategoryCache, name: "material-categories")
        materialCategoryCache = try await filledIntCache(
            materialCategoryCache, ids: ids, endpoint: "materials", name: "material-categories")
        return materialCategoryCache.filter { Set(ids).contains($0.key) }
    }

    func map(id: Int) async throws -> GW2MapMetadata {
        mapCache = await loadedIntCache(mapCache, name: "maps")
        if let cached = mapCache[id] { return cached }
        let metadata: GW2MapMetadata = try await request("maps/\(id)")
        mapCache[id] = metadata
        await diskCache.save(mapCache, named: "maps")
        return metadata
    }

    func landmarks(continentId: Int, floor: Int, mapId: Int) async throws -> [MapLandmark] {
        let key = "\(continentId)-\(floor)"
        let metadata: GW2FloorMetadata
        if let cached = floorCache[key] {
            metadata = cached
        } else if let cached = await diskCache.load(GW2FloorMetadata.self, named: "floor-\(key)") {
            floorCache[key] = cached
            metadata = cached
        } else {
            let loaded: GW2FloorMetadata = try await request("continents/\(continentId)/floors/\(floor)")
            floorCache[key] = loaded
            await diskCache.save(loaded, named: "floor-\(key)")
            metadata = loaded
        }
        guard let map = metadata.regions.values.lazy.compactMap({ $0.maps.values.first { $0.id == mapId } }).first else {
            return []
        }
        return map.landmarks()
    }

    func objectives(continentId: Int, floor: Int, mapId: Int, language: String = "en") async throws -> [MapObjective] {
        let safeLanguage = language.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "en"
        let cacheName = "world-objectives-v\(MapObjectiveCacheEnvelope.currentSchemaVersion)-\(continentId)-\(floor)-\(mapId)-\(safeLanguage)"
        let cached = await diskCache.load(MapObjectiveCacheEnvelope.self, named: cacheName)
        if let cached, cached.isCurrent { return cached.objectives }

        do {
            let loaded: GW2FloorMetadata = try await request(
                "continents/\(continentId)/floors/\(floor)?lang=\(safeLanguage)")
            guard let map = loaded.regions.values.lazy.compactMap({ region in
                region.maps.values.first { $0.id == mapId }
            }).first else { return [] }
            let objectives = map.objectives()
            await diskCache.save(
                MapObjectiveCacheEnvelope(
                    schemaVersion: MapObjectiveCacheEnvelope.currentSchemaVersion,
                    fetchedAt: Date(), objectives: objectives),
                named: cacheName)
            return objectives
        } catch {
            if let cached, cached.schemaVersion == MapObjectiveCacheEnvelope.currentSchemaVersion {
                return cached.objectives
            }
            throw error
        }
    }

    static func batchedIDs(_ ids: [Int]) -> [String] { Array(Set(ids)).sorted().map(String.init) }

    static func chunks<T>(of values: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<min($0 + size, values.count)])
        }
    }

    private func loadedIntCache<Value: Codable & Sendable>(
        _ cache: [Int: Value], name: String
    ) async -> [Int: Value] {
        guard !loadedCaches.contains(name) else { return cache }
        let loaded = await diskCache.load([Int: Value].self, named: name) ?? [:]
        loadedCaches.insert(name)
        return loaded
    }

    private func filledIntCache<Value: Codable & Sendable & Identifiable>(
        _ existing: [Int: Value], ids: [Int], endpoint: String, name: String,
        priority: APIRequestPriority = .normal,
        progress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [Int: Value] where Value.ID == Int {
        var cache = existing
        let wanted = Array(Set(ids)).sorted()
        let missing = wanted.filter { cache[$0] == nil }
        var unresolved: [Int] = []
        let batches = Self.chunks(of: missing, size: 200)
        for (index, batch) in batches.enumerated() {
            let query = batch.map(String.init).joined(separator: ",")
            let path = "\(endpoint)?ids=\(query)"
            do {
                let decoded: LossyDecodableArray<Value> = try await requestDeduplicated(path, priority: priority)
                decoded.values.forEach { cache[$0.id] = $0 }
                let returned = Set(decoded.values.map(\.id))
                unresolved.append(contentsOf: batch.filter { !returned.contains($0) })
                if !decoded.failures.isEmpty {
                    await Self.trace(
                        path: path, statusCode: 200, error: "Partial decode \(decoded.failures.prefix(3).joined(separator: "; "))",
                        decodeSucceeded: false, decodePath: decoded.failures.first)
                }
            } catch GW2APIError.server(404) {
                unresolved.append(contentsOf: batch)
            } catch {
                unresolved.append(contentsOf: batch.filter { cache[$0] == nil })
                if cache.isEmpty && index == 0 { throw error }
            }
            await progress?(index + 1, max(batches.count, 1))
            if index % 2 == 1 { await diskCache.save(cache, named: name) }
        }
        lastUnresolvedMetadataIDs[endpoint] = Array(Set(unresolved)).sorted()
        if !missing.isEmpty { await diskCache.save(cache, named: name) }
        return cache
    }

    private func authenticatedRequest<T: Decodable & Sendable>(
        _ path: String, priority: APIRequestPriority = .normal
    ) async throws -> T {
        guard let key = try credentials.getAPIKey() else { throw GW2APIError.invalidAPIKey }
        return try await request(path, apiKey: key, priority: priority)
    }

    private func authenticatedLossyArray<T: Decodable & Sendable>(
        _ path: String, priority: APIRequestPriority = .normal
    ) async throws -> [T] {
        let decoded: LossyDecodableArray<T> = try await authenticatedRequest(path, priority: priority)
        if !decoded.failures.isEmpty {
            await Self.trace(
                path: path, statusCode: 200,
                error: "Partial decode \(decoded.failures.prefix(3).joined(separator: "; "))",
                decodeSucceeded: false, decodePath: decoded.failures.first)
        }
        return decoded.values
    }

    private func authenticatedSparseArray<T: Decodable & Sendable>(
        _ path: String, priority: APIRequestPriority = .normal
    ) async throws -> [T?] {
        let decoded: SparseNullableArray<T> = try await authenticatedRequest(path, priority: priority)
        return decoded.values
    }

    private func request<T: Decodable & Sendable>(
        _ path: String, apiKey: String? = nil, priority: APIRequestPriority = .normal
    ) async throws -> T {
        let data = try await data(for: path, apiKey: apiKey, priority: priority)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            let pathText = DecodeErrorPath.describe(error)
            await Self.trace(
                path: path, statusCode: 200, error: "Decode failed \(pathText)",
                decodeSucceeded: false, decodePath: pathText)
            throw GW2APIError.decodeFailed(path: pathText)
        }
    }

    private func requestDeduplicated<T: Decodable & Sendable>(
        _ path: String, priority: APIRequestPriority = .normal
    ) async throws -> T {
        let data: Data
        if let task = inFlightBatches[path] {
            data = try await task.value
        } else {
            let task = Task { try await self.data(for: path, apiKey: nil, priority: priority) }
            inFlightBatches[path] = task
            defer { inFlightBatches[path] = nil }
            data = try await task.value
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            let pathText = DecodeErrorPath.describe(error)
            await Self.trace(
                path: path, statusCode: 200, error: "Decode failed \(pathText)",
                decodeSucceeded: false, decodePath: pathText)
            throw GW2APIError.decodeFailed(path: pathText)
        }
    }

    private func data(
        for path: String, apiKey: String?, priority: APIRequestPriority = .normal
    ) async throws -> Data {
        try await scheduler.perform(priority: priority) {
            try await self.send(path: path, apiKey: apiKey, attempt: 0)
        }
    }

    private func send(path: String, apiKey: String?, attempt: Int) async throws -> Data {
        let resolvedPath = GW2Schema.applyingQuery(to: path)
        guard let url = URL(string: resolvedPath, relativeTo: baseURL) else { throw GW2APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                await Self.trace(path: path, statusCode: nil, error: "Network unavailable")
                throw GW2APIError.networkUnavailable
            case .timedOut:
                await Self.trace(path: path, statusCode: nil, error: "Timed out")
                throw GW2APIError.timedOut
            default:
                await Self.trace(path: path, statusCode: nil, error: "Service unavailable")
                throw GW2APIError.serviceUnavailable
            }
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GW2APIError.invalidResponse }
        if http.statusCode == 429 {
            let delay = RetryAfterParser.delay(from: http, attempt: attempt)
            await scheduler.noteRateLimited(retryAfter: delay)
            await Self.trace(path: path, statusCode: 429, error: "HTTP 429")
            guard attempt < 4 else { throw GW2APIError.rateLimited }
            try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            return try await send(path: path, apiKey: apiKey, attempt: attempt + 1)
        }
        await scheduler.noteSuccess()
        let schema = GW2Schema.version(for: path)
        await Self.trace(
            path: path, statusCode: http.statusCode, error: nil, schemaVersion: schema)
        if http.statusCode == 206 {
            return data
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GW2APIError.invalidAPIKey }
            if http.statusCode == 403 { throw GW2APIError.server(403) }
            throw GW2APIError.server(http.statusCode)
        }
        return data
    }

    private static func trace(
        path: String, statusCode: Int?, error: String?, usedCache: Bool = false,
        schemaVersion: String? = nil, decodeSucceeded: Bool? = nil, decodePath: String? = nil
    ) async {
        let safePath = QARedaction.apiPath(path)
        await MainActor.run {
            DeveloperDiagnostics.shared.recordAPICall(
                path: safePath, statusCode: statusCode, error: error, usedCache: usedCache,
                schemaVersion: schemaVersion, decodeSucceeded: decodeSucceeded, decodePath: decodePath)
        }
    }

    private static func encodedPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func encodedQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

extension GW2APIClient: MapLandmarkDataProvider, MapObjectiveDataProvider {}
extension GW2APIClient: TodayDataProvider {}
