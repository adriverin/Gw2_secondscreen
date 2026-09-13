import XCTest
@testable import GW2Companion

final class PhaseFourAchievementTests: XCTestCase {
    func testAchievementDefinitionsDecodeAllKnownBitTypes() throws {
        let values = try fixture([AchievementDefinition].self, "achievements-phase4")
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(values[2].bits, [.text("Visit the ancient ruins"), .text("Open the chest")])
        XCTAssertEqual(values[3].bits, [.item(19_697)])
        XCTAssertEqual(values[4].bits, [.skin(101)])
        XCTAssertEqual(values[5].bits, [.minipet(202)])
    }

    func testAccountProgressMergeIsAuthoritativeAndSupportsRepeatedProgress() throws {
        let definitions = try fixture([AchievementDefinition].self, "achievements-phase4")
        let progress = try fixture([AccountAchievementProgress].self, "account-achievements-phase4")
        let complete = AchievementTrackingEngine.merge(
            definition: definitions[0], progress: progress[0], progressPermissionAvailable: true)
        XCTAssertEqual(complete.isComplete, true)
        XCTAssertTrue(complete.goalProgress.isAuthoritativeCompletion)
        XCTAssertEqual(progress[1].repeated, 2)

        let bits = AchievementTrackingEngine.merge(
            definition: definitions[2], progress: progress[2], progressPermissionAvailable: true)
        XCTAssertEqual(bits.bits.map(\.isComplete), [true, false])
    }

    func testMissingProgressPermissionNeverInfersCompletionFromTextOrUnlocks() throws {
        let definition = try fixture([AchievementDefinition].self, "achievements-phase4")[2]
        let state = AchievementTrackingEngine.merge(
            definition: definition, progress: nil, progressPermissionAvailable: false)
        XCTAssertNil(state.isComplete)
        XCTAssertTrue(state.bits.allSatisfy { $0.isComplete == nil })
        XCTAssertEqual(state.goalProgress.label, "Account progress unavailable")
    }

    func testSkinAndMiniOwnershipRequiresUnlockPermission() throws {
        let values = try fixture([AchievementDefinition].self, "achievements-phase4")
        let skin = AchievementTrackingEngine.merge(
            definition: values[4], progress: nil, progressPermissionAvailable: false,
            unlockedSkinIDs: [101], unlockPermissionAvailable: true)
        XCTAssertEqual(skin.bits.first?.ownershipHint, true)
        let mini = AchievementTrackingEngine.merge(
            definition: values[5], progress: nil, progressPermissionAvailable: false,
            unlockedMiniIDs: [202], unlockPermissionAvailable: false)
        XCTAssertNil(mini.bits.first?.ownershipHint)
    }
}

final class PhaseFourCraftingPlannerTests: XCTestCase {
    private var recipes: [Int: RecipeDefinition] {
        get throws {
            let values = try fixture([RecipeDefinition].self, "recipes-phase4")
            return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        }
    }

    func testLiveLegacyRecipeSchemaAndGuildIngredientsDecode() throws {
        let recipe = try fixture(RecipeDefinition.self, "recipe-live-legacy")
        XCTAssertEqual(recipe.outputItemID, 19_713)
        XCTAssertEqual(recipe.ingredients.first, RecipeIngredient(type: "Item", id: 19_726, count: 2))
        XCTAssertEqual(recipe.ingredients.last, RecipeIngredient(type: "GuildUpgrade", id: 88, count: 1))
        XCTAssertTrue(recipe.isAutomaticallyLearned)
    }

    func testSimpleRecipeAndIngredientQuantity() throws {
        let recipes = try recipes
        let plan = CraftingPlanner.build(
            targetItemID: 2000, quantity: 3, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [])
        XCTAssertEqual(plan.flattenedRequirements.first(where: { $0.requirement == .item(3000) })?.requiredQuantity, 6)
    }

    func testNestedRecipeAndOutputCountScaling() throws {
        let recipes = try recipes
        let nested = CraftingPlanner.build(
            targetItemID: 4000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [])
        XCTAssertEqual(nested.flattenedRequirements.first(where: { $0.requirement == .item(3000) })?.requiredQuantity, 4)

        let scaled = CraftingPlanner.build(
            targetItemID: 4100, quantity: 5, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [])
        XCTAssertEqual(scaled.flattenedRequirements.first?.requiredQuantity, 9)
    }

    func testDuplicateBranchesUseGlobalSupplyOnce() throws {
        let recipes = try recipes
        let holdings = [AccountHolding(
            itemID: 3000, totalQuantity: 18,
            locations: [HoldingLocation(location: .materialStorage, quantity: 18)])]
        let plan = CraftingPlanner.build(
            targetItemID: 5000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: holdings)
        let raw = try XCTUnwrap(plan.flattenedRequirements.first(where: { $0.requirement == .item(3000) }))
        XCTAssertEqual(raw.requiredQuantity, 30)
        XCTAssertEqual(raw.ownedQuantity, 18)
        XCTAssertEqual(raw.missingQuantity, 12)
    }

    func testMultipleRecipesDefaultDeterministicallyAndSelectionRecalculates() throws {
        let recipes = try recipes
        let index = RecipeOutputIndex(recipes: recipes)
        XCTAssertEqual(index.recipesProducing(itemID: 6000), [7, 8])
        let defaultPlan = CraftingPlanner.build(
            targetItemID: 6000, quantity: 3, recipes: recipes, index: index, holdings: [])
        XCTAssertEqual(defaultPlan.root.recipeID, 7)
        XCTAssertEqual(defaultPlan.flattenedRequirements.first?.requiredQuantity, 6)
        let selected = CraftingPlanner.build(
            targetItemID: 6000, quantity: 3, recipes: recipes, index: index,
            selectedRecipeIDs: [6000: 8], holdings: [])
        XCTAssertEqual(selected.root.recipeID, 8)
        XCTAssertEqual(selected.flattenedRequirements.first?.requirement, .item(3001))
        XCTAssertEqual(selected.flattenedRequirements.first?.requiredQuantity, 6)
    }

    func testCurrencyGuildUpgradeAndUnknownIngredientsAreDefensive() throws {
        let recipes = try recipes
        let plan = CraftingPlanner.build(
            targetItemID: 7000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [],
            wallet: [WalletEntry(id: 23, value: 3)])
        let currency = try XCTUnwrap(plan.flattenedRequirements.first { $0.requirement == .currency(23) })
        XCTAssertEqual(currency.ownedQuantity, 3)
        XCTAssertEqual(currency.missingQuantity, 2)
        XCTAssertTrue(plan.issues.contains(.guildUpgradeUnsupported(id: 88)))
        XCTAssertTrue(plan.issues.contains(.unknownIngredient(type: "FutureType", id: 99)))
    }

    func testCycleAndDepthProtectionTerminate() throws {
        let recipes = try recipes
        let cycle = CraftingPlanner.build(
            targetItemID: 8000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [])
        XCTAssertTrue(cycle.issues.contains(.cycle(itemID: 8000)))
        XCTAssertLessThan(cycle.nodeCount, 10)
        let depth = CraftingPlanner.build(
            targetItemID: 4000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [], maxDepth: 1)
        XCTAssertTrue(depth.issues.contains { if case .depthLimit = $0 { true } else { false } })
    }

    func testMissingRecipeRemainsInspectableAndOfflineSafe() throws {
        let plan = CraftingPlanner.build(
            targetItemID: 9999, quantity: 2, recipes: [:],
            index: RecipeOutputIndex(recipes: [:]), holdings: [])
        XCTAssertEqual(plan.flattenedRequirements.first?.missingQuantity, 2)
        XCTAssertTrue(plan.issues.contains(.missingRecipe(itemID: 9999)))
        XCTAssertNil(MarketCalculator.buyNow(price: nil, quantity: 2))
    }

    func testFinalItemOwnedDoesNotClaimCraftingCompletion() throws {
        let recipes = try recipes
        let plan = CraftingPlanner.build(
            targetItemID: 2000, quantity: 2, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes),
            holdings: [AccountHolding(itemID: 2000, totalQuantity: 2, locations: [.init(location: .bank, quantity: 2)])])
        XCTAssertTrue(plan.targetAlreadyOwned)
        XCTAssertFalse(plan.progress.isAuthoritativeCompletion)
        XCTAssertEqual(plan.progress.label, "Target already owned")
    }
}

final class PhaseFourMarketAndActionTests: XCTestCase {
    @MainActor
    func testGoalRouteHandsOffToExistingNavigatorWhenMapBecomesCurrent() throws {
        let suite = "PhaseFourRoute-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let objective = MapObjective(
            id: .init("user:goal"), mapId: 15, name: "Linked Ruins", type: .custom,
            continentX: 10, continentY: 20, source: .user, chatLink: nil,
            level: nil, description: nil, state: .unknown)
        let store = MapObjectiveStore(defaults: defaults)
        store.startGoalRoute(name: "Achievement", objectives: [objective])
        XCTAssertNil(store.currentTargetID)
        store.transition(to: 15)
        XCTAssertEqual(store.currentTargetID, objective.id)
        XCTAssertEqual(store.route?.name, "Achievement")
    }

    func testIntegerCopperBuyNowAndSellNowFormulas() throws {
        let price = try fixture([CommercePrice].self, "prices-phase4")[0]
        let timed = TimedCommercePrice(price: price, fetchedAt: Date())
        XCTAssertEqual(MarketCalculator.buyNow(price: timed, quantity: 19)?.copper, 2_850)
        XCTAssertEqual(MarketCalculator.sellNow(price: timed, quantity: 19)?.copper, 2_337)
    }

    func testNoBuyAndNoSellOrdersReturnNoEstimateAndStaleIsMarked() throws {
        let values = try fixture([CommercePrice].self, "prices-phase4")
        XCTAssertNil(MarketCalculator.sellNow(price: .init(price: values[1], fetchedAt: Date()), quantity: 1))
        XCTAssertNil(MarketCalculator.buyNow(price: .init(price: values[2], fetchedAt: Date()), quantity: 1))
        let stale = MarketCalculator.buyNow(
            price: .init(price: values[0], fetchedAt: Date(timeIntervalSinceNow: -601)), quantity: 1)
        XCTAssertEqual(stale?.stale, true)
        XCTAssertEqual(MarketCalculator.buyState(price: .init(price: values[2], fetchedAt: Date())), .noSellOrders)
        XCTAssertEqual(MarketCalculator.sellState(price: .init(price: values[1], fetchedAt: Date())), .noBuyOrders)
        let bound = ItemMetadata(id: 1, name: "Bound", icon: nil, rarity: "Basic", flags: ["AccountBound"])
        XCTAssertEqual(MarketCalculator.buyState(price: nil, item: bound), .nonTradable)
        XCTAssertEqual(MarketCalculator.buyState(price: nil), .noPriceRecord)
    }

    func testCurrentMapGatheringOutranksInspectUsingExplicitScore() {
        let targetRecipe = RecipeDefinition(
            id: 50, type: "Weapon", outputItemID: 9000, outputItemCount: 1,
            timeToCraftMS: nil, disciplines: [], minRating: 0, flags: [],
            ingredients: [.init(type: "Item", id: 19_700, count: 19)], chatLink: nil)
        let recipes = [50: targetRecipe]
        let plan = CraftingPlanner.build(
            targetItemID: 9000, quantity: 1, recipes: recipes,
            index: RecipeOutputIndex(recipes: recipes), holdings: [])
        let goal = PlayerGoal(title: "Test", type: .craftItem(itemID: 9000, quantity: 1), priority: .high)
        let node = MapObjective(
            id: .init("gathering:mithril"), mapId: 15, name: "Rich Mithril Vein",
            type: .gatheringOre, continentX: 100, continentY: 100,
            source: .bundledGathering, chatLink: nil, level: nil, description: nil, state: .unknown)
        let actions = SuggestedActionEngine.actions(
            for: goal, craftingPlan: plan,
            context: SuggestedActionContext(
                currentMapID: 15, playerPosition: .init(x: 110, y: 100),
                mapObjectives: [node], prices: [:], itemNames: [19_700: "Mithril Ore"]))
        XCTAssertEqual(actions.first?.type, .gather)
        XCTAssertEqual(actions.first?.confidence, .derivedStrong)
        XCTAssertTrue(actions.first?.reason.contains("not guaranteed") == true)
    }

    func testNoTelemetryGracefullyFallsBackToInspect() {
        let goal = PlayerGoal(title: "Custom", type: .custom)
        let actions = SuggestedActionEngine.actions(
            for: goal,
            context: SuggestedActionContext(
                currentMapID: nil, playerPosition: nil, mapObjectives: [], prices: [:], itemNames: [:]))
        XCTAssertEqual(actions.first?.type, .inspect)
    }
}

final class PhaseFourGoalDomainTests: XCTestCase {
    func testPersistenceAndStableAccountScopingDoNotMixGoals() throws {
        let suite = "PhaseFourGoals-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = PlayerGoal(title: "A", type: .achievement(42), priority: .high)
        let accountB = PlayerGoal(title: "B", type: .custom, status: .paused)
        GoalPersistence.save([accountA], accountID: "account-a", defaults: defaults)
        GoalPersistence.save([accountB], accountID: "account-b", defaults: defaults)
        XCTAssertEqual(GoalPersistence.load(accountID: "account-a", defaults: defaults), [accountA])
        XCTAssertEqual(GoalPersistence.load(accountID: "account-b", defaults: defaults), [accountB])
        XCTAssertTrue(GoalPersistence.load(accountID: nil, defaults: defaults).isEmpty)
    }

    func testCustomGoalSourceAndManualMapLinkRemainUserDeclaredAfterCodableRoundTrip() throws {
        let objective = MapObjective(
            id: .init("user:one"), mapId: 15, name: "Ruins", type: .custom,
            continentX: 1, continentY: 2, source: .user, chatLink: nil,
            level: nil, description: nil, state: .unknown)
        let goal = PlayerGoal(
            title: "Explore", type: .custom,
            sourceReference: .init(apiPath: nil, apiID: nil, provenance: .userDeclared),
            checklist: [.init(title: "Find ruins")],
            mapLinks: [.init(achievementBitIndex: nil, objective: objective)])
        let decoded = try JSONDecoder().decode(PlayerGoal.self, from: JSONEncoder().encode(goal))
        XCTAssertEqual(decoded, goal)
        XCTAssertEqual(decoded.checklist.first?.provenance, .userDeclared)
        XCTAssertEqual(decoded.mapLinks.first?.provenance, .userDeclared)
    }

    func testRecipeAvailabilityKeepsDisciplineAndUnlockSignalsIndependent() {
        let recipe = RecipeDefinition(
            id: 1, type: "Weapon", outputItemID: 2, outputItemCount: 1,
            timeToCraftMS: nil, disciplines: ["Weaponsmith"], minRating: 500,
            flags: [], ingredients: [], chatLink: nil)
        let character = GW2Character(
            name: "Andrea", race: "Human", gender: "Female", profession: "Warrior",
            level: 80, age: 1, crafting: [.init(discipline: "Weaponsmith", rating: 500, active: true)])
        let unknown = RecipeCapabilityEngine.capability(
            recipe: recipe, characters: [character], unlockedRecipeIDs: [], unlockPermissionAvailable: false)
        XCTAssertTrue(unknown.disciplineSatisfied)
        XCTAssertEqual(unknown.recipeAvailability, .unknown)
        let locked = RecipeCapabilityEngine.capability(
            recipe: recipe, characters: [character], unlockedRecipeIDs: [], unlockPermissionAvailable: true)
        XCTAssertEqual(locked.recipeAvailability, .locked)
    }

    func testHoldingsFixtureAggregatesEveryLocationWithoutDoubleCounting() throws {
        let data = try fixtureData("holdings-phase4")
        let fixture = try JSONDecoder().decode(HoldingsFixture.self, from: data)
        var sources: [(ItemLocation, [InventorySlot])] = [
            (.materialStorage, fixture.materialStorage), (.bank, fixture.bank),
            (.sharedInventory, fixture.sharedInventory)
        ]
        sources.append(contentsOf: fixture.characters.map { (.character($0.key), $0.value) })
        let result = AccountHoldingAggregator.aggregate(sources)
        XCTAssertEqual(result.first(where: { $0.itemID == 3000 })?.totalQuantity, 18)
        XCTAssertEqual(result.first?.locations.count, 5)
    }
}

private struct HoldingsFixture: Decodable {
    let materialStorage: [InventorySlot]
    let bank: [InventorySlot]
    let sharedInventory: [InventorySlot]
    let characters: [String: [InventorySlot]]
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle(for: PhaseFourAchievementTests.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private func fixture<Value: Decodable>(_ type: Value.Type, _ name: String) throws -> Value {
    try JSONDecoder().decode(type, from: fixtureData(name))
}
