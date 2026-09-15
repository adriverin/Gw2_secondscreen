import Foundation

@MainActor
final class AccountStore: ObservableObject {
    enum ConnectionState: Equatable {
        case loading
        case disconnected
        case connected
    }

    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var tokenInfo: TokenInfo?
    @Published private(set) var account: GW2Account?
    @Published private(set) var world: GW2World?
    @Published private(set) var characters: [GW2Character] = []
    @Published private(set) var professions: [String: ProfessionMetadata] = [:]
    @Published private(set) var characterInventories: [String: CharacterInventoryResponse] = [:]
    @Published private(set) var bank: [InventorySlot] = []
    @Published private(set) var bankSlots: [InventorySlot?] = []
    @Published private(set) var sharedInventory: [InventorySlot] = []
    @Published private(set) var sharedSlots: [InventorySlot?] = []
    @Published private(set) var materials: [AccountMaterial] = []
    @Published private(set) var materialCategories: [Int: MaterialCategoryMetadata] = [:]
    @Published private(set) var materialSnapshot: MaterialStorageSnapshot?
    @Published private(set) var wallet: [WalletEntry] = []
    @Published private(set) var currencies: [Int: CurrencyMetadata] = [:]
    @Published private(set) var itemMetadata: [Int: ItemMetadata] = [:]
    @Published private(set) var holdings: [AccountHolding] = []
    @Published private(set) var achievementProgress: [Int: AccountAchievementProgress] = [:]
    @Published private(set) var unlockedRecipeIDs: Set<Int> = []
    @Published private(set) var unlockedSkinIDs: Set<Int> = []
    @Published private(set) var unlockedMiniIDs: Set<Int> = []
    @Published private(set) var legendaryArmory: [AccountLegendaryArmorySlot] = []
    @Published private(set) var accountLastRefreshedAt: Date?
    @Published private(set) var goalsAccountLastRefreshedAt: Date?
    @Published private(set) var accountMetadataUpdatedAt: Date?
    @Published private(set) var charactersUpdatedAt: Date?
    @Published private(set) var inventoryUpdatedAt: Date?
    @Published private(set) var dataSource: AccountDataSource = .unknown
    @Published private(set) var characterDetails: [String: CharacterDetailData] = [:]
    @Published private(set) var loadingCharacterNames: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var liveCharacterName: String?
    @Published private(set) var domainStates: [AccountLoadDomain: AccountDomainStatus] = Dictionary(
        uniqueKeysWithValues: AccountLoadDomain.allCases.map { ($0, .idle($0)) })

    var inventoryLive: Bool {
        [.bank, .materials, .sharedInventory, .characterInventory].contains { domainStates[$0]?.phase == .live }
    }

    private let api: GW2APIClient
    private let cache: MetadataDiskCache
    private var hasStarted = false
    private var materialSnapshotGeneration = 0

    init(api: GW2APIClient, cache: MetadataDiskCache = MetadataDiskCache()) {
        self.api = api
        self.cache = cache
    }

    var permissions: PermissionSet { PermissionSet(tokenInfo?.permissions ?? []) }
    var legendaryArmoryCounts: [Int: Int] {
        Dictionary(uniqueKeysWithValues: legendaryArmory.filter { $0.count > 0 }.map { ($0.id, $0.count) })
    }
    var currentCharacter: GW2Character? {
        CurrentCharacterMatcher.match(liveName: liveCharacterName, characters: characters)
    }
    var summary: AccountSummary { AccountSummary(characters: characters, holdings: holdings) }
    var cacheStatusText: String {
        if isStale, let date = accountLastRefreshedAt {
            return "CACHED. Last updated \(date.formatted(date: .abbreviated, time: .shortened)). Quantities may have changed."
        }
        if isStale { return "CACHED. Quantities may have changed." }
        if let date = inventoryUpdatedAt ?? accountLastRefreshedAt, inventoryLive || dataSource == .live {
            return "\(AccountDataSource.live.qaLabel). Last updated \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Never loaded"
    }

    var qaCharacterBagOccupiedSlots: Int {
        characterInventories.values.reduce(0) { total, response in
            total + response.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }.count
        }
    }
    var qaBankOccupiedSlots: Int { bankSlots.compactMap { $0 }.count }
    var qaMaterialEntries: Int { materials.filter { $0.count > 0 }.count }
    var qaSharedOccupiedSlots: Int { sharedSlots.compactMap { $0 }.count }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phase2-no-inventories") {
            loadPhaseTwoLimitedInventoryFixtures()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--phase2-fixtures") {
            loadPhaseTwoFixtures()
            return
        }
#endif
        await restoreSnapshot()
        await refresh()
    }

    func restoreCachedState() async {
        guard !hasStarted else { return }
        hasStarted = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phase2-no-inventories") {
            loadPhaseTwoLimitedInventoryFixtures()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--phase2-fixtures") {
            loadPhaseTwoFixtures()
            return
        }
#endif
        await restoreSnapshot()
    }

    func updateLiveCharacter(name: String?) { liveCharacterName = name }

    func connect(apiKey: String) async throws {
        tokenInfo = try await api.validateAndSave(apiKey: apiKey)
        await refresh()
    }

    func disconnect() async throws {
        try await api.disconnect()
        tokenInfo = nil
        account = nil
        world = nil
        characters = []
        professions = [:]
        characterInventories = [:]
        bank = []
        bankSlots = []
        sharedInventory = []
        sharedSlots = []
        materials = []
        materialCategories = [:]
        materialSnapshot = nil
        wallet = []
        currencies = [:]
        itemMetadata = [:]
        holdings = []
        achievementProgress = [:]
        unlockedRecipeIDs = []
        unlockedSkinIDs = []
        unlockedMiniIDs = []
        legendaryArmory = []
        accountLastRefreshedAt = nil
        goalsAccountLastRefreshedAt = nil
        accountMetadataUpdatedAt = nil
        charactersUpdatedAt = nil
        inventoryUpdatedAt = nil
        characterDetails = [:]
        errorMessage = nil
        isStale = false
        dataSource = .unknown
        connectionState = .disconnected
        domainStates = Dictionary(uniqueKeysWithValues: AccountLoadDomain.allCases.map { ($0, .idle($0)) })
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard let info = try await api.savedTokenInfo() else {
                connectionState = .disconnected
                tokenInfo = nil
                return
            }
            tokenInfo = info
            connectionState = .connected
            let allowed = PermissionSet(info.permissions)

            async let accountLoad: Void = refreshAccountIdentity(allowed: allowed)
            async let characterLoad: Void = refreshCharacters(allowed: allowed)
            async let walletLoad: Void = refreshWallet(allowed: allowed)
            _ = await (accountLoad, characterLoad, walletLoad)

            if allowed.contains(.inventories) {
                await refreshInventories()
            } else {
                markMissingPermission([.characterInventory, .bank, .materials, .sharedInventory])
            }

            await loadGoalAccountData(permissions: allowed)
            await refreshLegendaryArmory(allowed: allowed)

            let failed = domainStates.values.filter { $0.phase == .failed }
            let liveCount = domainStates.values.filter { $0.phase == .live }.count
            errorMessage = liveCount == 0 ? failed.first?.message : nil
            isStale = liveCount == 0 && (account != nil || !characters.isEmpty || !wallet.isEmpty)
            dataSource = liveCount > 0 ? .live : (account != nil || !characters.isEmpty ? .cached : .unknown)
            if liveCount > 0 { accountLastRefreshedAt = Date() }
            await saveSnapshot()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.userFacingMessage(fallback: "Account data couldn’t be refreshed. Showing saved data where possible.")
            isStale = !characters.isEmpty || account != nil || !holdings.isEmpty || !wallet.isEmpty
            if tokenInfo == nil { connectionState = .disconnected }
        }
    }

    /// Refreshes the authenticated goal endpoints without polling every inventory endpoint.
    /// Goals calls this on entry and on explicit refresh; it never runs at telemetry frequency.
    func refreshGoalAccountData() async {
        guard connectionState == .connected else { return }
        await loadGoalAccountData(permissions: permissions)
        await refreshLegendaryArmory(allowed: permissions)
        await saveSnapshot()
    }

    func loadCharacterDetails(_ character: GW2Character, force: Bool = false) async {
        if !force, let existing = characterDetails[character.name], existing.source == .live { return }
        guard !loadingCharacterNames.contains(character.name) else { return }
        loadingCharacterNames.insert(character.name)
        defer { loadingCharacterNames.remove(character.name) }

        var detail = characterDetails[character.name] ?? CharacterDetailData()
        let allowed = permissions

        if allowed.contains(.builds) {
            do {
                detail.equipmentTabs = try await api.equipmentTabs(character: character.name)
                detail.equipmentError = nil
                markDomain(.equipmentTabs, phase: .live, endpoint: "characters/{name}/equipmenttabs")
            } catch {
                detail.equipmentError = error.userFacingMessage(fallback: "Couldn't refresh equipment tabs.")
                markDomain(.equipmentTabs, phase: .failed, endpoint: "characters/{name}/equipmenttabs", error: error)
            }
            do {
                detail.buildTabs = try await api.buildTabs(character: character.name)
                detail.buildError = nil
                markDomain(.buildTabs, phase: .live, endpoint: "characters/{name}/buildtabs")
            } catch {
                detail.buildError = error.userFacingMessage(fallback: "Couldn't refresh builds")
                markDomain(.buildTabs, phase: .failed, endpoint: "characters/{name}/buildtabs", error: error)
            }
        } else {
            markDomain(.buildTabs, phase: .missingPermission, endpoint: "characters/{name}/buildtabs")
            if let equipment = character.equipment {
                detail.equipmentTabs = [
                    EquipmentTab(tab: character.activeEquipmentTab ?? 1, name: "Equipment", isActive: true, equipment: equipment)
                ]
            }
        }

        if allowed.contains(.inventories) {
            do {
                if let cached = characterInventories[character.name] { detail.inventory = cached }
                else { detail.inventory = try await api.characterInventoryResponse(name: character.name) }
                detail.inventoryError = nil
                markDomain(.characterInventory, phase: .live, endpoint: "characters/{name}/inventory")
            } catch {
                detail.inventoryError = error.userFacingMessage(fallback: "Couldn't refresh character inventory.")
                markDomain(.characterInventory, phase: .failed, endpoint: "characters/{name}/inventory", error: error)
            }
        }

        let equipment = detail.equipmentTabs.flatMap(\.equipment)
        var itemIDs: [Int] = []
        for equipped in equipment {
            itemIDs.append(equipped.itemID)
            itemIDs.append(contentsOf: equipped.upgrades ?? [])
            itemIDs.append(contentsOf: equipped.infusions ?? [])
        }
        if let bags = detail.inventory?.bags {
            for bag in bags.compactMap({ $0 }) {
                if let bagID = bag.id { itemIDs.append(bagID) }
                itemIDs.append(contentsOf: (bag.inventory ?? []).compactMap { $0?.id })
            }
        }
        if let resolved = try? await api.items(ids: itemIDs, priority: .high) {
            detail.items = resolved
        }
        if let resolved = try? await api.skins(ids: equipment.compactMap(\.skin)) {
            detail.skins = resolved
        }

        let builds = detail.buildTabs.map(\.build)
        let specializationIDs = builds.flatMap(\.specializations).compactMap(\.id)
        if let resolved = try? await api.specializations(ids: specializationIDs) {
            detail.specializations.merge(resolved) { _, new in new }
        }
        let traitIDs = builds.flatMap(\.specializations).flatMap(\.traits).compactMap { $0 }
        if let resolved = try? await api.traits(ids: traitIDs) {
            detail.traits.merge(resolved) { _, new in new }
        }
        let skillIDs = builds.flatMap { build -> [Int] in
            [build.skills.terrestrial, build.skills.aquatic, build.skills.pve, build.skills.pvp, build.skills.wvw]
                .compactMap { $0 }.flatMap {
                [$0.heal, $0.elite].compactMap { $0 } + $0.utilities.compactMap { $0 }
            }
        }
        if let resolved = try? await api.skills(ids: skillIDs) {
            detail.skills.merge(resolved) { _, new in new }
        }

        let parts = [detail.buildError, detail.equipmentError, detail.inventoryError].compactMap { $0 }
        detail.errorMessage = parts.isEmpty ? nil : parts.first
        if parts.isEmpty {
            detail.source = .live
            detail.updatedAt = Date()
        } else if let previous = characterDetails[character.name],
                  (!previous.equipmentTabs.isEmpty || !previous.buildTabs.isEmpty) {
            if detail.equipmentTabs.isEmpty { detail.equipmentTabs = previous.equipmentTabs }
            if detail.buildTabs.isEmpty { detail.buildTabs = previous.buildTabs }
            if detail.inventory == nil { detail.inventory = previous.inventory }
            if detail.items.isEmpty { detail.items = previous.items }
            if detail.specializations.isEmpty { detail.specializations = previous.specializations }
            if detail.traits.isEmpty { detail.traits = previous.traits }
            if detail.skills.isEmpty { detail.skills = previous.skills }
            detail.source = .cached
            detail.updatedAt = previous.updatedAt ?? Date()
        } else {
            detail.source = connectionState == .connected ? .live : .cached
            detail.updatedAt = Date()
        }
        characterDetails[character.name] = detail
        await saveSnapshot()
    }

    func eliteSpecializationName(for character: GW2Character) -> String? {
        guard let detail = characterDetails[character.name] else { return nil }
        let active = detail.buildTabs.first(where: \.isActive) ?? detail.buildTabs.first
        return active?.build.specializations.compactMap { specialization in
            specialization.id.flatMap { detail.specializations[$0] }
        }.last(where: \.elite)?.name
    }

#if DEBUG
    private func loadPhaseTwoFixtures() {
        let decoder = JSONDecoder()
        tokenInfo = TokenInfo(
            id: "fixture-key", name: "Phase 2 fixtures",
            permissions: ["account", "characters", "inventories", "builds", "wallet"])
        account = GW2Account(
            id: "fixture-account", name: "Andrea.1234", world: 2203,
            created: "2018-05-18T17:42:00Z", commander: true, fractalLevel: 42,
            dailyAP: 8_000, monthlyAP: 500, wvwRank: 321)
        world = GW2World(id: 2203, name: "Gandara", population: "High")
        characters = (try? decoder.decode([GW2Character].self, from: Data(Self.fixtureCharacters.utf8))) ?? []
        professions = [
            "Mesmer": ProfessionMetadata(id: "Mesmer", name: "Mesmer", icon: nil, iconBig: nil, specializations: [66]),
            "Ranger": ProfessionMetadata(id: "Ranger", name: "Ranger", icon: nil, iconBig: nil, specializations: [])
        ]
        let andreaInventory = (try? decoder.decode(CharacterInventoryResponse.self, from: Data(Self.fixtureInventory.utf8)))
            ?? CharacterInventoryResponse(bags: [])
        characterInventories = ["Andrea": andreaInventory, "Test Mesmer": andreaInventory]
        bank = [InventorySlot(id: 19697, count: 211), InventorySlot(id: 46731, count: 4)]
        bankSlots = [InventorySlot(id: 19697, count: 211), nil, InventorySlot(id: 46731, count: 4), nil]
        sharedInventory = [InventorySlot(id: 19697, count: 100)]
        sharedSlots = [InventorySlot(id: 19697, count: 100), nil]
        materials = [AccountMaterial(id: 19697, category: 5, count: 250)]
        itemMetadata = (try? decoder.decode([ItemMetadata].self, from: Data(Self.fixtureItems.utf8)))
            .map { Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) }) } ?? [:]
        materialCategories = [5: MaterialCategoryMetadata(id: 5, name: "Basic Crafting Materials", items: [19697], order: 1)]
        rebuildMaterialSnapshot()
        wallet = [WalletEntry(id: 1, value: 3_824_100), WalletEntry(id: 2, value: 1_423_443), WalletEntry(id: 23, value: 481)]
        currencies = [
            1: CurrencyMetadata(id: 1, name: "Coin", description: "Your liquid coin balance.", icon: nil, order: 1),
            2: CurrencyMetadata(id: 2, name: "Karma", description: "Earned by helping Tyrians.", icon: nil, order: 2),
            23: CurrencyMetadata(id: 23, name: "Spirit Shard", description: "A crafting currency.", icon: nil, order: 3)
        ]
        var sources: [(ItemLocation, [InventorySlot])] = [
            (.character("Andrea"), andreaInventory.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }),
            (.character("Test Mesmer"), [InventorySlot(id: 19697, count: 173)]),
            (.bank, bank), (.sharedInventory, sharedInventory),
            (.materialStorage, [InventorySlot(id: 19697, count: 250)])
        ]
        sources.append((.character("Sylvari Ranger"), [InventorySlot(id: 46731, count: 8)]))
        holdings = AccountHoldingAggregator.aggregate(sources)

        let equipmentTabs = (try? decoder.decode([EquipmentTab].self, from: Data(Self.fixtureEquipment.utf8))) ?? []
        let buildTabs = (try? decoder.decode([BuildTab].self, from: Data(Self.fixtureBuild.utf8))) ?? []
        let specializations = [66: SpecializationMetadata(
            id: 66, name: "Virtuoso", profession: "Mesmer", elite: true, icon: nil, background: nil,
            minorTraits: [], majorTraits: [31, 32, 33])]
        let traits = Dictionary(uniqueKeysWithValues: (31...33).map {
            ($0, TraitMetadata(id: $0, name: "Selected Virtuoso Trait \($0 - 30)", icon: nil, description: "A selected fixture trait.", tier: $0 - 30, slot: "Major"))
        })
        let skillIDs = [5503, 5519, 5570, 10234, 29519]
        let skills = Dictionary(uniqueKeysWithValues: skillIDs.map {
            ($0, SkillMetadata(id: $0, name: "Fixture Skill \($0)", icon: nil, description: "A resolved fixture skill.", type: "Utility", weaponType: nil, slot: "Utility"))
        })
        let detail = CharacterDetailData(
            equipmentTabs: equipmentTabs, buildTabs: buildTabs, inventory: andreaInventory,
            items: itemMetadata, skins: [:], specializations: specializations, traits: traits,
            skills: skills, errorMessage: nil)
        characterDetails = ["Andrea": detail, "Test Mesmer": detail]
        connectionState = .connected
        errorMessage = nil
        isStale = false
        dataSource = .live
        accountLastRefreshedAt = Date()
        accountMetadataUpdatedAt = Date()
        charactersUpdatedAt = Date()
        inventoryUpdatedAt = Date()
    }

    private func loadPhaseTwoLimitedInventoryFixtures() {
        loadPhaseTwoFixtures()
        tokenInfo = TokenInfo(
            id: "limited-key", name: "Limited key",
            permissions: ["account", "characters"])
        characterInventories = [:]
        bank = []
        bankSlots = []
        sharedInventory = []
        sharedSlots = []
        materials = []
        holdings = []
        characterDetails = characterDetails.mapValues { detail in
            var copy = detail
            copy.inventory = nil
            return copy
        }
    }
#endif

    private func refreshAccountIdentity(allowed: PermissionSet) async {
        guard allowed.contains(.account) else {
            markDomain(.account, phase: .missingPermission, endpoint: "account")
            return
        }
        markDomain(.account, phase: .loading, endpoint: "account")
        do {
            account = try await api.account()
            accountMetadataUpdatedAt = Date()
            if let worldID = account?.world { world = try? await api.world(id: worldID) }
            markDomain(.account, phase: .live, endpoint: "account")
        } catch {
            markDomain(.account, phase: .failed, endpoint: "account", error: error)
        }
    }

    private func refreshCharacters(allowed: PermissionSet) async {
        guard allowed.contains(.characters) else {
            markDomain(.characters, phase: .missingPermission, endpoint: "characters")
            return
        }
        markDomain(.characters, phase: .loading, endpoint: "characters")
        do {
            characters = try await api.characters().sorted {
                if $0.level != $1.level { return $0.level > $1.level }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            charactersUpdatedAt = Date()
            if let loaded = try? await api.professions(ids: characters.map(\.profession)) {
                professions = loaded
            }
            markDomain(.characters, phase: .live, endpoint: "characters")
        } catch {
            markDomain(.characters, phase: .failed, endpoint: "characters", error: error)
        }
    }

    private func refreshWallet(allowed: PermissionSet) async {
        guard allowed.contains(.wallet) else {
            markDomain(.wallet, phase: .missingPermission, endpoint: "account/wallet")
            return
        }
        markDomain(.wallet, phase: .loading, endpoint: "account/wallet")
        do {
            wallet = try await api.walletEntries()
            currencies = (try? await api.currencies(ids: wallet.map(\.id), priority: .high)) ?? currencies
            markDomain(.wallet, phase: .live, endpoint: "account/wallet")
        } catch {
            markDomain(.wallet, phase: .failed, endpoint: "account/wallet", error: error)
        }
    }

    private func markDomain(
        _ domain: AccountLoadDomain, phase: AccountDomainPhase, endpoint: String,
        error: Error? = nil, httpStatus: Int? = nil
    ) {
        let mapped = error.map(Self.mapAPIError)
        let decode = Self.decodeInfo(error)
        let schema = GW2Schema.version(for: endpoint)
        domainStates[domain] = AccountDomainStatus(
            domain: domain, phase: phase, endpoint: endpoint,
            httpStatus: httpStatus ?? mapped?.status,
            schemaVersion: schema,
            source: phase == .cached ? .cached : (phase == .live ? .live : dataSource),
            decodeSucceeded: decode.succeeded ?? (phase == .failed ? nil : true),
            decodePath: decode.path,
            message: error?.userFacingMessage(fallback: mapped?.message ?? phase.rawValue),
            updatedAt: Date())
        let result = QADomainRefreshResult(
            domain: qaDomain(for: domain), success: phase == .live,
            httpStatus: httpStatus ?? mapped?.status,
            message: error?.userFacingMessage(fallback: mapped?.message ?? phase.rawValue) ?? phase.rawValue,
            usedCache: phase == .cached, timestamp: Date())
        DeveloperDiagnostics.shared.recordDomainRefresh(result)
        DeveloperDiagnostics.shared.recordAPICall(
            path: endpoint, statusCode: httpStatus ?? mapped?.status,
            error: phase == .failed ? (error?.userFacingMessage(fallback: mapped?.message ?? "failed")) : nil,
            usedCache: phase == .cached, schemaVersion: schema,
            decodeSucceeded: decode.succeeded ?? true,
            decodePath: decode.path)
    }

    private static func decodeInfo(_ error: Error?) -> (succeeded: Bool?, path: String?) {
        guard let api = error as? GW2APIError else { return (nil, nil) }
        if case let .decodeFailed(path) = api { return (false, path) }
        return (nil, nil)
    }

    private func markMissingPermission(_ domains: [AccountLoadDomain]) {
        for domain in domains {
            markDomain(domain, phase: .missingPermission, endpoint: domain.rawValue)
        }
    }

    private func qaDomain(for domain: AccountLoadDomain) -> QADomain {
        switch domain {
        case .account: .account
        case .characters: .characters
        case .characterInventory, .bank, .materials, .sharedInventory: .inventory
        case .equipment, .equipmentTabs, .buildTabs: .builds
        case .achievements, .recipesUnlocked: .achievements
        case .today: .today
        case .wallet: .account
        }
    }

    private func loadGoalAccountData(permissions: PermissionSet) async {
        if permissions.contains(.progression) {
            markDomain(.achievements, phase: .loading, endpoint: "account/achievements")
            do {
                let values = try await api.accountAchievements()
                achievementProgress = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
                markDomain(.achievements, phase: .live, endpoint: "account/achievements")
            } catch {
                markDomain(.achievements, phase: .failed, endpoint: "account/achievements", error: error)
            }
        } else {
            achievementProgress = [:]
            markDomain(.achievements, phase: .missingPermission, endpoint: "account/achievements")
        }

        if permissions.contains(.unlocks) {
            markDomain(.recipesUnlocked, phase: .loading, endpoint: "account/recipes")
            async let recipes = try? api.accountRecipeIDs()
            async let skins = try? api.accountSkinIDs()
            async let minis = try? api.accountMiniIDs()
            let resolved = await (recipes, skins, minis)
            if let values = resolved.0 {
                unlockedRecipeIDs = Set(values)
                markDomain(.recipesUnlocked, phase: .live, endpoint: "account/recipes")
            } else {
                markDomain(
                    .recipesUnlocked, phase: .failed, endpoint: "account/recipes",
                    error: GW2APIError.invalidResponse)
            }
            if let values = resolved.1 { unlockedSkinIDs = Set(values) }
            if let values = resolved.2 { unlockedMiniIDs = Set(values) }
        } else {
            unlockedRecipeIDs = []
            unlockedSkinIDs = []
            unlockedMiniIDs = []
            markDomain(.recipesUnlocked, phase: .missingPermission, endpoint: "account/recipes")
        }
        goalsAccountLastRefreshedAt = Date()
    }

    private func refreshLegendaryArmory(allowed: PermissionSet) async {
        guard allowed.contains(.account), allowed.contains(.inventories), allowed.contains(.unlocks) else {
            return
        }
        do {
            legendaryArmory = try await api.accountLegendaryArmory()
        } catch {
            if legendaryArmory.isEmpty {
                legendaryArmory = []
            }
        }
    }

#if DEBUG
    private static let fixtureCharacters = #"""
    [{"name":"Andrea","race":"Human","gender":"Female","profession":"Mesmer","level":80,"age":4467600,"created":"2018-05-18T17:42:00Z","deaths":83,"crafting":[{"discipline":"Tailor","rating":500,"active":true}]},{"name":"Test Mesmer","race":"Human","gender":"Female","profession":"Mesmer","level":80,"age":1241000,"created":"2025-01-01T12:00:00Z","deaths":14,"crafting":[]},{"name":"Sylvari Ranger","race":"Sylvari","gender":"Male","profession":"Ranger","level":35,"age":1537200,"created":"2024-01-04T12:00:00Z","deaths":12,"crafting":[]}]
    """#
    private static let fixtureInventory = #"{"bags":[{"id":20,"size":5,"inventory":[{"id":19697,"count":173},null,{"id":46731,"count":4},null,null]}]}"#
    private static let fixtureItems = #"[{"id":20,"name":"Starter Backpack","icon":null,"rarity":"Basic","type":"Bag","level":0},{"id":19697,"name":"Mithril Ore","icon":null,"rarity":"Basic","type":"CraftingMaterial","level":0},{"id":46731,"name":"Bolt of Damask","icon":null,"rarity":"Ascended","type":"CraftingMaterial","level":0},{"id":101,"name":"Zojja's Sword","icon":null,"rarity":"Ascended","type":"Weapon","level":80,"details":{"type":"Sword","infix_upgrade":{"id":161,"attributes":[{"attribute":"Power","modifier":125},{"attribute":"Precision","modifier":90},{"attribute":"Ferocity","modifier":90}],"buff":null}}},{"id":201,"name":"Superior Sigil of Force","icon":null,"rarity":"Exotic","type":"UpgradeComponent","level":60},{"id":301,"name":"+9 Agony Infusion","icon":null,"rarity":"Fine","type":"UpgradeComponent","level":0}]"#
    private static let fixtureEquipment = #"[{"tab":1,"name":"Raid DPS","is_active":true,"equipment":[{"id":101,"slot":"WeaponA1","stats":{"id":161,"attributes":{"Power":125,"Precision":90,"Ferocity":90}},"upgrades":[201],"infusions":[301],"binding":"Account"}]},{"tab":2,"name":"Open World","is_active":false,"equipment":[]}]"#
    private static let fixtureBuild = #"[{"tab":1,"name":"Power Virtuoso","is_active":true,"build":{"name":"Power Virtuoso","profession":"Mesmer","specializations":[{"id":66,"traits":[31,32,33]}],"skills":{"terrestrial":{"heal":5503,"utilities":[5519,5570,10234],"elite":29519},"aquatic":null,"pve":null,"pvp":null,"wvw":null}}}]"#
#endif

    private func refreshInventories() async {
        markDomain(.characterInventory, phase: .loading, endpoint: "characters/{name}/inventory")
        markDomain(.bank, phase: .loading, endpoint: "account/bank")
        markDomain(.sharedInventory, phase: .loading, endpoint: "account/inventory")
        markDomain(.materials, phase: .loading, endpoint: "account/materials")

        async let characterLoad: Void = loadCharacterInventories()
        async let bankLoad: Void = loadBank()
        async let sharedLoad: Void = loadSharedInventory()
        async let materialsLoad: Void = loadMaterials()
        _ = await (characterLoad, bankLoad, sharedLoad, materialsLoad)

        var sources: [(ItemLocation, [InventorySlot])] = characterInventories.map { name, response in
            let slots = response.bags.compactMap { $0 }.flatMap { $0.inventory ?? [] }.compactMap { $0 }
            return (.character(name), slots)
        }
        sources.append((.bank, bank))
        sources.append((.sharedInventory, sharedInventory))
        sources.append((.materialStorage, materials.filter { $0.count > 0 }.map {
            InventorySlot(id: $0.id, count: $0.count, binding: $0.binding)
        }))
        holdings = AccountHoldingAggregator.aggregate(sources)
        if let resolvedItems = try? await api.items(ids: holdings.map(\.itemID), priority: .high) {
            itemMetadata.merge(resolvedItems) { _, new in new }
        }
        for holding in holdings where itemMetadata[holding.itemID] == nil {
            itemMetadata[holding.itemID] = ItemPlaceholder.metadata(id: holding.itemID)
        }
        materialCategories = (try? await api.materialCategories(ids: materials.map(\.category))) ?? materialCategories
        inventoryUpdatedAt = Date()
        await refreshMaterialItemMetadata(priority: .high)
        rebuildMaterialSnapshot()
    }

    private func refreshMaterialItemMetadata(priority: APIRequestPriority) async {
        let ids = materials.map(\.id)
        guard !ids.isEmpty else { return }
        if let resolvedItems = try? await api.items(ids: ids, priority: priority) {
            itemMetadata.merge(resolvedItems) { _, new in new }
        }
        for material in materials where itemMetadata[material.id] == nil {
            itemMetadata[material.id] = ItemPlaceholder.metadata(id: material.id)
        }
    }

    func rebuildMaterialSnapshot() {
        materialSnapshotGeneration += 1
        let generation = materialSnapshotGeneration
        let materials = materials
        let categories = materialCategories
        let metadata = itemMetadata
        let source = dataSource
        let updatedAt = inventoryUpdatedAt ?? Date()
        Task.detached(priority: .userInitiated) {
            let snapshot = MaterialStorageSnapshotBuilder.build(
                materials: materials, categories: categories, metadata: metadata,
                source: source, updatedAt: updatedAt)
            await MainActor.run {
                guard self.materialSnapshotGeneration == generation else { return }
                self.materialSnapshot = snapshot
            }
        }
    }

    private func loadCharacterInventories() async {
        var loadedCharacters: [String: CharacterInventoryResponse] = [:]
        var inventoryFailures = 0
        let names = characters.map(\.name)
        for batch in stride(from: 0, to: names.count, by: 4) {
            let slice = names[batch..<min(batch + 4, names.count)]
            await withTaskGroup(of: (String, CharacterInventoryResponse?).self) { group in
                for name in slice {
                    group.addTask { [api] in
                        let response = try? await api.characterInventoryResponse(name: name)
                        return (name, response)
                    }
                }
                for await (name, response) in group {
                    if let response { loadedCharacters[name] = response }
                    else { inventoryFailures += 1 }
                }
            }
        }
        if !loadedCharacters.isEmpty { characterInventories.merge(loadedCharacters) { _, new in new } }
        if !names.isEmpty && loadedCharacters.isEmpty {
            markDomain(
                .characterInventory, phase: .failed, endpoint: "characters/{name}/inventory",
                error: GW2APIError.invalidResponse)
        } else if !names.isEmpty {
            markDomain(.characterInventory, phase: .live, endpoint: "characters/{name}/inventory")
        }
        _ = inventoryFailures
    }

    private func loadBank() async {
        do {
            bankSlots = try await api.bankSlots()
            bank = bankSlots.compactMap { $0 }
            markDomain(.bank, phase: .live, endpoint: "account/bank")
        } catch {
            markDomain(.bank, phase: .failed, endpoint: "account/bank", error: error)
        }
    }

    private func loadSharedInventory() async {
        do {
            sharedSlots = try await api.sharedInventorySlots()
            sharedInventory = sharedSlots.compactMap { $0 }
            markDomain(.sharedInventory, phase: .live, endpoint: "account/inventory")
        } catch {
            markDomain(.sharedInventory, phase: .failed, endpoint: "account/inventory", error: error)
        }
    }

    private func loadMaterials() async {
        do {
            materials = try await api.accountMaterials()
            markDomain(.materials, phase: .live, endpoint: "account/materials")
        } catch {
            markDomain(.materials, phase: .failed, endpoint: "account/materials", error: error)
        }
    }

    private func restoreSnapshot() async {
        guard let snapshot = await cache.load(AccountSnapshot.self, named: "account-snapshot") else { return }
        tokenInfo = snapshot.tokenInfo
        account = snapshot.account
        world = snapshot.world
        characters = snapshot.characters
        professions = snapshot.professions
        characterInventories = snapshot.characterInventories
        bank = snapshot.bank
        bankSlots = snapshot.bankSlots ?? snapshot.bank.map { Optional($0) }
        sharedInventory = snapshot.sharedInventory
        sharedSlots = snapshot.sharedSlots ?? snapshot.sharedInventory.map { Optional($0) }
        materials = snapshot.materials
        materialCategories = snapshot.materialCategories
        wallet = snapshot.wallet
        currencies = snapshot.currencies
        itemMetadata = snapshot.itemMetadata
        holdings = snapshot.holdings
        achievementProgress = snapshot.achievementProgress ?? [:]
        unlockedRecipeIDs = Set(snapshot.unlockedRecipeIDs ?? [])
        unlockedSkinIDs = Set(snapshot.unlockedSkinIDs ?? [])
        unlockedMiniIDs = Set(snapshot.unlockedMiniIDs ?? [])
        legendaryArmory = snapshot.legendaryArmory ?? []
        accountLastRefreshedAt = snapshot.accountLastRefreshedAt
        goalsAccountLastRefreshedAt = snapshot.goalsAccountLastRefreshedAt
        accountMetadataUpdatedAt = snapshot.accountMetadataUpdatedAt ?? snapshot.accountLastRefreshedAt
        charactersUpdatedAt = snapshot.charactersUpdatedAt ?? snapshot.accountLastRefreshedAt
        inventoryUpdatedAt = snapshot.inventoryUpdatedAt ?? snapshot.accountLastRefreshedAt
        characterDetails = (snapshot.characterDetails ?? [:]).mapValues { detail in
            var copy = detail
            copy.source = .cached
            return copy
        }
        isStale = true
        dataSource = .cached
        connectionState = snapshot.tokenInfo == nil ? .disconnected : .connected
        for domain in [AccountLoadDomain.account, .characters, .wallet, .bank, .materials, .sharedInventory, .characterInventory] {
            if domainStates[domain]?.phase != .live {
                var status = domainStates[domain] ?? .idle(domain)
                status.phase = .cached
                status.source = .cached
                domainStates[domain] = status
            }
        }
        rebuildMaterialSnapshot()
    }

    private func saveSnapshot() async {
        let snapshot = AccountSnapshot(
            tokenInfo: tokenInfo, account: account, world: world, characters: characters,
            professions: professions, characterInventories: characterInventories, bank: bank,
            bankSlots: bankSlots, sharedInventory: sharedInventory, sharedSlots: sharedSlots, materials: materials, materialCategories: materialCategories,
            wallet: wallet, currencies: currencies, itemMetadata: itemMetadata, holdings: holdings,
            achievementProgress: achievementProgress, unlockedRecipeIDs: Array(unlockedRecipeIDs),
            unlockedSkinIDs: Array(unlockedSkinIDs), unlockedMiniIDs: Array(unlockedMiniIDs),
            legendaryArmory: legendaryArmory,
            accountLastRefreshedAt: accountLastRefreshedAt,
            goalsAccountLastRefreshedAt: goalsAccountLastRefreshedAt,
            accountMetadataUpdatedAt: accountMetadataUpdatedAt,
            charactersUpdatedAt: charactersUpdatedAt,
            inventoryUpdatedAt: inventoryUpdatedAt,
            characterDetails: characterDetails)
        await cache.save(snapshot, named: "account-snapshot")
    }
}

private struct AccountSnapshot: Codable, Sendable {
    let tokenInfo: TokenInfo?
    let account: GW2Account?
    let world: GW2World?
    let characters: [GW2Character]
    let professions: [String: ProfessionMetadata]
    let characterInventories: [String: CharacterInventoryResponse]
    let bank: [InventorySlot]
    var bankSlots: [InventorySlot?]?
    let sharedInventory: [InventorySlot]
    var sharedSlots: [InventorySlot?]?
    let materials: [AccountMaterial]
    let materialCategories: [Int: MaterialCategoryMetadata]
    let wallet: [WalletEntry]
    let currencies: [Int: CurrencyMetadata]
    let itemMetadata: [Int: ItemMetadata]
    let holdings: [AccountHolding]
    let achievementProgress: [Int: AccountAchievementProgress]?
    let unlockedRecipeIDs: [Int]?
    let unlockedSkinIDs: [Int]?
    let unlockedMiniIDs: [Int]?
    var legendaryArmory: [AccountLegendaryArmorySlot]?
    let accountLastRefreshedAt: Date?
    let goalsAccountLastRefreshedAt: Date?
    var accountMetadataUpdatedAt: Date?
    var charactersUpdatedAt: Date?
    var inventoryUpdatedAt: Date?
    var characterDetails: [String: CharacterDetailData]?
}

extension AccountStore {
    func refreshQADomain(_ domain: QADomain) async -> QADomainRefreshResult {
        let started = Date()
        do {
            switch domain {
            case .account:
                guard permissions.contains(.account) else {
                    return qaFailure(domain, status: 403, message: "Missing account permission", at: started)
                }
                account = try await api.account()
                if let worldID = account?.world { world = try? await api.world(id: worldID) }
                accountMetadataUpdatedAt = Date()
                dataSource = .live
                return qaSuccess(domain, status: 200, message: "OK", at: Date())
            case .characters:
                guard permissions.contains(.characters) else {
                    return qaFailure(domain, status: 403, message: "Missing characters permission", at: started)
                }
                characters = try await api.characters().sorted {
                    if $0.level != $1.level { return $0.level > $1.level }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                professions = (try? await api.professions(ids: characters.map(\.profession))) ?? professions
                charactersUpdatedAt = Date()
                dataSource = .live
                return qaSuccess(domain, status: 200, message: "OK", at: Date())
            case .inventory:
                guard permissions.contains(.inventories) else {
                    return qaFailure(domain, status: 403, message: "Missing inventories permission", at: started)
                }
                await refreshInventories()
                dataSource = .live
                isStale = false
                return qaSuccess(domain, status: 200, message: "OK", at: Date())
            case .builds:
                guard permissions.contains(.builds) else {
                    return qaFailure(domain, status: 403, message: "Missing builds permission", at: started)
                }
                guard let character = currentCharacter ?? characters.first else {
                    return qaFailure(domain, status: nil, message: "No character available", at: started)
                }
                await loadCharacterDetails(character, force: true)
                if let error = characterDetails[character.name]?.buildError {
                    return qaFailure(domain, status: nil, message: error, at: Date())
                }
                return qaSuccess(domain, status: 200, message: "OK", at: Date())
            case .achievements:
                guard permissions.contains(.progression) else {
                    return qaFailure(domain, status: 403, message: "Missing progression permission", at: started)
                }
                await loadGoalAccountData(permissions: permissions)
                return qaSuccess(domain, status: 200, message: "OK", at: Date())
            case .today:
                return qaFailure(domain, status: nil, message: "Today is refreshed by TodayStore", at: started)
            }
        } catch {
            let mapped = Self.mapAPIError(error)
            return qaFailure(domain, status: mapped.status, message: mapped.message, at: Date())
        }
    }

    func refreshAllQADomains() async -> [QADomainRefreshResult] {
        var results: [QADomainRefreshResult] = []
        for domain in [QADomain.account, .characters, .inventory, .builds, .achievements] {
            results.append(await refreshQADomain(domain))
        }
        accountLastRefreshedAt = Date()
        await saveSnapshot()
        return results
    }

    static func mapAPIError(_ error: Error) -> (status: Int?, message: String) {
        if let api = error as? GW2APIError {
            switch api {
            case .invalidAPIKey: return (401, api.errorDescription ?? "Invalid API key")
            case let .missingPermission(permission): return (403, "Missing \(permission) permission")
            case .rateLimited: return (429, "HTTP 429")
            case let .decodeFailed(path): return (nil, "Decode failed at \(path)")
            case let .server(code) where code == 403: return (403, "HTTP 403")
            case let .server(code): return (code, api.errorDescription ?? "Server error")
            default: return (nil, error.userFacingMessage(fallback: "Request failed"))
            }
        }
        return (nil, error.userFacingMessage(fallback: "Request failed"))
    }

    private func qaSuccess(_ domain: QADomain, status: Int?, message: String, at: Date) -> QADomainRefreshResult {
        let result = QADomainRefreshResult(
            domain: domain, success: true, httpStatus: status, message: message, usedCache: false, timestamp: at)
        DeveloperDiagnostics.shared.recordDomainRefresh(result)
        return result
    }

    private func qaFailure(_ domain: QADomain, status: Int?, message: String, at: Date) -> QADomainRefreshResult {
        let result = QADomainRefreshResult(
            domain: domain, success: false, httpStatus: status, message: message, usedCache: dataSource == .cached,
            timestamp: at)
        DeveloperDiagnostics.shared.recordDomainRefresh(result)
        return result
    }
}
