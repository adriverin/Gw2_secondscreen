import Foundation

enum GW2APIError: LocalizedError, Equatable {
    case invalidAPIKey
    case missingPermission(String)
    case invalidResponse
    case server(Int)
    case rateLimited
    case serviceUnavailable
    case networkUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "This API key is invalid or has been revoked. Create or paste a new key."
        case let .missingPermission(permission): "Your API key does not include the \(permission) permission."
        case .invalidResponse: "ArenaNet returned data this version of the app could not read. Your saved data is still available."
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
        try await authenticatedRequest("characters?page=0&page_size=200")
    }

    func characterInventoryResponse(name: String) async throws -> CharacterInventoryResponse {
        try await authenticatedRequest("characters/\(Self.encodedPath(name))/inventory")
    }

    func characterInventory(name: String) async throws -> [InventorySlot] {
        let response = try await characterInventoryResponse(name: name)
        return response.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }
    }

    func equipmentTabs(character name: String) async throws -> [EquipmentTab] {
        try await authenticatedRequest("characters/\(Self.encodedPath(name))/equipmenttabs?tabs=all")
    }

    func buildTabs(character name: String) async throws -> [BuildTab] {
        try await authenticatedRequest("characters/\(Self.encodedPath(name))/buildtabs?tabs=all")
    }

    func bank() async throws -> [InventorySlot] {
        let slots: [InventorySlot?] = try await authenticatedRequest("account/bank")
        return slots.compactMap { $0 }
    }

    func sharedInventory() async throws -> [InventorySlot] {
        let slots: [InventorySlot?] = try await authenticatedRequest("account/inventory")
        return slots.compactMap { $0 }
    }

    func accountMaterials() async throws -> [AccountMaterial] {
        try await authenticatedRequest("account/materials")
    }

    func materials() async throws -> [InventorySlot] {
        try await accountMaterials().filter { $0.count > 0 }.map {
            InventorySlot(id: $0.id, count: $0.count, binding: $0.binding)
        }
    }

    func walletEntries() async throws -> [WalletEntry] { try await authenticatedRequest("account/wallet") }

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

    func items(ids: [Int]) async throws -> [Int: ItemMetadata] {
        itemCache = await loadedIntCache(itemCache, name: "items")
        itemCache = try await filledIntCache(itemCache, ids: ids, endpoint: "items", name: "items")
        return itemCache.filter { Set(ids).contains($0.key) }
    }

    func currencies(ids: [Int]) async throws -> [Int: CurrencyMetadata] {
        currencyCache = await loadedIntCache(currencyCache, name: "currencies")
        currencyCache = try await filledIntCache(currencyCache, ids: ids, endpoint: "currencies", name: "currencies")
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
        try await authenticatedRequest("account/achievements")
    }

    func recipeIDs() async throws -> [Int] { try await request("recipes") }

    func recipes(ids: [Int]) async throws -> [Int: RecipeDefinition] {
        recipeCache = await loadedIntCache(recipeCache, name: "recipes-v1")
        recipeCache = try await filledIntCache(recipeCache, ids: ids, endpoint: "recipes", name: "recipes-v1")
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
        try await authenticatedRequest("account/wizardsvault/daily")
    }
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod {
        try await authenticatedRequest("account/wizardsvault/weekly")
    }
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial {
        try await authenticatedRequest("account/wizardsvault/special")
    }
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing] {
        try await authenticatedRequest("account/wizardsvault/listings")
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
        ids: [Int], force: Bool = false, now: Date = Date(), ttl: TimeInterval = 300
    ) async throws -> [Int: TimedCommercePrice] {
        commercePriceCache = await loadedIntCache(commercePriceCache, name: "commerce-prices-v1")
        let wanted = Array(Set(ids)).sorted()
        let staleOrMissing = wanted.filter { id in
            guard !force, let cached = commercePriceCache[id] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) > ttl
        }
        do {
            for batch in Self.chunks(of: staleOrMissing, size: 200) {
                let query = batch.map(String.init).joined(separator: ",")
                let values: [CommercePrice] = try await request("commerce/prices?ids=\(query)")
                values.forEach { commercePriceCache[$0.id] = TimedCommercePrice(price: $0, fetchedAt: now) }
            }
            if !staleOrMissing.isEmpty {
                await diskCache.save(commercePriceCache, named: "commerce-prices-v1")
            }
        } catch {
            let fallback = commercePriceCache.filter { Set(wanted).contains($0.key) }
            if fallback.isEmpty { throw error }
        }
        return commercePriceCache.filter { Set(wanted).contains($0.key) }
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
        _ existing: [Int: Value], ids: [Int], endpoint: String, name: String
    ) async throws -> [Int: Value] where Value.ID == Int {
        var cache = existing
        let wanted = Array(Set(ids)).sorted()
        let missing = wanted.filter { cache[$0] == nil }
        for batch in Self.chunks(of: missing, size: 200) {
            let query = batch.map(String.init).joined(separator: ",")
            let values: [Value] = try await requestDeduplicated("\(endpoint)?ids=\(query)")
            values.forEach { cache[$0.id] = $0 }
        }
        if !missing.isEmpty { await diskCache.save(cache, named: name) }
        return cache
    }

    private func authenticatedRequest<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let key = try credentials.getAPIKey() else { throw GW2APIError.invalidAPIKey }
        return try await request(path, apiKey: key)
    }

    private func request<T: Decodable & Sendable>(_ path: String, apiKey: String? = nil) async throws -> T {
        let data = try await data(for: path, apiKey: apiKey)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GW2APIError.invalidResponse }
    }

    private func requestDeduplicated<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let data: Data
        if let task = inFlightBatches[path] {
            data = try await task.value
        } else {
            let task = Task { try await self.data(for: path, apiKey: nil) }
            inFlightBatches[path] = task
            defer { inFlightBatches[path] = nil }
            data = try await task.value
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GW2APIError.invalidResponse }
    }

    private func data(for path: String, apiKey: String?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw GW2APIError.invalidResponse }
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
                throw GW2APIError.networkUnavailable
            case .timedOut: throw GW2APIError.timedOut
            default: throw GW2APIError.serviceUnavailable
            }
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GW2APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GW2APIError.invalidAPIKey }
            if http.statusCode == 403 { throw GW2APIError.missingPermission("required") }
            if http.statusCode == 429 { throw GW2APIError.rateLimited }
            if [500, 502, 503, 504].contains(http.statusCode) { throw GW2APIError.serviceUnavailable }
            throw GW2APIError.server(http.statusCode)
        }
        return data
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
