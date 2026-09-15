import Foundation

struct TodayPublicCatalog: Codable, Sendable {
    var season: WizardVaultSeason
    var vaultObjectives: [WizardVaultObjectiveMetadata]
    var vaultListings: [WizardVaultListingMetadata]
    var worldBossIDs: [String]
    var mapChestIDs: [String]
    var dailyCraftingIDs: [String]
    var raids: [RaidDefinition]
    var dungeons: [DungeonDefinition]
    var items: [Int: ItemMetadata]
    var astralAcclaimCurrency: CurrencyMetadata?
}

struct TodayAccountPayload: Sendable {
    var daily: WizardVaultAccountPeriod
    var weekly: WizardVaultAccountPeriod
    var special: WizardVaultAccountSpecial
    var listings: [WizardVaultAccountListing]
    var worldBossIDs: [String]
    var mapChestIDs: [String]
    var dailyCraftingIDs: [String]
    var raidEventIDs: [String]
    var dungeonPathIDs: [String]
    var wallet: [WalletEntry]
    var rewardItems: [Int: ItemMetadata]
}

enum TodayMerger {
    static func mergeVaultOnly(
        daily: WizardVaultAccountPeriod?,
        weekly: WizardVaultAccountPeriod?,
        special: WizardVaultAccountSpecial?,
        listings: [WizardVaultAccountListing],
        catalog: TodayPublicCatalog?,
        accountID: String?,
        hasProgressionPermission: Bool,
        now: Date = Date()
    ) -> TodayDataSnapshot {
        var opportunities: [AccountOpportunity] = []
        if let daily { opportunities += vaultOpportunities(daily.objectives, type: .wizardVaultDaily, scope: .daily) }
        if let weekly { opportunities += vaultOpportunities(weekly.objectives, type: .wizardVaultWeekly, scope: .weekly) }
        if let special { opportunities += vaultOpportunities(special.objectives, type: .wizardVaultSpecial, scope: .seasonal) }
        let items = catalog?.items ?? [:]
        let dailyMeta = daily.map { meta($0, scope: .daily, items: items) }
        let weeklyMeta = weekly.map { meta($0, scope: .weekly, items: items) }
        return TodayDataSnapshot(
            timestamp: now, accountID: accountID, season: catalog?.season, opportunities: opportunities,
            dailyMeta: dailyMeta, weeklyMeta: weeklyMeta, vaultRewards: [],
            astralAcclaimBalance: nil, hasProgressionPermission: hasProgressionPermission,
            diagnostics: TodayDiagnostics(
                dailyObjectiveCount: daily?.objectives.count ?? 0,
                weeklyObjectiveCount: weekly?.objectives.count ?? 0,
                specialObjectiveCount: special?.objectives.count ?? 0,
                claimableCount: opportunities.filter(\.state.isClaimable).count,
                worldBossIDs: [], mapChestIDs: [], dailyCraftingIDs: [], raidEventIDs: [],
                dungeonPathIDs: [], unknownIDs: []))
    }

    static func merge(
        public catalog: TodayPublicCatalog,
        account: TodayAccountPayload?,
        accountID: String?,
        hasProgressionPermission: Bool,
        now: Date = Date()
    ) -> TodayDataSnapshot {
        var opportunities: [AccountOpportunity] = []
        var unknown: [String] = []

        if let account {
            opportunities += vaultOpportunities(account.daily.objectives, type: .wizardVaultDaily, scope: .daily)
            opportunities += vaultOpportunities(account.weekly.objectives, type: .wizardVaultWeekly, scope: .weekly)
            opportunities += vaultOpportunities(account.special.objectives, type: .wizardVaultSpecial, scope: .seasonal)
        }

        opportunities += checklist(
            publicIDs: catalog.worldBossIDs, completedIDs: account.map { Set($0.worldBossIDs) },
            type: .worldBoss, scope: .daily, unknown: &unknown)
        opportunities += checklist(
            publicIDs: catalog.mapChestIDs, completedIDs: account.map { Set($0.mapChestIDs) },
            type: .mapChest, scope: .daily, unknown: &unknown)
        opportunities += checklist(
            publicIDs: catalog.dailyCraftingIDs, completedIDs: account.map { Set($0.dailyCraftingIDs) },
            type: .dailyCrafting, scope: .daily, unknown: &unknown)

        let raidEvents = catalog.raids.flatMap { raid in
            raid.wings.flatMap { wing in
                wing.events.compactMap { event -> ChecklistDefinition? in
                    guard event.type == .boss else {
                        if case let .unknown(raw) = event.type { unknown.append("raid-event-type:\(raw):\(event.id)") }
                        return nil
                    }
                    return ChecklistDefinition(
                        id: event.id, title: CuratedOpportunityCatalog.title(event.id),
                        subtitle: CuratedOpportunityCatalog.title(wing.id), mapID: nil, mapName: nil,
                        relatedItemIDs: [], activity: .raids)
                }
            }
        }
        opportunities += checklist(
            definitions: raidEvents, completedIDs: account.map { Set($0.raidEventIDs) },
            type: .raidEncounter, scope: .weekly, unknown: &unknown)

        let dungeonPaths = catalog.dungeons.flatMap { dungeon in
            dungeon.paths.map { path in
                ChecklistDefinition(
                    id: path.id, title: CuratedOpportunityCatalog.dungeonPathTitle(path.id, type: path.type),
                    subtitle: CuratedOpportunityCatalog.title(dungeon.id), mapID: nil, mapName: nil,
                    relatedItemIDs: [], activity: .dungeons)
            }
        }
        opportunities += checklist(
            definitions: dungeonPaths, completedIDs: account.map { Set($0.dungeonPathIDs) },
            type: .dungeonPath, scope: .daily, unknown: &unknown)

        let allItems = catalog.items.merging(account?.rewardItems ?? [:]) { _, new in new }
        let rewards = rewardListings(public: catalog.vaultListings, account: account?.listings, items: allItems)
        for reward in rewards {
            if case let .unknown(raw) = reward.type { unknown.append("vault-listing-type:\(raw):\(reward.id)") }
        }

        let dailyMeta = account.map { meta($0.daily, scope: .daily, items: allItems) }
        let weeklyMeta = account.map { meta($0.weekly, scope: .weekly, items: allItems) }
        let astralID = catalog.astralAcclaimCurrency.flatMap { currency in
            currency.name.compare("Astral Acclaim", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                ? currency.id : nil
        }
        let balance = astralID.flatMap { id in account?.wallet.first(where: { $0.id == id })?.value }
        let sorted = opportunities.sorted { lhs, rhs in
            if lhs.resetScope != rhs.resetScope { return scopeRank(lhs.resetScope) < scopeRank(rhs.resetScope) }
            if lhs.type != rhs.type { return lhs.type.rawValue < rhs.type.rawValue }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return TodayDataSnapshot(
            timestamp: now, accountID: accountID, season: catalog.season, opportunities: sorted,
            dailyMeta: dailyMeta, weeklyMeta: weeklyMeta, vaultRewards: rewards,
            astralAcclaimBalance: balance, hasProgressionPermission: hasProgressionPermission,
            diagnostics: TodayDiagnostics(
                dailyObjectiveCount: account?.daily.objectives.count ?? 0,
                weeklyObjectiveCount: account?.weekly.objectives.count ?? 0,
                specialObjectiveCount: account?.special.objectives.count ?? 0,
                claimableCount: sorted.filter(\.state.isClaimable).count
                    + [dailyMeta, weeklyMeta].compactMap { $0 }.filter { $0.state.isClaimable }.count,
                worldBossIDs: account?.worldBossIDs ?? [], mapChestIDs: account?.mapChestIDs ?? [],
                dailyCraftingIDs: account?.dailyCraftingIDs ?? [], raidEventIDs: account?.raidEventIDs ?? [],
                dungeonPathIDs: account?.dungeonPathIDs ?? [], unknownIDs: Array(Set(unknown)).sorted()))
    }

    private static func vaultOpportunities(
        _ objectives: [WizardVaultAccountObjective], type: OpportunityType, scope: OpportunityResetScope
    ) -> [AccountOpportunity] {
        objectives.map { objective in
            let progress = OpportunityProgress(current: objective.progressCurrent, complete: objective.progressComplete)
            let state: OpportunityState = objective.claimed ? .completeClaimed : (progress.isComplete ? .completeUnclaimed : .incomplete)
            return AccountOpportunity(
                id: OpportunityID("\(type.rawValue):\(objective.id)"), type: type, resetScope: scope,
                urgency: urgency(scope), title: objective.title, subtitle: objective.track,
                progress: progress,
                reward: OpportunityReward(astralAcclaim: objective.acclaim, itemID: nil, itemName: nil),
                state: state, activity: activity(for: objective.track), relatedItemIDs: [],
                relatedAchievementIDs: [], mapID: nil, mapName: nil,
                sourceIdentifier: String(objective.id), provenance: [.arenaNetAccount])
        }
    }

    private static func meta(
        _ period: WizardVaultAccountPeriod, scope: OpportunityResetScope, items: [Int: ItemMetadata]
    ) -> VaultMetaProgress {
        VaultMetaProgress(
            resetScope: scope,
            progress: OpportunityProgress(current: period.metaProgressCurrent, complete: period.metaProgressComplete),
            reward: OpportunityReward(
                astralAcclaim: period.metaRewardAstral, itemID: period.metaRewardItemID,
                itemName: items[period.metaRewardItemID]?.name), claimed: period.metaRewardClaimed)
    }

    private static func checklist(
        publicIDs: [String], completedIDs: Set<String>?, type: OpportunityType,
        scope: OpportunityResetScope, unknown: inout [String]
    ) -> [AccountOpportunity] {
        let definitions = publicIDs.map { id in
            let location = CuratedOpportunityCatalog.location(for: type, id: id)
            return ChecklistDefinition(
                id: id, title: CuratedOpportunityCatalog.displayName(for: type, id: id), subtitle: nil,
                mapID: location?.mapID, mapName: location?.name,
                relatedItemIDs: CuratedOpportunityCatalog.relatedItemIDs(for: type, id: id),
                activity: type == .dailyCrafting ? .crafting : .pve)
        }
        return checklist(
            definitions: definitions, completedIDs: completedIDs, type: type, scope: scope, unknown: &unknown)
    }

    private static func checklist(
        definitions: [ChecklistDefinition], completedIDs: Set<String>?, type: OpportunityType,
        scope: OpportunityResetScope, unknown: inout [String]
    ) -> [AccountOpportunity] {
        let publicIDs = Set(definitions.map(\.id))
        var values = definitions.map { definition in
            AccountOpportunity(
                id: OpportunityID("\(type.rawValue):\(definition.id)"), type: type, resetScope: scope,
                urgency: urgency(scope), title: definition.title, subtitle: definition.subtitle,
                progress: nil, reward: nil,
                state: completedIDs.map { $0.contains(definition.id) ? .completed : .incomplete } ?? .unknown,
                activity: definition.activity, relatedItemIDs: definition.relatedItemIDs,
                relatedAchievementIDs: [], mapID: definition.mapID, mapName: definition.mapName,
                sourceIdentifier: definition.id,
                provenance: completedIDs == nil ? [.arenaNetPublic] : [.arenaNetPublic, .arenaNetAccount])
        }
        for id in (completedIDs ?? []).subtracting(publicIDs).sorted() {
            unknown.append("\(type.rawValue):\(id)")
            values.append(AccountOpportunity(
                id: OpportunityID("\(type.rawValue):\(id)"), type: type, resetScope: scope,
                urgency: urgency(scope), title: "Unknown \(type.title.dropLast(type.title.hasSuffix("s") ? 1 : 0))",
                subtitle: "Developer ID: \(id)", progress: nil, reward: nil, state: .completed,
                activity: type == .dailyCrafting ? .crafting : .pve, relatedItemIDs: [],
                relatedAchievementIDs: [], mapID: nil, mapName: nil, sourceIdentifier: id,
                provenance: [.arenaNetAccount]))
        }
        return values
    }

    private static func rewardListings(
        public values: [WizardVaultListingMetadata], account: [WizardVaultAccountListing]?,
        items: [Int: ItemMetadata]
    ) -> [VaultRewardListing] {
        let accountByID = Dictionary(uniqueKeysWithValues: (account ?? []).map { ($0.id, $0) })
        let publicByID = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let ids = Set(publicByID.keys).union(accountByID.keys)
        return ids.compactMap { id in
            guard let itemID = accountByID[id]?.itemID ?? publicByID[id]?.itemID,
                  let itemCount = accountByID[id]?.itemCount ?? publicByID[id]?.itemCount,
                  let type = accountByID[id]?.type ?? publicByID[id]?.type,
                  let cost = accountByID[id]?.cost ?? publicByID[id]?.cost else { return nil }
            return VaultRewardListing(
                id: id, itemID: itemID, itemName: items[itemID]?.name ?? "Unknown Item \(itemID)",
                icon: items[itemID]?.icon, itemCount: itemCount, type: type, cost: cost,
                purchased: accountByID[id]?.purchased, purchaseLimit: accountByID[id]?.purchaseLimit)
        }.sorted { lhs, rhs in
            if lhs.type.sortOrder != rhs.type.sortOrder { return lhs.type.sortOrder < rhs.type.sortOrder }
            if lhs.cost != rhs.cost { return lhs.cost < rhs.cost }
            return lhs.id < rhs.id
        }
    }

    private static func scopeRank(_ scope: OpportunityResetScope) -> Int {
        switch scope { case .daily: 0; case .weekly: 1; case .seasonal: 2; case .none: 3 }
    }

    private static func urgency(_ scope: OpportunityResetScope) -> OpportunityUrgency {
        switch scope { case .daily: .daily; case .weekly: .weekly; case .seasonal: .seasonal; case .none: .none }
    }

    private static func activity(for track: String) -> OpportunityActivityCategory {
        switch track.lowercased() { case "pve": .pve; case "pvp": .pvp; case "wvw": .wvw; default: .unknown }
    }
}

private struct ChecklistDefinition {
    let id: String
    let title: String
    let subtitle: String?
    let mapID: Int?
    let mapName: String?
    let relatedItemIDs: [Int]
    let activity: OpportunityActivityCategory
}

enum CuratedOpportunityCatalog {
    struct Location { let mapID: Int; let name: String }

    private static let names: [String: String] = [
        "admiral_taidha_covington": "Admiral Taidha Covington", "claw_of_jormag": "Claw of Jormag",
        "drakkar": "Drakkar", "fire_elemental": "Fire Elemental", "great_jungle_wurm": "Great Jungle Wurm",
        "inquest_golem_mark_ii": "Inquest Golem Mark II", "karka_queen": "Karka Queen",
        "megadestroyer": "Megadestroyer", "mists_and_monsters_titans": "Mists and Monsters Titans",
        "modniir_ulgoth": "Modniir Ulgoth", "shadow_behemoth": "Shadow Behemoth",
        "svanir_shaman_chief": "Svanir Shaman Chief", "tequatl_the_sunless": "Tequatl the Sunless",
        "the_shatterer": "The Shatterer", "triple_trouble_wurm": "Triple Trouble Wurm",
        "charged_quartz_crystal": "Charged Quartz Crystal", "glob_of_elder_spirit_residue": "Glob of Elder Spirit Residue",
        "lump_of_mithrilium": "Lump of Mithrillium", "spool_of_silk_weaving_thread": "Spool of Silk Weaving Thread",
        "spool_of_thick_elonian_cord": "Spool of Thick Elonian Cord",
        "spirit_vale": "Spirit Vale", "salvation_pass": "Salvation Pass",
        "stronghold_of_the_faithful": "Stronghold of the Faithful", "bastion_of_the_penitent": "Bastion of the Penitent",
        "hall_of_chains": "Hall of Chains", "mythwright_gambit": "Mythwright Gambit",
        "the_key_of_ahdashim": "The Key of Ahdashim", "mount_balrior": "Mount Balrior",
        "vale_guardian": "Vale Guardian", "gorseval": "Gorseval", "sabetha": "Sabetha",
        "slothasor": "Slothasor", "bandit_trio": "Bandit Trio", "matthias": "Matthias",
        "keep_construct": "Keep Construct", "twisted_castle": "Twisted Castle", "xera": "Xera",
        "soulless_horror": "Soulless Horror", "river_of_souls": "River of Souls", "statues_of_grenth": "Statues of Grenth",
        "voice_in_the_void": "Dhuum", "conjured_amalgamate": "Conjured Amalgamate", "twin_largos": "Twin Largos",
        "qadim": "Qadim", "adina": "Cardinal Adina", "sabir": "Cardinal Sabir", "qadim_the_peerless": "Qadim the Peerless",
        "greer": "Greer", "decima": "Decima", "ura": "Ura",
        "ascalonian_catacombs": "Ascalonian Catacombs", "caudecus_manor": "Caudecus's Manor",
        "twilight_arbor": "Twilight Arbor", "sorrows_embrace": "Sorrow's Embrace", "citadel_of_flame": "Citadel of Flame",
        "honor_of_the_waves": "Honor of the Waves", "crucible_of_eternity": "Crucible of Eternity", "ruined_city_of_arah": "The Ruined City of Arah"
    ]

    private static let dailyCraftItems = [
        "charged_quartz_crystal": 43_772, "spool_of_silk_weaving_thread": 46_740,
        "lump_of_mithrilium": 46_742, "glob_of_elder_spirit_residue": 46_744,
        "spool_of_thick_elonian_cord": 46_745
    ]

    private static let locations: [String: Location] = [
        "worldBoss:shadow_behemoth": Location(mapID: 15, name: "Queensdale"),
        "worldBoss:tequatl_the_sunless": Location(mapID: 53, name: "Sparkfly Fen"),
        "worldBoss:the_shatterer": Location(mapID: 32, name: "Blazeridge Steppes"),
        "mapChest:verdant_brink_heros_choice_chest": Location(mapID: 1052, name: "Verdant Brink"),
        "mapChest:auric_basin_heros_choice_chest": Location(mapID: 1175, name: "Auric Basin"),
        "mapChest:tangled_depths_heros_choice_chest": Location(mapID: 1043, name: "Tangled Depths"),
        "mapChest:dragons_stand_heros_choice_chest": Location(mapID: 1195, name: "Dragon's Stand")
    ]

    static func displayName(for type: OpportunityType, id: String) -> String {
        if let name = names[id] { return name }
        if type == .mapChest {
            return title(id.replacingOccurrences(of: "_heros_choice_chest", with: ""))
        }
        return title(id)
    }

    static func title(_ identifier: String) -> String {
        if let name = names[identifier] { return name }
        return identifier.split(separator: "_").map { word in
            let lower = word.lowercased()
            return ["of", "the", "and", "or"].contains(lower) ? lower : lower.capitalized
        }.joined(separator: " ")
    }

    static func dungeonPathTitle(_ id: String, type: String) -> String {
        let name = title(id)
        return type.lowercased() == "story" ? "Story: \(name)" : name
    }

    static func relatedItemIDs(for type: OpportunityType, id: String) -> [Int] {
        guard type == .dailyCrafting, let itemID = dailyCraftItems[id] else { return [] }
        return [itemID]
    }

    static func location(for type: OpportunityType, id: String) -> Location? {
        locations["\(type.rawValue):\(id)"]
    }
}
