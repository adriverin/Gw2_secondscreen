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
    @Published private(set) var sharedInventory: [InventorySlot] = []
    @Published private(set) var materials: [AccountMaterial] = []
    @Published private(set) var materialCategories: [Int: MaterialCategoryMetadata] = [:]
    @Published private(set) var wallet: [WalletEntry] = []
    @Published private(set) var currencies: [Int: CurrencyMetadata] = [:]
    @Published private(set) var itemMetadata: [Int: ItemMetadata] = [:]
    @Published private(set) var holdings: [AccountHolding] = []
    @Published private(set) var achievementProgress: [Int: AccountAchievementProgress] = [:]
    @Published private(set) var unlockedRecipeIDs: Set<Int> = []
    @Published private(set) var unlockedSkinIDs: Set<Int> = []
    @Published private(set) var unlockedMiniIDs: Set<Int> = []
    @Published private(set) var accountLastRefreshedAt: Date?
    @Published private(set) var goalsAccountLastRefreshedAt: Date?
    @Published private(set) var characterDetails: [String: CharacterDetailData] = [:]
    @Published private(set) var loadingCharacterNames: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var liveCharacterName: String?

    private let api: GW2APIClient
    private let cache: MetadataDiskCache
    private var hasStarted = false

    init(api: GW2APIClient, cache: MetadataDiskCache = MetadataDiskCache()) {
        self.api = api
        self.cache = cache
    }

    var permissions: PermissionSet { PermissionSet(tokenInfo?.permissions ?? []) }
    var currentCharacter: GW2Character? {
        CurrentCharacterMatcher.match(liveName: liveCharacterName, characters: characters)
    }
    var summary: AccountSummary { AccountSummary(characters: characters, holdings: holdings) }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phase2-fixtures") {
            loadPhaseTwoFixtures()
            return
        }
#endif
        await restoreSnapshot()
        await refresh()
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
        sharedInventory = []
        materials = []
        materialCategories = [:]
        wallet = []
        currencies = [:]
        itemMetadata = [:]
        holdings = []
        achievementProgress = [:]
        unlockedRecipeIDs = []
        unlockedSkinIDs = []
        unlockedMiniIDs = []
        accountLastRefreshedAt = nil
        goalsAccountLastRefreshedAt = nil
        characterDetails = [:]
        errorMessage = nil
        isStale = false
        connectionState = .disconnected
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

            if allowed.contains(.account) {
                account = try await api.account()
                if let worldID = account?.world { world = try? await api.world(id: worldID) }
            }

            if allowed.contains(.characters) {
                characters = try await api.characters().sorted {
                    if $0.level != $1.level { return $0.level > $1.level }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                professions = try await api.professions(ids: characters.map(\.profession))
            }

            if allowed.contains(.inventories) {
                await refreshInventories()
            } else {
                characterInventories = [:]
                bank = []
                sharedInventory = []
                materials = []
                holdings = []
            }

            if allowed.contains(.wallet) {
                wallet = try await api.walletEntries()
                currencies = try await api.currencies(ids: wallet.map(\.id))
            } else {
                wallet = []
                currencies = [:]
            }

            await loadGoalAccountData(permissions: allowed)

            errorMessage = nil
            isStale = false
            accountLastRefreshedAt = Date()
            await saveSnapshot()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            isStale = !characters.isEmpty || account != nil || !holdings.isEmpty
            if tokenInfo == nil { connectionState = .disconnected }
        }
    }

    /// Refreshes the authenticated goal endpoints without polling every inventory endpoint.
    /// Goals calls this on entry and on explicit refresh; it never runs at telemetry frequency.
    func refreshGoalAccountData() async {
        guard connectionState == .connected else { return }
        await loadGoalAccountData(permissions: permissions)
        await saveSnapshot()
    }

    func loadCharacterDetails(_ character: GW2Character, force: Bool = false) async {
        if !force, characterDetails[character.name] != nil { return }
        guard !loadingCharacterNames.contains(character.name) else { return }
        loadingCharacterNames.insert(character.name)
        defer { loadingCharacterNames.remove(character.name) }

        var detail = characterDetails[character.name] ?? CharacterDetailData()
        let allowed = permissions
        do {
            if allowed.contains(.builds) {
                detail.equipmentTabs = try await api.equipmentTabs(character: character.name)
                detail.buildTabs = try await api.buildTabs(character: character.name)
            } else if let equipment = character.equipment {
                detail.equipmentTabs = [
                    EquipmentTab(tab: character.activeEquipmentTab ?? 1, name: "Equipment", isActive: true, equipment: equipment)
                ]
            }

            if allowed.contains(.inventories) {
                if let cached = characterInventories[character.name] { detail.inventory = cached }
                else { detail.inventory = try await api.characterInventoryResponse(name: character.name) }
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
                    itemIDs.append(contentsOf: (bag.inventory ?? []).compactMap { $0?.id })
                }
            }
            detail.items = try await api.items(ids: itemIDs)
            detail.skins = try await api.skins(ids: equipment.compactMap(\.skin))

            let builds = detail.buildTabs.map(\.build)
            let specializationIDs = builds.flatMap(\.specializations).compactMap(\.id)
            detail.specializations = try await api.specializations(ids: specializationIDs)
            let traitIDs = builds.flatMap(\.specializations).flatMap(\.traits).compactMap { $0 }
            detail.traits = try await api.traits(ids: traitIDs)
            let skillIDs = builds.flatMap { build -> [Int] in
                [build.skills.terrestrial, build.skills.aquatic, build.skills.pve, build.skills.pvp, build.skills.wvw]
                    .compactMap { $0 }.flatMap {
                    [$0.heal, $0.elite].compactMap { $0 } + $0.utilities.compactMap { $0 }
                }
            }
            detail.skills = try await api.skills(ids: skillIDs)
            detail.errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            detail.errorMessage = error.localizedDescription
        }
        characterDetails[character.name] = detail
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
        sharedInventory = [InventorySlot(id: 19697, count: 100)]
        materials = [AccountMaterial(id: 19697, category: 5, count: 250)]
        itemMetadata = (try? decoder.decode([ItemMetadata].self, from: Data(Self.fixtureItems.utf8)))
            .map { Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) }) } ?? [:]
        materialCategories = [5: MaterialCategoryMetadata(id: 5, name: "Basic Crafting Materials", items: [19697], order: 1)]
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
    }

    private func loadGoalAccountData(permissions: PermissionSet) async {
        if permissions.contains(.progression) {
            if let values = try? await api.accountAchievements() {
                achievementProgress = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
            }
        } else {
            achievementProgress = [:]
        }

        if permissions.contains(.unlocks) {
            async let recipes = try? api.accountRecipeIDs()
            async let skins = try? api.accountSkinIDs()
            async let minis = try? api.accountMiniIDs()
            let resolved = await (recipes, skins, minis)
            if let values = resolved.0 { unlockedRecipeIDs = Set(values) }
            if let values = resolved.1 { unlockedSkinIDs = Set(values) }
            if let values = resolved.2 { unlockedMiniIDs = Set(values) }
        } else {
            unlockedRecipeIDs = []
            unlockedSkinIDs = []
            unlockedMiniIDs = []
        }
        goalsAccountLastRefreshedAt = Date()
    }

    private static let fixtureCharacters = #"""
    [{"name":"Andrea","race":"Human","gender":"Female","profession":"Mesmer","level":80,"age":4467600,"created":"2018-05-18T17:42:00Z","deaths":83,"crafting":[{"discipline":"Tailor","rating":500,"active":true}]},{"name":"Test Mesmer","race":"Human","gender":"Female","profession":"Mesmer","level":80,"age":1241000,"created":"2025-01-01T12:00:00Z","deaths":14,"crafting":[]},{"name":"Sylvari Ranger","race":"Sylvari","gender":"Male","profession":"Ranger","level":35,"age":1537200,"created":"2024-01-04T12:00:00Z","deaths":12,"crafting":[]}]
    """#
    private static let fixtureInventory = #"{"bags":[{"id":20,"size":5,"inventory":[{"id":19697,"count":173},null,{"id":46731,"count":4},null,null]}]}"#
    private static let fixtureItems = #"[{"id":19697,"name":"Mithril Ore","icon":null,"rarity":"Basic","type":"CraftingMaterial","level":0},{"id":46731,"name":"Bolt of Damask","icon":null,"rarity":"Ascended","type":"CraftingMaterial","level":0},{"id":101,"name":"Zojja's Sword","icon":null,"rarity":"Ascended","type":"Weapon","level":80,"details":{"type":"Sword","infix_upgrade":{"id":161,"attributes":[{"attribute":"Power","modifier":125},{"attribute":"Precision","modifier":90},{"attribute":"Ferocity","modifier":90}],"buff":null}}},{"id":201,"name":"Superior Sigil of Force","icon":null,"rarity":"Exotic","type":"UpgradeComponent","level":60},{"id":301,"name":"+9 Agony Infusion","icon":null,"rarity":"Fine","type":"UpgradeComponent","level":0}]"#
    private static let fixtureEquipment = #"[{"tab":1,"name":"Raid DPS","is_active":true,"equipment":[{"id":101,"slot":"WeaponA1","stats":{"id":161,"attributes":{"Power":125,"Precision":90,"Ferocity":90}},"upgrades":[201],"infusions":[301],"binding":"Account"}]},{"tab":2,"name":"Open World","is_active":false,"equipment":[]}]"#
    private static let fixtureBuild = #"[{"tab":1,"name":"Power Virtuoso","is_active":true,"build":{"name":"Power Virtuoso","profession":"Mesmer","specializations":[{"id":66,"traits":[31,32,33]}],"skills":{"terrestrial":{"heal":5503,"utilities":[5519,5570,10234],"elite":29519},"aquatic":null,"pve":null,"pvp":null,"wvw":null}}}]"#
#endif

    private func refreshInventories() async {
        var loadedCharacters: [String: CharacterInventoryResponse] = [:]
        await withTaskGroup(of: (String, CharacterInventoryResponse?).self) { group in
            for character in characters {
                group.addTask { [api] in
                    let response = try? await api.characterInventoryResponse(name: character.name)
                    return (character.name, response)
                }
            }
            for await (name, response) in group {
                if let response { loadedCharacters[name] = response }
            }
        }
        characterInventories = loadedCharacters

        async let loadedBank = api.bank()
        async let loadedShared = api.sharedInventory()
        async let loadedMaterials = api.accountMaterials()
        bank = (try? await loadedBank) ?? bank
        sharedInventory = (try? await loadedShared) ?? sharedInventory
        materials = (try? await loadedMaterials) ?? materials

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
        if let resolvedItems = try? await api.items(ids: holdings.map(\.itemID)) {
            itemMetadata = resolvedItems
        }
        materialCategories = (try? await api.materialCategories(ids: materials.map(\.category))) ?? materialCategories
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
        sharedInventory = snapshot.sharedInventory
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
        accountLastRefreshedAt = snapshot.accountLastRefreshedAt
        goalsAccountLastRefreshedAt = snapshot.goalsAccountLastRefreshedAt
        isStale = true
        connectionState = snapshot.tokenInfo == nil ? .disconnected : .connected
    }

    private func saveSnapshot() async {
        let snapshot = AccountSnapshot(
            tokenInfo: tokenInfo, account: account, world: world, characters: characters,
            professions: professions, characterInventories: characterInventories, bank: bank,
            sharedInventory: sharedInventory, materials: materials, materialCategories: materialCategories,
            wallet: wallet, currencies: currencies, itemMetadata: itemMetadata, holdings: holdings,
            achievementProgress: achievementProgress, unlockedRecipeIDs: Array(unlockedRecipeIDs),
            unlockedSkinIDs: Array(unlockedSkinIDs), unlockedMiniIDs: Array(unlockedMiniIDs),
            accountLastRefreshedAt: accountLastRefreshedAt,
            goalsAccountLastRefreshedAt: goalsAccountLastRefreshedAt)
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
    let sharedInventory: [InventorySlot]
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
    let accountLastRefreshedAt: Date?
    let goalsAccountLastRefreshedAt: Date?
}
