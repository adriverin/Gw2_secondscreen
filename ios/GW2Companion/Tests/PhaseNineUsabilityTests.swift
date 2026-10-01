import CoreGraphics
import XCTest
@testable import GW2Companion

final class DerivedDetailedTileTests: XCTestCase {
    func testZoomSixMapsToCorrectFourZoomSevenChildren() throws {
        let request = DerivedDetailedTileRequest(
            continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 6, x: 87, y: 61), sourceZoom: 7)

        XCTAssertEqual(try XCTUnwrap(request.sourceTiles()), [
            TileIndex(zoom: 7, x: 174, y: 122),
            TileIndex(zoom: 7, x: 175, y: 122),
            TileIndex(zoom: 7, x: 174, y: 123),
            TileIndex(zoom: 7, x: 175, y: 123)
        ])
        XCTAssertEqual(request.sourceTileCount, 4)
    }

    func testZoomFiveMapsToCorrectSixteenZoomSevenChildren() throws {
        let request = DerivedDetailedTileRequest(
            continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 5, x: 43, y: 30), sourceZoom: 7)
        let children = try XCTUnwrap(request.sourceTiles())

        XCTAssertEqual(children.count, 16)
        XCTAssertEqual(children.first, TileIndex(zoom: 7, x: 172, y: 120))
        XCTAssertEqual(children.last, TileIndex(zoom: 7, x: 175, y: 123))
        XCTAssertEqual(Set(children.map(\.x)), Set(172...175))
        XCTAssertEqual(Set(children.map(\.y)), Set(120...123))
    }

    func testSourceTilesNeverEscapeProjectionCoverage() {
        let request = DerivedDetailedTileRequest(
            continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 6, x: 160, y: 61), sourceZoom: 7)
        XCTAssertNil(request.sourceTiles())
    }

    func testCacheKeyIncludesFloorSourceZoomAndProjectionVersion() {
        let tile = TileIndex(zoom: 6, x: 87, y: 61)
        let first = DerivedDetailedTileRequest(
            continent: 1, floor: 1, displayTile: tile, sourceZoom: 7,
            projectionVersion: "projection-a")
        let differentFloor = DerivedDetailedTileRequest(
            continent: 1, floor: 2, displayTile: tile, sourceZoom: 7,
            projectionVersion: "projection-a")
        let differentVersion = DerivedDetailedTileRequest(
            continent: 1, floor: 1, displayTile: tile, sourceZoom: 7,
            projectionVersion: "projection-b")

        XCTAssertNotEqual(first.cacheKey, differentFloor.cacheKey)
        XCTAssertNotEqual(first.cacheKey, differentVersion.cacheKey)
        XCTAssertTrue(first.cacheKey.contains("display-z6-x87-y61"))
        XCTAssertTrue(first.cacheKey.contains("source-z7"))
    }

    func testBalancedUsesNativeAndDetailedUsesDerivedOnlyAtModerateZoom() {
        XCTAssertEqual(
            MapRasterDetail.renderingSource(
                displayZoom: 6, continentID: 1, mode: .balanced,
                visibleDisplayTileCount: 4),
            .native(zoom: 6))
        XCTAssertEqual(
            MapRasterDetail.renderingSource(
                displayZoom: 6, continentID: 1, mode: .detailed,
                visibleDisplayTileCount: 4),
            .derived(sourceZoom: 7))
        XCTAssertEqual(
            MapRasterDetail.renderingSource(
                displayZoom: 5, continentID: 1, mode: .detailed,
                visibleDisplayTileCount: 4),
            .derived(sourceZoom: 7))
        XCTAssertEqual(
            MapRasterDetail.renderingSource(
                displayZoom: 4, continentID: 1, mode: .detailed,
                visibleDisplayTileCount: 4),
            .native(zoom: 4))
        XCTAssertEqual(
            MapRasterDetail.renderingSource(
                displayZoom: 6, continentID: 1, mode: .detailed,
                visibleDisplayTileCount: MapRasterDetail.maximumVisibleDerivedTiles + 1),
            .native(zoom: 6))
    }

    func testCancellationStopsDerivedGeneration() async {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GW2DerivedCancellation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = DerivedDetailedTileProvider(directory: directory) { _ in
            try? await Task.sleep(for: .seconds(2))
            return nil
        }
        let request = DerivedDetailedTileRequest(
            continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 6, x: 87, y: 61), sourceZoom: 7)

        let task = Task { await provider.image(for: request) }
        try? await Task.sleep(for: .milliseconds(30))
        await provider.cancel(request)
        let result = await task.value

        XCTAssertNil(result)
    }
}

final class OwnedInventoryPricingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testVisibleItemBatchDeduplicatesAndPrioritizesSelection() {
        XCTAssertEqual(
            InventoryPriceBatchPlanner.batch(
                visibleItemIDs: [3, 2, 3, 4, 5], selectedItemID: 9, limit: 4),
            [9, 3, 2, 4])
        XCTAssertEqual(
            InventoryPriceBatchPlanner.batch(visibleItemIDs: [1, 2], selectedItemID: 9, limit: 1),
            [9])
    }

    func testSellNowAndBuyNowUseCorrectOrderSidesAndStackMultiplication() {
        let values = OwnedItemMarketValues(
            item: item(), quantity: 3,
            price: price(buy: 100, sell: 175), now: now)

        XCTAssertEqual(values.sellNow?.unitCopper, 100)
        XCTAssertEqual(values.sellNow?.copper, 300)
        XCTAssertEqual(values.buyNow?.unitCopper, 175)
        XCTAssertEqual(values.buyNow?.copper, 525)
        XCTAssertEqual(values.sellState, .available)
        XCTAssertEqual(values.buyState, .available)
    }

    func testNontradableAndUnavailablePricesNeverBecomeZeroCoinValues() {
        let bound = item(flags: ["AccountBound"])
        let boundValues = OwnedItemMarketValues(
            item: bound, quantity: 10, price: price(buy: 100, sell: 175), now: now)
        XCTAssertEqual(boundValues.sellState, .nonTradable)
        XCTAssertEqual(boundValues.buyState, .nonTradable)

        let unavailable = OwnedItemMarketValues(item: item(), quantity: 10, price: nil, now: now)
        XCTAssertNil(unavailable.sellNow)
        XCTAssertNil(unavailable.buyNow)
        XCTAssertEqual(unavailable.sellState, .noPriceRecord)
        XCTAssertEqual(unavailable.buyState, .noPriceRecord)
    }

    func testMaterialSnapshotBuildsWithoutAnyPriceInput() {
        let metadata = item()
        let snapshot = MaterialStorageSnapshotBuilder.build(
            materials: [AccountMaterial(id: metadata.id, category: 1, count: 250)],
            categories: [1: MaterialCategoryMetadata(
                id: 1, name: "Basic Crafting Materials", items: [metadata.id], order: 1)],
            metadata: [metadata.id: metadata], source: .live)

        XCTAssertEqual(snapshot.sections.first?.rows.first?.count, 250)
        XCTAssertEqual(snapshot.metrics.rowModelsCreated, 1)
    }

    private func item(flags: [String]? = nil) -> ItemMetadata {
        ItemMetadata(id: 19697, name: "Mithril Ore", icon: nil, rarity: "Basic", flags: flags)
    }

    private func price(buy: Int, sell: Int) -> TimedCommercePrice {
        TimedCommercePrice(
            price: CommercePrice(
                id: 19697, whitelisted: true,
                buys: CommerceListingSummary(quantity: 1_000, unitPrice: buy),
                sells: CommerceListingSummary(quantity: 1_000, unitPrice: sell)),
            fetchedAt: now)
    }
}

final class WalletDisclosureRegressionTests: XCTestCase {
    func testSearchTemporarilyExpandsWithoutMutatingPersistedPreference() throws {
        let suite = "WalletDisclosure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = "fixture-account"
        WalletPresentation.setAllExpanded(false, accountID: accountID, defaults: defaults)

        XCTAssertFalse(WalletPresentation.effectiveAllExpanded(stored: false, query: ""))
        XCTAssertTrue(WalletPresentation.effectiveAllExpanded(stored: false, query: "karma"))
        XCTAssertFalse(WalletPresentation.isAllExpanded(accountID: accountID, defaults: defaults))
        XCTAssertFalse(WalletPresentation.effectiveAllExpanded(
            stored: WalletPresentation.isAllExpanded(accountID: accountID, defaults: defaults), query: ""))
    }

}

final class CharacterStatFidelityV3Tests: XCTestCase {
    private let level80 = GW2Character(
        name: "Audit", race: "Human", gender: "Female", profession: "Warrior", level: 80, age: 1)

    func testSelectedEquipmentStatsTakePrecedenceWithoutDoubleCountingGenericInfix() {
        let item = metadata(
            id: 100, name: "Selectable Helm", type: "Armor",
            details: ItemDetails(
                type: "Helm", defense: 127,
                infixUpgrade: InfixUpgrade(
                    id: 1, attributes: [ItemAttribute(attribute: "Power", modifier: 100)], buff: nil)))
        let equipped = CharacterEquipment(
            itemID: item.id, slot: "Helm",
            stats: SelectedItemStats(id: 2, attributes: ["Power": 150]))

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: [equipped], items: [item.id: item])

        XCTAssertEqual(stats.total(for: "Power"), 1_150)
        XCTAssertEqual(stats.attributes["Power"]?.equipment, 150)
    }

    func testUnresolvedSelectableEquipmentDoesNotGuessFromGenericInfix() {
        let item = metadata(
            id: 101, name: "Unresolved Selectable Coat", type: "Armor",
            details: ItemDetails(
                type: "Coat",
                infixUpgrade: InfixUpgrade(
                    id: 1, attributes: [ItemAttribute(attribute: "Power", modifier: 100)], buff: nil),
                statChoices: [1, 2]))

        let stats = CharacterStatEngine.calculate(
            character: level80,
            equipment: [CharacterEquipment(itemID: item.id, slot: "Coat")],
            items: [item.id: item])

        XCTAssertEqual(stats.total(for: "Power"), 1_000)
        XCTAssertTrue(stats.excludedSources.contains { $0.contains("selectable equipment stat source unavailable") })
    }

    func testArmorAddsToughnessArmorDefenseAndShieldDefense() {
        let helm = metadata(id: 100, name: "Helm", type: "Armor", details: ItemDetails(type: "Helm", defense: 127))
        let shield = metadata(id: 101, name: "Shield", type: "Weapon", details: ItemDetails(type: "Shield", defense: 64))
        let equipment = [
            CharacterEquipment(
                itemID: helm.id, slot: "Helm",
                stats: SelectedItemStats(id: 1, attributes: ["Toughness": 100])),
            CharacterEquipment(itemID: shield.id, slot: "WeaponA2")
        ]

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: equipment, items: [helm.id: helm, shield.id: shield])

        XCTAssertEqual(stats.defense.armorPieces, 127)
        XCTAssertEqual(stats.defense.shield, 64)
        XCTAssertEqual(stats.derived.armor, 1_100 + 127 + 64)
    }

    func testProfessionHealthTiersIncludeVitalityContribution() {
        XCTAssertEqual(CharacterStatEngine.professionBaseHealth("Warrior") + 10_000, 19_212)
        XCTAssertEqual(CharacterStatEngine.professionBaseHealth("Ranger") + 10_000, 15_922)
        XCTAssertEqual(CharacterStatEngine.professionBaseHealth("Elementalist") + 10_000, 11_645)
    }

    func testLevel80DerivedFormulas() {
        XCTAssertEqual(CharacterStatEngine.criticalChance(precision: 1_147), 12, accuracy: 0.0001)
        XCTAssertEqual(CharacterStatEngine.criticalDamage(ferocity: 750), 200, accuracy: 0.0001)
        XCTAssertEqual(CharacterStatEngine.duration(attribute: 450), 30, accuracy: 0.0001)
        XCTAssertEqual(CharacterStatEngine.duration(attribute: 1_800), 100, accuracy: 0.0001)

        let equipped = CharacterEquipment(
            itemID: 100, slot: "Coat",
            stats: SelectedItemStats(id: 1, attributes: ["Concentration": 450, "Expertise": 300]))
        let calculated = CharacterStatEngine.calculate(
            character: level80, equipment: [equipped], items: [:])
        XCTAssertEqual(calculated.derived.boonDurationPercent ?? 0, 30, accuracy: 0.0001)
        XCTAssertEqual(calculated.derived.conditionDurationPercent ?? 0, 20, accuracy: 0.0001)
    }

    func testStructuredUpgradeAttributesUseCanonicalAPINames() {
        let upgrade = metadata(
            id: 200, name: "Deterministic Upgrade", type: "UpgradeComponent",
            details: ItemDetails(
                type: "Default",
                infixUpgrade: InfixUpgrade(
                    id: nil,
                    attributes: [
                        ItemAttribute(attribute: "CritDamage", modifier: 50),
                        ItemAttribute(attribute: "BoonDuration", modifier: 15)
                    ],
                    buff: nil)))
        let equipped = CharacterEquipment(itemID: 100, slot: "WeaponA1", upgrades: [upgrade.id])

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: [equipped], items: [upgrade.id: upgrade])

        XCTAssertEqual(stats.attributes["Ferocity"]?.upgradeComponents, 50)
        XCTAssertEqual(stats.attributes["Concentration"]?.upgradeComponents, 15)
    }

    func testActiveMajorAndMinorTraitsApplyAdjustThenBuffConversion() {
        let adjust = TraitMetadata(
            id: 803, name: "Deterministic Adjust", icon: nil, description: "ignored", tier: 1, slot: "Minor",
            facts: [TraitFact(type: "AttributeAdjust", target: "Precision", value: 180)])
        let conversion = TraitMetadata(
            id: 232, name: "Deterministic Conversion", icon: nil, description: "ignored", tier: 2, slot: "Major",
            facts: [TraitFact(
                type: "BuffConversion", target: "CritDamage", source: "Precision", percent: 7)])
        let build = CharacterBuild(
            name: "PvE", profession: "Warrior",
            specializations: [BuildSpecialization(id: 1, traits: [232])], skills: .empty)
        let specialization = SpecializationMetadata(
            id: 1, name: "Audit", profession: "Warrior", elite: false,
            icon: nil, background: nil, minorTraits: [803], majorTraits: [232])

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: [], items: [:], build: build,
            traits: [803: adjust, 232: conversion], specializations: [1: specialization])

        XCTAssertEqual(stats.attributes["Precision"]?.traits, 180)
        XCTAssertEqual(stats.attributes["Ferocity"]?.traits, 82)
        XCTAssertEqual(stats.modeledTraitCount, 2)
    }

    func testUncuratedPotentiallyConditionalTraitIsExcluded() {
        let trait = TraitMetadata(
            id: 999_999, name: "Conditional", icon: nil,
            description: "While in combat, gain power.", tier: 2, slot: "Major",
            facts: [TraitFact(type: "AttributeAdjust", target: "Power", value: 200)])
        let build = CharacterBuild(
            name: "PvE", profession: "Warrior",
            specializations: [BuildSpecialization(id: nil, traits: [trait.id])], skills: .empty)

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: [], items: [:], build: build, traits: [trait.id: trait])

        XCTAssertEqual(stats.total(for: "Power"), 1_000)
        XCTAssertEqual(stats.excludedTraitCount, 1)
        XCTAssertTrue(stats.excludedSources.contains { $0.contains("trait modifiers excluded") })
    }

    func testUnknownRuneProducesPartialCoverageDisclosure() {
        let rune = metadata(id: 24899, name: "Unknown Rune", type: "UpgradeComponent", details: ItemDetails(type: "Rune"))
        let equipped = CharacterEquipment(itemID: 100, slot: "Helm", upgrades: [rune.id])

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: [equipped], items: [rune.id: rune])

        XCTAssertEqual(stats.coverage, .partial)
        XCTAssertTrue(stats.excludedSources.contains { $0.contains("Rune bonuses not fully modeled") })
    }

    func testCuratedScholarRuneSixPieceAttributesAreDeterministic() {
        let rune = metadata(
            id: 24_836, name: "Superior Rune of the Scholar", type: "UpgradeComponent",
            details: ItemDetails(type: "Rune", bonuses: [
                "+25 Power", "+35 Ferocity", "+50 Power",
                "+65 Ferocity", "+100 Power", "+125 Ferocity"
            ]))
        let equipment = (0..<6).map { index in
            CharacterEquipment(itemID: 100 + index, slot: "Armor\(index)", upgrades: [rune.id])
        }

        let stats = CharacterStatEngine.calculate(
            character: level80, equipment: equipment, items: [rune.id: rune])

        XCTAssertEqual(stats.attributes["Power"]?.runes, 175)
        XCTAssertEqual(stats.attributes["Ferocity"]?.runes, 225)
        XCTAssertFalse(stats.excludedSources.contains { $0.contains("Rune bonuses not fully modeled") })
    }

    private func metadata(
        id: Int, name: String, type: String, details: ItemDetails? = nil
    ) -> ItemMetadata {
        ItemMetadata(id: id, name: name, icon: nil, rarity: "Ascended", type: type, details: details)
    }
}

final class LegendaryUXV2Tests: XCTestCase {
    private let sunrise = 30_703
    private let twilight = 30_704

    func testOwnedLegendaryRetainsFullPlanAndViewFullPlanAction() throws {
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: sunrise, catalog: catalog(), holdings: [], armoryCounts: [sunrise: 1]))

        XCTAssertEqual(plan.ownership.planActionTitle, "View Full Plan")
        XCTAssertFalse(plan.topLevel.isEmpty)
        XCTAssertTrue(plan.topLevel.allSatisfy(\.isComplete))
    }

    func testCompletedBranchesCollapseByDefaultAndRemainAvailable() throws {
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: twilight, catalog: catalog(),
            holdings: [holding(29_185, 1)], armoryCounts: [:]))

        XCTAssertFalse(plan.topLevel.allSatisfy(\.isComplete))
        XCTAssertEqual(plan.visibleTopLevel(showCompleted: false).count, plan.topLevel.count - 1)
        XCTAssertEqual(plan.visibleTopLevel(showCompleted: true), plan.topLevel)
    }

    func testTwilightPartialPlanSeparatesTradableAndAccountBoundRequirements() throws {
        let plan = try XCTUnwrap(LegendaryPlanner.plan(
            itemID: twilight, catalog: catalog(), holdings: [], armoryCounts: [:]))

        XCTAssertEqual(plan.ownership.planActionTitle, "View Plan")
        XCTAssertEqual(plan.topLevelTotalCount, 4)
        XCTAssertFalse(plan.tradableMissing.isEmpty)
        XCTAssertFalse(plan.accountBoundMissing.isEmpty)
        XCTAssertTrue(plan.tradableMissing.allSatisfy { $0.binding == .tradable })
        XCTAssertTrue(plan.accountBoundMissing.allSatisfy { $0.binding == .accountBound })
    }

    private func holding(_ itemID: Int, _ quantity: Int) -> AccountHolding {
        AccountHolding(
            itemID: itemID, totalQuantity: quantity,
            locations: [HoldingLocation(location: .bank, quantity: quantity)])
    }

    private func catalog() throws -> LegendaryCatalog {
        let bundles = [Bundle(for: GoalStore.self), Bundle(for: Self.self), .main]
        for bundle in bundles {
            if let loaded = try? BundledLegendaryCatalogProvider(bundle: bundle).catalog() {
                return loaded
            }
        }
        return try BundledLegendaryCatalogProvider().catalog()
    }
}
