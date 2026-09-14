import Foundation

private struct TimedTodayPublicCatalog: Codable, Sendable {
    let fetchedAt: Date
    let value: TodayPublicCatalog
}

enum TodayLoadError: LocalizedError {
    case accountStateUnavailable

    var errorDescription: String? {
        switch self {
        case .accountStateUnavailable: "Today's account state could not be refreshed. Cached data remains available."
        }
    }
}

/// Owns the network/cache/merge pipeline so views never call individual Today endpoints.
actor TodayRepository {
    static let accountTTL: TimeInterval = 5 * 60
    static let publicTTL: TimeInterval = 24 * 60 * 60

    private let provider: any TodayDataProvider
    private let cache: MetadataDiskCache

    init(provider: any TodayDataProvider, cache: MetadataDiskCache = MetadataDiskCache()) {
        self.provider = provider
        self.cache = cache
    }

    func cached(accountID: String?) async -> TodayDataSnapshot? {
        await cache.load(TodayDataSnapshot.self, named: accountCacheName(accountID))
    }

    func refresh(
        accountID: String?, hasProgressionPermission: Bool, hasWalletPermission: Bool,
        language: String = "en", force: Bool = false, now: Date = Date()
    ) async throws -> TodayDataSnapshot {
        if !force, let cached = await cached(accountID: accountID),
           now.timeIntervalSince(cached.timestamp) < Self.accountTTL,
           cached.hasProgressionPermission == hasProgressionPermission {
            return cached
        }

        // Manual refresh bypasses the short account TTL, not the long metadata TTL.
        let publicCatalog = try await loadPublic(language: language, force: false, now: now)
        let account: TodayAccountPayload?
        if hasProgressionPermission {
            account = try await loadAccount(hasWalletPermission: hasWalletPermission)
        } else {
            account = nil
        }
        let merged = TodayMerger.merge(
            public: publicCatalog, account: account, accountID: accountID,
            hasProgressionPermission: hasProgressionPermission, now: now)
        await cache.save(merged, named: accountCacheName(accountID))
        return merged
    }

    private func loadPublic(language: String, force: Bool, now: Date) async throws -> TodayPublicCatalog {
        let name = "today-public-v1-\(language)"
        if !force, let cached = await cache.load(TimedTodayPublicCatalog.self, named: name),
           now.timeIntervalSince(cached.fetchedAt) < Self.publicTTL,
           Self.seasonMayStillBeCurrent(cached.value.season, now: now) {
            return cached.value
        }

        let season = try await provider.wizardVaultSeason(language: language)
        async let objectives = provider.wizardVaultObjectives(ids: season.objectives, language: language)
        async let listings = provider.wizardVaultListings(ids: season.listings, language: language)
        async let bosses = provider.worldBossIDs()
        async let chests = provider.mapChestIDs()
        async let crafting = provider.dailyCraftingIDs()
        async let raids = provider.raids(language: language)
        async let dungeons = provider.dungeons(language: language)
        async let currencies = provider.todayCurrencies(ids: [63])
        let loaded = try await (objectives, listings, bosses, chests, crafting, raids, dungeons, currencies)
        let items = try await provider.todayItems(ids: loaded.1.map(\.itemID))
        let astral = loaded.7[63].flatMap { $0.name.isEmpty ? nil : $0 }
        let catalog = TodayPublicCatalog(
            season: season, vaultObjectives: loaded.0, vaultListings: loaded.1,
            worldBossIDs: loaded.2, mapChestIDs: loaded.3, dailyCraftingIDs: loaded.4,
            raids: loaded.5, dungeons: loaded.6, items: items, astralAcclaimCurrency: astral)
        await cache.save(TimedTodayPublicCatalog(fetchedAt: now, value: catalog), named: name)
        return catalog
    }

    private func loadAccount(hasWalletPermission: Bool) async throws -> TodayAccountPayload {
        async let daily = provider.wizardVaultDaily()
        async let weekly = provider.wizardVaultWeekly()
        async let special = provider.wizardVaultSpecial()
        async let listings = provider.accountWizardVaultListings()
        async let bosses = provider.accountWorldBossIDs()
        async let chests = provider.accountMapChestIDs()
        async let crafting = provider.accountDailyCraftingIDs()
        async let raids = provider.accountRaidEventIDs()
        async let dungeons = provider.accountDungeonPathIDs()
        let loaded = try await (daily, weekly, special, listings, bosses, chests, crafting, raids, dungeons)
        let metaItemIDs = [loaded.0.metaRewardItemID, loaded.1.metaRewardItemID]
        async let rewardItems = provider.todayItems(ids: metaItemIDs)
        let wallet = hasWalletPermission ? ((try? await provider.todayWallet()) ?? []) : []
        return try await TodayAccountPayload(
            daily: loaded.0, weekly: loaded.1, special: loaded.2, listings: loaded.3,
            worldBossIDs: loaded.4, mapChestIDs: loaded.5, dailyCraftingIDs: loaded.6,
            raidEventIDs: loaded.7, dungeonPathIDs: loaded.8, wallet: wallet,
            rewardItems: rewardItems)
    }

    private func accountCacheName(_ accountID: String?) -> String {
        let raw = accountID ?? "local-anonymous"
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return "today-account-v1-" + String(safe)
    }

    private static func seasonMayStillBeCurrent(_ season: WizardVaultSeason, now: Date) -> Bool {
        guard let end = ISO8601DateFormatter().date(from: season.end) else { return true }
        return now < end
    }
}

@MainActor
final class TodayStore: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var snapshot: TodayDataSnapshot?
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var wishedRewardIDs: Set<Int> = []
    @Published private(set) var opportunityLinks: [OpportunityID: TodayOpportunityLink] = [:]

    private let repository: TodayRepository
    private let defaults: UserDefaults
    private var accountID: String?
    private var hasProgressionPermission = false
    private var hasWalletPermission = false

    init(
        provider: any TodayDataProvider, cache: MetadataDiskCache = MetadataDiskCache(),
        defaults: UserDefaults = .standard
    ) {
        repository = TodayRepository(provider: provider, cache: cache)
        self.defaults = defaults
    }

    var opportunities: [AccountOpportunity] { snapshot?.opportunities ?? [] }
    var userLinkedObjectives: [MapObjective] { opportunityLinks.values.compactMap(\.objective) }
    var progressSnapshot: TodayProgressSnapshot? { snapshot.map(TodayProgressSnapshot.init(data:)) }
    var lastUpdatedAt: Date? { snapshot?.timestamp }

    func setAccountScope(_ id: String?, permissions: PermissionSet) async {
        let scopeChanged = accountID != id
        accountID = id
        hasProgressionPermission = permissions.contains(.progression)
        hasWalletPermission = permissions.contains(.wallet)
        if scopeChanged {
            restoreWishList()
            restoreLinks()
            snapshot = await repository.cached(accountID: id)
            isStale = snapshot != nil
        }
        await refreshIfNeeded()
    }

    func refreshIfNeeded(now: Date = Date()) async {
        if let timestamp = snapshot?.timestamp,
           now.timeIntervalSince(timestamp) < TodayRepository.accountTTL,
           snapshot?.hasProgressionPermission == hasProgressionPermission { return }
        await refresh(now: now)
    }

    func refresh(force: Bool = true, now: Date = Date()) async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            snapshot = try await repository.refresh(
                accountID: accountID, hasProgressionPermission: hasProgressionPermission,
                hasWalletPermission: hasWalletPermission, force: force, now: now)
            loadState = .loaded
            errorMessage = nil
            isStale = false
        } catch is CancellationError {
            loadState = snapshot == nil ? .idle : .loaded
        } catch {
            if snapshot == nil { snapshot = await repository.cached(accountID: accountID) }
            loadState = .failed
            errorMessage = error.userFacingMessage(fallback: "Today couldn’t be refreshed. Showing saved data where possible.")
            isStale = snapshot != nil
        }
    }

    func toggleWish(_ listingID: Int) {
        if wishedRewardIDs.contains(listingID) { wishedRewardIDs.remove(listingID) }
        else { wishedRewardIDs.insert(listingID) }
        defaults.set(Array(wishedRewardIDs).sorted(), forKey: wishKey)
    }

    func isWished(_ listingID: Int) -> Bool { wishedRewardIDs.contains(listingID) }

    func link(_ opportunity: AccountOpportunity, to objective: MapObjective) {
        opportunityLinks[opportunity.id] = TodayOpportunityLink(
            opportunityID: opportunity.id, mapID: objective.mapId, mapName: nil,
            objective: objective, provenance: .userDeclared)
        persistLinks()
    }

    func linkToCurrentPosition(
        _ opportunity: AccountOpportunity, mapID: Int, position: ContinentPoint
    ) {
        let objective = MapObjective(
            id: MapObjectiveID("today:\(opportunity.id.rawValue)"), mapId: mapID,
            name: opportunity.title, type: .custom, continentX: position.x, continentY: position.y,
            source: .user, chatLink: nil, level: nil,
            description: "User-linked Today opportunity location.", state: .unknown)
        link(opportunity, to: objective)
    }

    func linkToMap(_ opportunity: AccountOpportunity, mapID: Int, mapName: String? = nil) {
        opportunityLinks[opportunity.id] = TodayOpportunityLink(
            opportunityID: opportunity.id, mapID: mapID, mapName: mapName,
            objective: nil, provenance: .userDeclared)
        persistLinks()
    }

    func removeLink(for opportunityID: OpportunityID) {
        opportunityLinks[opportunityID] = nil
        persistLinks()
    }

    private var wishKey: String { "phase6.today.vault-wishes.\(accountID ?? "local-anonymous")" }
    private func restoreWishList() { wishedRewardIDs = Set(defaults.array(forKey: wishKey) as? [Int] ?? []) }
    private var linksKey: String { "phase6.today.links.\(accountID ?? "local-anonymous")" }
    private func restoreLinks() {
        guard let data = defaults.data(forKey: linksKey),
              let values = try? JSONDecoder().decode([TodayOpportunityLink].self, from: data) else {
            opportunityLinks = [:]
            return
        }
        opportunityLinks = Dictionary(uniqueKeysWithValues: values.map { ($0.opportunityID, $0) })
    }
    private func persistLinks() {
        defaults.set(try? JSONEncoder().encode(Array(opportunityLinks.values)), forKey: linksKey)
    }
}
