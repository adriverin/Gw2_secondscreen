import XCTest
@testable import GW2Companion

final class PhaseSixTodayMergeTests: XCTestCase {
    func testVaultCompletionAndClaimSemanticsStayDistinct() throws {
        let data = merged()
        let zero = try XCTUnwrap(data.opportunities.first { $0.sourceIdentifier == "1" })
        let partial = try XCTUnwrap(data.opportunities.first { $0.sourceIdentifier == "2" })
        let unclaimed = try XCTUnwrap(data.opportunities.first { $0.sourceIdentifier == "3" })
        let claimed = try XCTUnwrap(data.opportunities.first { $0.sourceIdentifier == "4" })
        XCTAssertEqual(zero.state, .incomplete)
        XCTAssertEqual(partial.progress, OpportunityProgress(current: 4, complete: 10))
        XCTAssertEqual(unclaimed.state, .completeUnclaimed)
        XCTAssertEqual(claimed.state, .completeClaimed)
        XCTAssertEqual(data.dailyMeta?.state, .incomplete)

        let completeUnclaimed = period(metaCurrent: 4, metaClaimed: false)
        let completeClaimed = period(metaCurrent: 4, metaClaimed: true)
        XCTAssertEqual(merge(daily: completeUnclaimed).dailyMeta?.state, .completeUnclaimed)
        XCTAssertEqual(merge(daily: completeClaimed).dailyMeta?.state, .completeClaimed)
    }

    func testChecklistMergesUseAuthoritativeAccountEvidenceAndPreserveUnknownIDs() throws {
        let data = merged()
        XCTAssertEqual(data.opportunities.first { $0.id == OpportunityID("worldBoss:tequatl_the_sunless") }?.state, .completed)
        XCTAssertEqual(data.opportunities.first { $0.id == OpportunityID("worldBoss:shadow_behemoth") }?.state, .incomplete)
        let unknown = try XCTUnwrap(data.opportunities.first { $0.sourceIdentifier == "future_boss" })
        XCTAssertEqual(unknown.state, .completed)
        XCTAssertTrue(unknown.title.contains("Unknown"))
        XCTAssertTrue(data.diagnostics.unknownIDs.contains("worldBoss:future_boss"))
        XCTAssertEqual(data.opportunities.first { $0.sourceIdentifier == "lump_of_mithrilium" }?.relatedItemIDs, [46_742])
    }

    func testRaidCheckpointIsNotCountedAsBossAndDungeonPathsMerge() throws {
        let data = merged()
        let raids = data.opportunities.filter { $0.type == .raidEncounter }
        XCTAssertEqual(raids.count, 4)
        XCTAssertFalse(raids.contains { $0.sourceIdentifier == "spirit_woods" })
        XCTAssertTrue(data.diagnostics.unknownIDs.contains("raid-event-type:FutureType:future_event"))
        XCTAssertEqual(data.opportunities.first { $0.sourceIdentifier == "vale_guardian" }?.state, .completed)
        XCTAssertEqual(data.opportunities.first { $0.sourceIdentifier == "sabetha" }?.state, .incomplete)
        XCTAssertEqual(data.opportunities.first { $0.sourceIdentifier == "hodgins" }?.state, .completed)
    }

    func testUnknownVaultListingTypeDecodesWithoutLosingCatalog() throws {
        let values: [WizardVaultAccountListing] = try fixture("wizards-vault-listings-phase6")
        XCTAssertEqual(values.count, 4)
        guard case .unknown("FutureType") = values[3].type else { return XCTFail("Unknown type was not preserved") }
        let rewards = merged().vaultRewards
        XCTAssertEqual(rewards.count, 4)
        XCTAssertTrue(merged().diagnostics.unknownIDs.contains("vault-listing-type:FutureType:4"))
        XCTAssertNil(rewards.first { $0.id == 2 }?.purchaseLimit)
        XCTAssertTrue(rewards.first { $0.id == 3 }?.isLimitReached == true)
    }

    func testNewDailyResponseReplacesOldDailySet() throws {
        let original = merged()
        var changed = period(metaCurrent: 0, metaClaimed: false)
        changed = WizardVaultAccountPeriod(
            metaProgressCurrent: changed.metaProgressCurrent, metaProgressComplete: changed.metaProgressComplete,
            metaRewardItemID: changed.metaRewardItemID, metaRewardAstral: changed.metaRewardAstral,
            metaRewardClaimed: changed.metaRewardClaimed,
            objectives: [WizardVaultAccountObjective(
                id: 999, title: "New Daily", track: "PvE", acclaim: 10,
                progressCurrent: 0, progressComplete: 1, claimed: false)])
        let replacement = merge(daily: changed)
        XCTAssertTrue(original.opportunities.contains { $0.id == OpportunityID("wizardVaultDaily:1") })
        XCTAssertFalse(replacement.opportunities.contains { $0.id == OpportunityID("wizardVaultDaily:1") })
        XCTAssertTrue(replacement.opportunities.contains { $0.id == OpportunityID("wizardVaultDaily:999") })
    }

    func testSessionProgressDiffIsFactualBeforeAndAfter() {
        let before = TodayProgressSnapshot(data: merge(
            daily: try! fixture("wizards-vault-daily-phase6"),
            worldBosses: ["tequatl_the_sunless"]))
        let changed = merge(
            daily: period(metaCurrent: 4, metaClaimed: false),
            worldBosses: ["tequatl_the_sunless", "shadow_behemoth"],
            dailyCrafting: ["spool_of_silk_weaving_thread", "lump_of_mithrilium"])
        let diff = TodayProgressDiff.changes(from: before, to: TodayProgressSnapshot(data: changed))
        XCTAssertEqual(diff.first { $0.label == "World Bosses" }?.after, 2)
        XCTAssertEqual(diff.first { $0.label == "Daily Crafting" }?.after, 2)
    }

    private func merged() -> TodayDataSnapshot { merge(daily: try! fixture("wizards-vault-daily-phase6")) }

    private func merge(
        daily: WizardVaultAccountPeriod,
        worldBosses: [String] = ["tequatl_the_sunless", "future_boss"],
        dailyCrafting: [String] = ["spool_of_silk_weaving_thread"]
    ) -> TodayDataSnapshot {
        let checklists: ChecklistFixture = try! fixture("account-checklists-phase6")
        let listings: [WizardVaultAccountListing] = try! fixture("wizards-vault-listings-phase6")
        let account = TodayAccountPayload(
            daily: daily, weekly: try! fixture("wizards-vault-weekly-phase6"),
            special: try! fixture("wizards-vault-special-phase6"), listings: listings,
            worldBossIDs: worldBosses, mapChestIDs: checklists.mapchestsCompleted,
            dailyCraftingIDs: dailyCrafting, raidEventIDs: ["vale_guardian", "gorseval"],
            dungeonPathIDs: ["hodgins", "seraph"], wallet: [WalletEntry(id: 63, value: 125)],
            rewardItems: [:])
        return TodayMerger.merge(
            public: publicCatalog(checklists: checklists, listings: listings), account: account,
            accountID: "fixture", hasProgressionPermission: true,
            now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func publicCatalog(
        checklists: ChecklistFixture, listings: [WizardVaultAccountListing]
    ) -> TodayPublicCatalog {
        TodayPublicCatalog(
            season: WizardVaultSeason(
                title: "Fixture Season", start: "2026-01-01T00:00:00Z", end: "2026-04-01T00:00:00Z",
                listings: listings.map(\.id), objectives: [1, 2, 3, 4]),
            vaultObjectives: [],
            vaultListings: listings.map { WizardVaultListingMetadata(
                id: $0.id, itemID: $0.itemID, itemCount: $0.itemCount, type: $0.type, cost: $0.cost) },
            worldBossIDs: checklists.worldbossesPublic, mapChestIDs: checklists.mapchestsPublic,
            dailyCraftingIDs: checklists.dailycraftingPublic, raids: try! fixture("raids-phase6"),
            dungeons: try! fixture("dungeons-phase6"),
            items: [
                46_742: ItemMetadata(id: 46_742, name: "Lump of Mithrillium", icon: nil, rarity: "Ascended"),
                43_772: ItemMetadata(id: 43_772, name: "Charged Quartz Crystal", icon: nil, rarity: "Rare"),
                46_744: ItemMetadata(id: 46_744, name: "Glob of Elder Spirit Residue", icon: nil, rarity: "Ascended"),
                46_745: ItemMetadata(id: 46_745, name: "Spool of Thick Elonian Cord", icon: nil, rarity: "Ascended")
            ],
            astralAcclaimCurrency: CurrencyMetadata(
                id: 63, name: "Astral Acclaim", description: "Fixture", icon: nil, order: 1))
    }

    private func period(metaCurrent: Int, metaClaimed: Bool) -> WizardVaultAccountPeriod {
        WizardVaultAccountPeriod(
            metaProgressCurrent: metaCurrent, metaProgressComplete: 4, metaRewardItemID: 99961,
            metaRewardAstral: 20, metaRewardClaimed: metaClaimed, objectives: [])
    }
}

final class PhaseSixPlannerTests: XCTestCase {
    func testDailyCraftGoalCrossBenefitConsolidatesAndRanksStrongly() throws {
        let opportunity = dailyCraftOpportunity()
        let goalID = UUID()
        let requirement = PlanningRequirement(
            id: "mithrillium", target: .item(id: 46_742), requiredQuantity: 1,
            name: "Lump of Mithrillium", provenance: [.arenaNetPublic], craftReady: true)
        let goal = PlanningGoal(
            id: goalID, title: "Sunrise", priority: .high, requirements: [requirement],
            linkedObjectives: [], fallbackReason: nil)
        let plan = SessionPlanner.plan(context: context(
            goals: [goal], opportunities: [opportunity], methods: [craftMethod]))
        let task = try XCTUnwrap(plan.tasks.first)
        XCTAssertEqual(task.title, "Craft Lump of Mithrillium")
        XCTAssertEqual(task.relatedGoalIDs, [goalID])
        XCTAssertEqual(task.relatedOpportunityIDs, [opportunity.id])
        XCTAssertNotNil(task.scoreBreakdown.contributions.first { $0.factor == "goalOpportunityCrossBenefit" })
        XCTAssertEqual(task.scoreBreakdown.contributions.first { $0.factor == "opportunityUrgency" }?.value, 40)
    }

    func testDailyHasDocumentedUrgencyAdvantageOverWeekly() throws {
        let daily = opportunity(id: "daily", type: .worldBoss, scope: .daily)
        let weekly = opportunity(id: "weekly", type: .raidEncounter, scope: .weekly)
        let plan = SessionPlanner.plan(context: context(goals: [], opportunities: [weekly, daily], methods: []))
        let dailyTask = try XCTUnwrap(plan.tasks.first { $0.relatedOpportunityIDs == [daily.id] })
        let weeklyTask = try XCTUnwrap(plan.tasks.first { $0.relatedOpportunityIDs == [weekly.id] })
        XCTAssertEqual(dailyTask.scoreBreakdown.contributions.first { $0.factor == "opportunityUrgency" }?.value, 40)
        XCTAssertEqual(weeklyTask.scoreBreakdown.contributions.first { $0.factor == "opportunityUrgency" }?.value, 20)
        XCTAssertGreaterThan(dailyTask.scoreBreakdown.total, weeklyTask.scoreBreakdown.total)
    }

    func testReadyToClaimCreatesInformationalInGameTask() throws {
        var value = opportunity(id: "claim", type: .wizardVaultDaily, scope: .daily)
        value = AccountOpportunity(
            id: value.id, type: value.type, resetScope: value.resetScope, urgency: value.urgency,
            title: value.title, subtitle: value.subtitle,
            progress: OpportunityProgress(current: 3, complete: 3), reward: value.reward,
            state: .completeUnclaimed, activity: value.activity, relatedItemIDs: [],
            relatedAchievementIDs: [], mapID: nil, mapName: nil,
            sourceIdentifier: value.sourceIdentifier, provenance: [.arenaNetAccount])
        let task = try XCTUnwrap(SessionPlanner.plan(context: context(
            goals: [], opportunities: [value], methods: [])).tasks.first)
        XCTAssertTrue(task.title.contains("in game"))
        XCTAssertEqual(task.type, .daily)
        XCTAssertTrue(task.provenance.contains(.arenaNetAccount))
        XCTAssertEqual(task.scoreBreakdown.contributions.first { $0.factor == "readyToClaim" }?.value, 70)
    }

    private func context(
        goals: [PlanningGoal], opportunities: [AccountOpportunity], methods: [AcquisitionMethod]
    ) -> SessionPlanningContext {
        SessionPlanningContext(
            goals: goals, holdings: [:], currencies: [:], acquisitionMethods: methods,
            preferences: PlanningPreferences(activities: [.dailyCrafting: .prefer]),
            parameters: SessionParameters(duration: .openEnded, selectedGoalIDs: nil, stayNearCurrentMap: false),
            currentMapID: nil, playerPosition: nil, mapObjectives: [], opportunities: opportunities)
    }

    private var craftMethod: AcquisitionMethod {
        AcquisitionMethod(
            id: "fixture:mithrillium", target: .item(id: 46_742), type: .craft,
            title: "Craft Lump of Mithrillium", description: nil, requirements: [], location: nil, cost: nil,
            source: KnowledgeSource(
                type: .arenaNetAPI, sourceID: "fixture", sourceURL: nil, reviewedAt: Date(), notes: nil),
            confidence: .strong, coverage: .partial, gatheringCategory: nil, markerSubtype: nil)
    }

    private func dailyCraftOpportunity() -> AccountOpportunity {
        AccountOpportunity(
            id: OpportunityID("dailyCrafting:lump_of_mithrilium"), type: .dailyCrafting,
            resetScope: .daily, urgency: .daily, title: "Lump of Mithrillium", subtitle: nil,
            progress: nil, reward: nil, state: .incomplete, activity: .crafting,
            relatedItemIDs: [46_742], relatedAchievementIDs: [], mapID: nil, mapName: nil,
            sourceIdentifier: "lump_of_mithrilium", provenance: [.arenaNetPublic, .arenaNetAccount])
    }

    private func opportunity(
        id: String, type: OpportunityType, scope: OpportunityResetScope
    ) -> AccountOpportunity {
        AccountOpportunity(
            id: OpportunityID("\(type.rawValue):\(id)"), type: type, resetScope: scope,
            urgency: scope == .daily ? .daily : .weekly, title: id.capitalized, subtitle: nil,
            progress: nil, reward: nil, state: .incomplete, activity: .pve,
            relatedItemIDs: [], relatedAchievementIDs: [], mapID: nil, mapName: nil,
            sourceIdentifier: id, provenance: [.arenaNetPublic, .arenaNetAccount])
    }
}

final class PhaseSixOfflineTests: XCTestCase {
    @MainActor
    func testCachedTodayRemainsVisibleWhenRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = MetadataDiskCache(directory: directory)
        let cached = TodayDataSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), accountID: "fixture", season: nil,
            opportunities: [AccountOpportunity(
                id: OpportunityID("worldBoss:tequatl_the_sunless"), type: .worldBoss,
                resetScope: .daily, urgency: .daily, title: "Tequatl the Sunless", subtitle: nil,
                progress: nil, reward: nil, state: .completed, activity: .pve,
                relatedItemIDs: [], relatedAchievementIDs: [], mapID: 53, mapName: "Sparkfly Fen",
                sourceIdentifier: "tequatl_the_sunless", provenance: [.arenaNetPublic, .arenaNetAccount])],
            dailyMeta: nil, weeklyMeta: nil, vaultRewards: [], astralAcclaimBalance: nil,
            hasProgressionPermission: true,
            diagnostics: TodayDiagnostics(
                dailyObjectiveCount: 0, weeklyObjectiveCount: 0, specialObjectiveCount: 0,
                claimableCount: 0, worldBossIDs: ["tequatl_the_sunless"], mapChestIDs: [],
                dailyCraftingIDs: [], raidEventIDs: [], dungeonPathIDs: [], unknownIDs: []))
        await cache.save(cached, named: "today-account-v1-fixture")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PhaseSixOffline-\(UUID().uuidString)"))
        let store = TodayStore(provider: OfflineTodayProvider(), cache: cache, defaults: defaults)
        await store.setAccountScope("fixture", permissions: PermissionSet(["account", "progression"]))
        XCTAssertEqual(store.snapshot?.opportunities.first?.title, "Tequatl the Sunless")
        XCTAssertTrue(store.isStale)
        XCTAssertEqual(store.loadState, .failed)
        XCTAssertNotNil(store.errorMessage)
    }
}

private struct ChecklistFixture: Decodable {
    let worldbossesPublic: [String]
    let worldbossesCompleted: [String]
    let mapchestsPublic: [String]
    let mapchestsCompleted: [String]
    let dailycraftingPublic: [String]
    let dailycraftingCompleted: [String]

    enum CodingKeys: String, CodingKey {
        case worldbossesPublic = "worldbosses_public"
        case worldbossesCompleted = "worldbosses_completed"
        case mapchestsPublic = "mapchests_public"
        case mapchestsCompleted = "mapchests_completed"
        case dailycraftingPublic = "dailycrafting_public"
        case dailycraftingCompleted = "dailycrafting_completed"
    }
}

private func fixture<T: Decodable>(_ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle(for: PhaseSixTodayMergeTests.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private struct OfflineTodayProvider: TodayDataProvider {
    private func offline<T>() throws -> T { throw URLError(.notConnectedToInternet) }
    func wizardVaultSeason(language: String) async throws -> WizardVaultSeason { try offline() }
    func wizardVaultObjectives(ids: [Int], language: String) async throws -> [WizardVaultObjectiveMetadata] { try offline() }
    func wizardVaultListings(ids: [Int], language: String) async throws -> [WizardVaultListingMetadata] { try offline() }
    func worldBossIDs() async throws -> [String] { try offline() }
    func mapChestIDs() async throws -> [String] { try offline() }
    func dailyCraftingIDs() async throws -> [String] { try offline() }
    func raids(language: String) async throws -> [RaidDefinition] { try offline() }
    func dungeons(language: String) async throws -> [DungeonDefinition] { try offline() }
    func wizardVaultDaily() async throws -> WizardVaultAccountPeriod { try offline() }
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod { try offline() }
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial { try offline() }
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing] { try offline() }
    func accountWorldBossIDs() async throws -> [String] { try offline() }
    func accountMapChestIDs() async throws -> [String] { try offline() }
    func accountDailyCraftingIDs() async throws -> [String] { try offline() }
    func accountRaidEventIDs() async throws -> [String] { try offline() }
    func accountDungeonPathIDs() async throws -> [String] { try offline() }
    func todayItems(ids: [Int]) async throws -> [Int: ItemMetadata] { try offline() }
    func todayCurrencies(ids: [Int]) async throws -> [Int: CurrencyMetadata] { try offline() }
    func todayWallet() async throws -> [WalletEntry] { try offline() }
}
