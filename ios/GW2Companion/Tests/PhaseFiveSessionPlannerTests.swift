import XCTest
@testable import GW2Companion

final class PhaseFiveCatalogTests: XCTestCase {
    func testBundledCatalogDecodesAndValidates() async throws {
        let catalog = try await BundledCatalogProvider(bundle: .main).catalog()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertTrue(AcquisitionCatalogValidator.validate(catalog).isEmpty)
        XCTAssertGreaterThanOrEqual(catalog.methods.filter { $0.type == .gathering }.count, 5)
        XCTAssertTrue(catalog.methods.contains { $0.type == .vendor })
        XCTAssertTrue(catalog.methods.contains { $0.type == .mysticForge })
        XCTAssertTrue(catalog.methods.allSatisfy { $0.source.type != .companionCurated || $0.source.reviewedAt != nil })
    }

    func testCatalogRejectsDuplicateIDsInvalidQuantitiesLocationsAndCycles() {
        let source = KnowledgeSource(
            type: .companionCurated, sourceID: nil, sourceURL: nil,
            reviewedAt: Date(), notes: nil)
        let location = AcquisitionLocation(
            mapID: nil, continentX: 1, continentY: 2, objectiveID: nil,
            label: nil, locationPrecision: .exactCoordinate)
        let method = AcquisitionMethod(
            id: "duplicate", target: .item(id: -1, quantity: -2), type: .vendor,
            title: "Invalid", description: nil,
            requirements: [AcquisitionRequirement(
                kind: .acquisition, numericID: nil, quantity: nil, value: "duplicate", rating: nil)],
            location: location,
            cost: AcquisitionCost(
                coinCopper: -1, currencies: [CurrencyCost(currencyID: -1, quantity: 0)], items: []),
            source: source, confidence: .unknown, coverage: .exampleOnly,
            gatheringCategory: nil, markerSubtype: nil)
        let catalog = AcquisitionCatalog(
            schemaVersion: 1, catalogVersion: "1", lastReviewedAt: Date(),
            coverage: .exampleOnly, methods: [method, method])
        let issues = AcquisitionCatalogValidator.validate(catalog)
        XCTAssertTrue(issues.contains(.duplicateMethodID("duplicate")))
        XCTAssertTrue(issues.contains(.invalidTarget("duplicate")))
        XCTAssertTrue(issues.contains(.invalidRequirement(methodID: "duplicate")) == false)
        XCTAssertTrue(issues.contains(.invalidCost(methodID: "duplicate")))
        XCTAssertTrue(issues.contains(.invalidLocation(methodID: "duplicate")))
        XCTAssertTrue(issues.contains(.missingProvenance(methodID: "duplicate")))
        XCTAssertTrue(issues.contains(.directCycle(methodID: "duplicate")))
    }

    func testMixedVendorCostAndIncompleteLocationRoundTrip() throws {
        let value = AcquisitionMethod(
            id: "mixed", target: .custom("test"), type: .vendor, title: "Mixed",
            description: nil, requirements: [],
            location: AcquisitionLocation(
                mapID: 15, continentX: nil, continentY: nil, objectiveID: nil,
                label: "Queensdale", locationPrecision: .mapOnly),
            cost: AcquisitionCost(
                coinCopper: 30_000, currencies: [CurrencyCost(currencyID: 23, quantity: 250)],
                items: [ItemCost(itemID: 19_700, quantity: 1)]),
            source: KnowledgeSource(
                type: .userDeclared, sourceID: nil, sourceURL: nil, reviewedAt: Date(), notes: nil),
            confidence: .userProvided, coverage: .exampleOnly,
            gatheringCategory: nil, markerSubtype: nil)
        let decoded = try JSONDecoder().decode(AcquisitionMethod.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.cost?.currencies.first?.quantity, 250)
        XCTAssertTrue(AcquisitionCatalogValidator.validate(AcquisitionCatalog(
            schemaVersion: 1, catalogVersion: "test", lastReviewedAt: Date(),
            coverage: .exampleOnly, methods: [value]), knownMapIDs: [15]).isEmpty)
    }

    func testUserMethodWinsStableIDWithoutBundledDataBeingMutated() async throws {
        let bundled = method(id: "same", type: .gathering, title: "Bundled")
        let user = AcquisitionMethod(
            id: "same", target: .item(id: 19_700), type: .manual, title: "Mine my route",
            description: nil, requirements: [], location: nil, cost: nil,
            source: KnowledgeSource(
                type: .userDeclared, sourceID: nil, sourceURL: nil, reviewedAt: Date(), notes: nil),
            confidence: .userProvided, coverage: .exampleOnly,
            gatheringCategory: nil, markerSubtype: nil)
        let store = AcquisitionKnowledgeStore()
        try await store.load(provider: FixtureCatalogProvider(methods: [bundled]))
        await store.replaceUserDeclared(with: [user])
        let values = await store.methods(for: .item(id: 19_700))
        XCTAssertEqual(values, [user])
    }

    private func method(id: String, type: AcquisitionMethodType, title: String) -> AcquisitionMethod {
        AcquisitionMethod(
            id: id, target: .item(id: 19_700), type: type, title: title,
            description: nil, requirements: [], location: nil, cost: nil,
            source: KnowledgeSource(
                type: .companionCurated, sourceID: "fixture", sourceURL: nil,
                reviewedAt: Date(), notes: nil),
            confidence: .strong, coverage: .partial,
            gatheringCategory: type == .gathering ? .ore : nil, markerSubtype: "Mithril")
    }
}

private struct FixtureCatalogProvider: AcquisitionCatalogProvider {
    let methods: [AcquisitionMethod]
    func catalog() async throws -> AcquisitionCatalog {
        AcquisitionCatalog(
            schemaVersion: 1, catalogVersion: "fixture", lastReviewedAt: Date(),
            coverage: .exampleOnly, methods: methods)
    }
}

final class PhaseFivePlannerTests: XCTestCase {
    private let goalA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let goalB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testScenarioAConsolidatesMithrilAcrossGoalsAndAllocatesHoldingsOnce() throws {
        let plan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "Sunrise", required: 20), goal(goalB, title: "Armor", required: 30)],
            holdings: [19_700: 10], methods: [method(.gathering)],
            preferences: PlanningPreferences(global: [.gathering: .prefer]),
            currentMapID: 15, player: .init(x: 105, y: 100), objectives: [mithrilNode]))
        let task = try XCTUnwrap(plan.tasks.first)
        XCTAssertEqual(task.type, .gather)
        XCTAssertEqual(task.quantity, 40)
        XCTAssertEqual(task.relatedGoalIDs.count, 2)
        XCTAssertEqual(task.mapObjectiveIDs, [mithrilNode.id])
        XCTAssertNotNil(task.scoreBreakdown.contributions.first { $0.factor == "multiGoalBenefit" })
        XCTAssertNotNil(task.scoreBreakdown.contributions.first { $0.factor == "sameCurrentMap" })
        XCTAssertNotNil(task.scoreBreakdown.contributions.first { $0.factor == "acquisitionPreference" })
    }

    func testScenarioBTradingPostPreferenceRanksBuyAboveGather() throws {
        let plan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "Sunrise", required: 20)], holdings: [:],
            methods: [method(.gathering), method(.tradingPost)],
            preferences: PlanningPreferences(global: [.tradingPost: .prefer]),
            currentMapID: 15, player: .init(x: 105, y: 100), objectives: [mithrilNode]))
        XCTAssertEqual(plan.tasks.first?.type, .buy)
    }

    func testScenarioCCraftableReadyComponentScoresReadiness() throws {
        let requirement = PlanningRequirement(
            id: "component", target: .item(id: 19_700), requiredQuantity: 1,
            name: "Component", provenance: [.arenaNetPublic], craftReady: true)
        let plan = SessionPlanner.plan(context: context(
            goals: [PlanningGoal(
                id: goalA, title: "Ready craft", priority: .normal,
                requirements: [requirement], linkedObjectives: [], fallbackReason: nil)],
            holdings: [:], methods: [method(.craft)], preferences: PlanningPreferences(),
            currentMapID: nil, player: nil, objectives: []))
        XCTAssertEqual(plan.tasks.first?.type, .craft)
        XCTAssertEqual(plan.tasks.first?.scoreBreakdown.contributions.first {
            $0.factor == "requirementsReadiness"
        }?.value, SessionScoring.craftReady)
    }

    func testScenarioDNearbyHighPriorityAchievementObjectiveRanksStrongly() throws {
        let objective = MapObjective(
            id: .init("hero:1"), mapId: 15, name: "Hero Challenge", type: .heroChallenge,
            continentX: 100, continentY: 100, source: .arenaNet, chatLink: nil,
            level: nil, description: nil, state: .unknown)
        let linked = PlanningGoal(
            id: goalA, title: "Mastery", priority: .high,
            requirements: [], linkedObjectives: [objective], fallbackReason: nil)
        let plan = SessionPlanner.plan(context: context(
            goals: [linked], holdings: [:], methods: [], preferences: PlanningPreferences(),
            currentMapID: 15, player: .init(x: 110, y: 100), objectives: [objective]))
        let task = try XCTUnwrap(plan.tasks.first)
        XCTAssertEqual(task.type, .navigate)
        XCTAssertEqual(Set(task.scoreBreakdown.contributions.map(\.factor)), ["goalPriority", "sameCurrentMap", "nearbyDistance"])
    }

    func testScenarioENoTelemetryStillProducesExplainablePlan() throws {
        let plan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "Offline", required: 2)], holdings: [:],
            methods: [method(.gathering)], preferences: PlanningPreferences(),
            currentMapID: nil, player: nil, objectives: []))
        let task = try XCTUnwrap(plan.tasks.first)
        XCTAssertFalse(task.reason.isEmpty)
        XCTAssertNil(task.scoreBreakdown.contributions.first { $0.factor == "nearbyDistance" })
    }

    func testScenarioFUnknownAcquisitionUsesHonestManualFallback() throws {
        let plan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "Unknown", required: 2)], holdings: [:], methods: [],
            preferences: PlanningPreferences(), currentMapID: nil, player: nil, objectives: []))
        XCTAssertEqual(plan.tasks.first?.type, .manual)
        XCTAssertTrue(plan.tasks.first?.reason.contains("No known acquisition method") == true)
    }

    func testPreferencePrecedenceRequirementThenGoalThenGlobal() throws {
        let requirement = goal(goalA, title: "Override", required: 2).requirements[0]
        var preferences = PlanningPreferences(global: [.gathering: .prefer])
        preferences.goalOverrides[PlanningPreferences.goalKey(goalID: goalA, targetKey: requirement.target.key)] = .tradingPost
        preferences.requirementOverrides[PlanningPreferences.requirementKey(goalID: goalA, requirementID: requirement.id)] = .craft
        let plan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "Override", required: 2)], holdings: [:],
            methods: [method(.gathering), method(.tradingPost), method(.craft)], preferences: preferences,
            currentMapID: nil, player: nil, objectives: []))
        XCTAssertEqual(plan.tasks.first?.type, .craft)
        XCTAssertEqual(plan.tasks.first?.scoreBreakdown.contributions.first { $0.factor == "acquisitionOverride" }?.value, 80)
    }

    func testDynamicReplanPreservesCompletedSkippedAndLockedTasks() throws {
        let originalPlan = SessionPlanner.plan(context: context(
            goals: [goal(goalA, title: "A", required: 20)], holdings: [:],
            methods: [method(.gathering), method(.tradingPost)], preferences: PlanningPreferences(),
            currentMapID: nil, player: nil, objectives: []))
        var tasks = originalPlan.tasks
        tasks[0].state = .completed
        tasks[1].state = .skipped
        tasks[1].isLocked = true
        let snapshot = SessionAccountSnapshot(timestamp: Date(), relevantHoldings: [:], relevantCurrencies: [:])
        let active = ActiveSession(
            id: UUID(), createdAt: Date(), endedAt: nil, planningHorizon: .minutes45,
            initialMapID: nil, initialPlayerPosition: nil, initialAccountSnapshot: snapshot,
            latestAccountSnapshot: snapshot, tasks: tasks)
        let replanned = SessionPlanner.replan(active, context: context(
            goals: [goal(goalA, title: "A", required: 20)], holdings: [19_700: 20],
            methods: [method(.gathering), method(.tradingPost)], preferences: PlanningPreferences(),
            currentMapID: nil, player: nil, objectives: []))
        XCTAssertTrue(replanned.tasks.contains { $0.state == .completed })
        XCTAssertTrue(replanned.tasks.contains { $0.state == .skipped && $0.isLocked })
        XCTAssertEqual(replanned.tasks.filter { $0.state == .skipped }.count, 1)
        XCTAssertFalse(replanned.tasks.contains { $0.state == .pending })
    }

    func testAccountDiffReportsChangesWithoutCauseInference() {
        let before = SessionAccountSnapshot(
            timestamp: Date(), relevantHoldings: [19_700: 100, 19_768: 10], relevantCurrencies: [:])
        let after = SessionAccountSnapshot(
            timestamp: Date(), relevantHoldings: [19_700: 137, 19_768: 8], relevantCurrencies: [:])
        let changes = SessionAccountDiff.changes(from: before, to: after)
        XCTAssertEqual(changes.first { $0.numericID == 19_700 }?.delta, 37)
        XCTAssertEqual(changes.first { $0.numericID == 19_768 }?.delta, -2)
    }

    private func goal(_ id: UUID, title: String, required: Int) -> PlanningGoal {
        PlanningGoal(
            id: id, title: title, priority: .high,
            requirements: [PlanningRequirement(
                id: "mithril", target: .item(id: 19_700, quantity: required),
                requiredQuantity: required, name: "Mithril Ore",
                provenance: [.arenaNetPublic, .arenaNetAccount], craftReady: false)],
            linkedObjectives: [], fallbackReason: nil)
    }

    private func method(_ type: AcquisitionMethodType) -> AcquisitionMethod {
        AcquisitionMethod(
            id: "test:\(type.rawValue)", target: .item(id: 19_700), type: type,
            title: type.title, description: "Fixture method.", requirements: [], location: nil,
            cost: nil,
            source: KnowledgeSource(
                type: type == .tradingPost || type == .craft ? .arenaNetAPI : .companionCurated,
                sourceID: "fixture", sourceURL: nil, reviewedAt: Date(), notes: nil),
            confidence: .strong, coverage: .partial,
            gatheringCategory: type == .gathering ? .ore : nil,
            markerSubtype: type == .gathering ? "Mithril" : nil)
    }

    private var mithrilNode: MapObjective {
        MapObjective(
            id: .init("gathering:mithril"), mapId: 15, name: "Rich Mithril Vein",
            type: .gatheringOre, continentX: 100, continentY: 100,
            source: .bundledGathering, chatLink: nil, level: nil,
            description: nil, state: .unknown)
    }

    private func context(
        goals: [PlanningGoal], holdings: [Int: Int], methods: [AcquisitionMethod],
        preferences: PlanningPreferences, currentMapID: Int?, player: ContinentPoint?,
        objectives: [MapObjective]
    ) -> SessionPlanningContext {
        SessionPlanningContext(
            goals: goals, holdings: holdings, currencies: [:], acquisitionMethods: methods,
            preferences: preferences, parameters: SessionParameters(
                duration: .openEnded, selectedGoalIDs: nil, stayNearCurrentMap: false,
                enabledMethods: Set(AcquisitionMethodType.allCases)),
            currentMapID: currentMapID, playerPosition: player, mapObjectives: objectives)
    }
}
