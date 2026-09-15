import XCTest
@testable import GW2Companion

final class PhaseEightLegendaryTests: XCTestCase {
    private let sunrise = 30703
    private let twilight = 30704
    private let bifrost = 30698
    private let incinerator = 30687
    private let dawn = 29169
    private let dusk = 29185
    private let spark = 29167
    private let legend = 29180
    private let giftOfFortune = 19626
    private let giftOfMastery = 19674
    private let giftOfMight = 19672
    private let giftOfMagic = 19673
    private let giftOfExploration = 19677
    private let giftOfBattle = 19678
    private let mysticClover = 19675
    private let ecto = 19721
    private let giftOfSunrise = 19647

    private func catalog() throws -> LegendaryCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundles = [Bundle(for: GoalStore.self), Bundle(for: PhaseEightLegendaryTests.self), .main]
        for bundle in bundles {
            if let loaded = try? BundledLegendaryCatalogProvider(bundle: bundle).catalog() {
                return loaded
            }
            if let url = bundle.url(forResource: "legendary-plans-v1", withExtension: "json") {
                let loaded = try decoder.decode(LegendaryCatalog.self, from: Data(contentsOf: url))
                XCTAssertTrue(LegendaryCatalogValidator.validate(loaded).isEmpty)
                return loaded
            }
        }
        return try BundledLegendaryCatalogProvider().catalog()
    }

    private func holding(_ itemID: Int, _ quantity: Int) -> AccountHolding {
        AccountHolding(
            itemID: itemID, totalQuantity: quantity,
            locations: [HoldingLocation(location: .bank, quantity: quantity)])
    }

    private func price(id: Int, unit: Int, quantity: Int = 1000) -> TimedCommercePrice {
        TimedCommercePrice(
            price: CommercePrice(
                id: id, whitelisted: true,
                buys: CommerceListingSummary(quantity: 1, unitPrice: max(1, unit - 1)),
                sells: CommerceListingSummary(quantity: quantity, unitPrice: unit)),
            fetchedAt: Date())
    }

    func testBundledLegendaryCatalogLoadsAndSharesGiftDefinitions() throws {
        let catalog = try catalog()
        XCTAssertTrue(LegendaryCatalogValidator.validate(catalog).isEmpty)
        XCTAssertEqual(Set([sunrise, twilight, bifrost, incinerator]).subtracting(catalog.plansByItemID.keys), [])
        XCTAssertEqual(catalog.components.filter { $0.itemID == giftOfFortune }.count, 1)
        XCTAssertEqual(catalog.components.filter { $0.itemID == giftOfMastery }.count, 1)
        XCTAssertEqual(catalog.componentsByID[giftOfFortune]?.ingredients.contains { $0.itemID == giftOfMight }, true)
        XCTAssertEqual(catalog.coverage, .partial)
        XCTAssertTrue(catalog.plans.allSatisfy { $0.coverage == .partial })
    }

    func testOwnedArmoryLegendaryIsNotDescribedAsCrafted() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [], armoryCounts: [sunrise: 1]))
        XCTAssertEqual(plan.ownership, .armory)
        XCTAssertEqual(plan.progress.label, "Owned in Legendary Armory ✓")
        XCTAssertTrue(plan.progress.isAuthoritativeCompletion)
        XCTAssertTrue(plan.tradableMissing.isEmpty)
    }

    func testHoldingsOwnedLegendaryIsDistinctFromArmory() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [holding(sunrise, 1)], armoryCounts: [:]))
        XCTAssertEqual(plan.ownership, .holdings)
        XCTAssertEqual(plan.progress.label, "Owned in account holdings ✓")
        XCTAssertFalse(plan.progress.isAuthoritativeCompletion)
    }

    func testZeroProgressLegendaryExpandsTopLevelAndMysticForge() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [], armoryCounts: [:]))
        XCTAssertEqual(plan.topLevel.map(\.itemID), [dawn, giftOfSunrise, giftOfFortune, giftOfMastery])
        XCTAssertEqual(plan.topLevelReadyCount, 0)
        XCTAssertEqual(plan.topLevelTotalCount, 4)
        XCTAssertTrue(plan.sessionNodes.contains { $0.itemID == giftOfFortune && $0.acquisition == .mysticForge })
        XCTAssertTrue(plan.flattenedLeaves.contains { $0.itemID == dawn && $0.binding == .tradable })
        XCTAssertTrue(plan.flattenedLeaves.contains { $0.itemID == mysticClover && $0.binding == .accountBound })
    }

    func testPartialTopLevelOwnershipKeepsRemainingMissing() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [holding(dawn, 1)], armoryCounts: [:]))
        XCTAssertEqual(plan.topLevel.first { $0.itemID == dawn }?.status, .owned)
        XCTAssertEqual(plan.topLevel.first { $0.itemID == giftOfFortune }?.missingQuantity, 1)
        XCTAssertEqual(plan.topLevelReadyCount, 1)
    }

    func testTradablePrecursorIsPricedAndAccountBoundIsNot() throws {
        let catalog = try catalog()
        let prices = [dawn: price(id: dawn, unit: 1_000_000), ecto: price(id: ecto, unit: 50)]
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [], armoryCounts: [:], prices: prices))
        XCTAssertTrue(plan.tradableMissing.contains { $0.itemID == dawn })
        XCTAssertFalse(plan.tradableMissing.contains { $0.itemID == giftOfExploration })
        XCTAssertFalse(plan.tradableMissing.contains { $0.itemID == mysticClover })
        XCTAssertNotNil(plan.estimatedBuyNowCopper)
        XCTAssertFalse(plan.accountBoundMissing.isEmpty)
    }

    func testUnavailablePriceDoesNotInventABuyNowTotal() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: incinerator, catalog: catalog, holdings: [], armoryCounts: [:], prices: [:]))
        XCTAssertNil(plan.estimatedBuyNowCopper)
        XCTAssertFalse(plan.pricesUnavailableItemIDs.isEmpty)
        XCTAssertTrue(plan.tradableMissing.contains { $0.itemID == spark })
    }

    func testGiftOfExplorationStaysUnknownUnlessOwned() throws {
        let catalog = try catalog()
        let ingredientsExceptExploration = [
            holding(20797, 1), holding(19925, 250), holding(giftOfBattle, 1)
        ]
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: ingredientsExceptExploration, armoryCounts: [:]))
        let exploration = try XCTUnwrap(plan.sessionNodes.first { $0.itemID == giftOfExploration })
        XCTAssertEqual(exploration.status, .unknownManual)
        XCTAssertEqual(exploration.missingQuantity, 1)
        XCTAssertNotEqual(plan.topLevel.first { $0.itemID == giftOfMastery }?.status, .owned)
    }

    func testOwnedExplorationIsOwnedAndNotInferredFromSiblingGifts() throws {
        let catalog = try catalog()
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: twilight, catalog: catalog, holdings: [holding(giftOfExploration, 1)], armoryCounts: [:]))
        XCTAssertEqual(plan.sessionNodes.first { $0.itemID == giftOfExploration }?.status, .owned)
        XCTAssertEqual(plan.sessionNodes.first { $0.itemID == giftOfBattle }?.status, .unknownManual)
    }

    func testSharedGiftRequirementConsolidatesAcrossTwoLegendaryGoals() throws {
        let catalog = try catalog()
        let methods = LegendaryPlanner.acquisitionMethods(from: catalog)
        let sunrisePlan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog, holdings: [holding(giftOfFortune, 1)], armoryCounts: [:]))
        let twilightPlan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: twilight, catalog: catalog, holdings: [holding(giftOfFortune, 1)], armoryCounts: [:]))
        XCTAssertEqual(sunrisePlan.sessionNodes.first { $0.itemID == giftOfFortune }?.requiredQuantity, 1)
        XCTAssertEqual(twilightPlan.sessionNodes.first { $0.itemID == giftOfFortune }?.requiredQuantity, 1)

        let sunriseGoal = UUID()
        let twilightGoal = UUID()
        func requirements(_ plan: LegendaryProgressPlan, goalID: UUID) -> [PlanningRequirement] {
            plan.sessionNodes.map {
                PlanningRequirement(
                    id: "\(goalID)|\($0.itemID)", target: .item(id: $0.itemID, quantity: $0.requiredQuantity),
                    requiredQuantity: $0.requiredQuantity, name: $0.name,
                    provenance: [.companionObserved], craftReady: $0.missingQuantity == 0)
            }
        }
        let context = SessionPlanningContext(
            goals: [
                PlanningGoal(
                    id: sunriseGoal, title: "Sunrise", priority: .high,
                    requirements: requirements(sunrisePlan, goalID: sunriseGoal),
                    linkedObjectives: [], fallbackReason: nil),
                PlanningGoal(
                    id: twilightGoal, title: "Twilight", priority: .normal,
                    requirements: requirements(twilightPlan, goalID: twilightGoal),
                    linkedObjectives: [], fallbackReason: nil)
            ],
            holdings: [giftOfFortune: 1], currencies: [:], acquisitionMethods: methods,
            preferences: PlanningPreferences(), parameters: SessionParameters(),
            currentMapID: nil, playerPosition: nil, mapObjectives: [])
        let session = SessionPlanner.plan(context: context)
        let fortuneTasks = session.tasks.filter { $0.target?.numericID == giftOfFortune }
        XCTAssertEqual(fortuneTasks.first?.quantity, 1)
        XCTAssertTrue(fortuneTasks.contains { $0.type == .mysticForge })
        XCTAssertTrue(fortuneTasks.contains { $0.relatedGoalIDs.count == 2 })
    }

    func testPartialKnowledgeCoverageIsVisible() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.availability(for: sunrise), .partial)
        XCTAssertEqual(catalog.availability(for: 1), .none)
        let methods = LegendaryPlanner.acquisitionMethods(from: catalog)
        XCTAssertTrue(methods.contains { $0.target.numericID == giftOfFortune && $0.type == .mysticForge })
        XCTAssertTrue(methods.contains { $0.target.numericID == dawn && $0.type == .tradingPost })
        XCTAssertTrue(methods.contains { $0.target.numericID == giftOfExploration && $0.type == .manual })
    }

    func testLegendaryGoalTypeRoundTrips() throws {
        let goal = PlayerGoal(title: "Sunrise", type: .legendary(itemID: sunrise))
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(PlayerGoal.self, from: data)
        XCTAssertEqual(decoded.type, .legendary(itemID: sunrise))
        XCTAssertEqual(decoded.type.title, "Legendary")
    }

    func testBrowserMarksOwnedAndLimitedPlans() throws {
        let catalog = try catalog()
        let items = LegendaryPlanner.browserItems(
            definitions: [LegendaryArmoryDefinition(id: sunrise, maxCount: 1)],
            items: [sunrise: ItemMetadata(
                id: sunrise, name: "Sunrise", icon: nil, rarity: "Legendary", type: "Weapon",
                details: ItemDetails(type: "Greatsword"))],
            catalog: catalog, armoryCounts: [sunrise: 1], holdings: [])
        let row = try XCTUnwrap(items.first { $0.itemID == sunrise })
        XCTAssertEqual(row.ownership, .armory)
        XCTAssertEqual(row.availability, .partial)
        XCTAssertEqual(row.category, .weapons)
    }
}
