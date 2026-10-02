import XCTest
import UIKit
@testable import GW2Companion

@MainActor
final class ContinuousMapCameraTests: XCTestCase {
    private let size = CGSize(width: 1024, height: 1366)
    private let center = ContinentPoint(x: 44615.5, y: 29863.7)

    private func transform(_ zoom: Double, center: ContinentPoint? = nil) -> MapViewportTransform {
        MapViewportTransform(center: center ?? self.center, zoom: 6, magnification: 1,
                             dragOffset: .zero, size: size, cameraZoom: zoom)
    }

    func testFractionalCameraScaleAndContinuousMarkerGeometry() {
        XCTAssertEqual(ContinuousMapCamera.scale(cameraZoom: 6.3, sourceZoom: 6), pow(2, 0.3), accuracy: 0.000001)
        let point = ContinentPoint(x: center.x + 100, y: center.y - 100)
        var previous = transform(5).screenPosition(for: point)
        for step in 1...200 {
            let zoom = 5 + Double(step) / 100
            let position = transform(zoom).screenPosition(for: point)
            XCTAssertGreaterThan(position.x, previous.x)
            XCTAssertLessThan(position.y, previous.y)
            XCTAssertLessThan(position.x - previous.x, 1)
            XCTAssertEqual(transform(zoom).continentPoint(for: position).x, point.x, accuracy: 0.000001)
            previous = position
        }
    }

    func testNortheastPinchAnchorAndMovingFingerCentroid() {
        let anchor = CGPoint(x: 900, y: 120)
        let geographic = transform(5.8).continentPoint(for: anchor)
        let pinch = ContinuousMapCamera.Pinch(startZoom: 5.8, screenAnchor: anchor, continentAnchor: geographic)
        for scale in [0.31, 0.71, 1.01, 1.25, 2.1, 30.0] {
            let update = pinch.update(magnification: scale, size: size, referenceZoom: 7)
            let actual = transform(update.zoom, center: update.center).screenPosition(for: geographic)
            XCTAssertEqual(actual.x, anchor.x, accuracy: 0.000001)
            XCTAssertEqual(actual.y, anchor.y, accuracy: 0.000001)
            XCTAssertTrue((2...7).contains(update.zoom))
        }
        let moving = CGPoint(x: 840, y: 180)
        let update = pinch.update(magnification: 1.3, size: size, referenceZoom: 7, movingAnchor: moving)
        XCTAssertEqual(update.zoom, 5.8 + log2(1.3), accuracy: 0.000001)
        let actual = transform(update.zoom, center: update.center).screenPosition(for: geographic)
        XCTAssertEqual(actual.x, moving.x, accuracy: 0.000001)
        XCTAssertEqual(actual.y, moving.y, accuracy: 0.000001)
    }

    func testSourceHysteresisDoesNotThrashAndClampsMists() {
        var source = 6
        for zoom in [6.49, 6.51, 6.64, 6.4, 6.6] {
            source = ContinuousMapCamera.sourceZoom(cameraZoom: zoom, current: source, maximum: 7)
            XCTAssertEqual(source, 6)
        }
        source = ContinuousMapCamera.sourceZoom(cameraZoom: 6.65, current: source, maximum: 7)
        XCTAssertEqual(source, 7)
        for zoom in [6.64, 6.51, 6.36] {
            source = ContinuousMapCamera.sourceZoom(cameraZoom: zoom, current: source, maximum: 7)
            XCTAssertEqual(source, 7)
        }
        XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: 6.34, current: source, maximum: 7), 6)
        XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: 5.34, current: 6, maximum: 7), 5)
        XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: 8, current: 5, maximum: 6), 6)
    }

    func testFractionalLabelFadeDoesNotWaitForIntegerZoom() {
        let objective = MapObjective(id: MapObjectiveID("label-fixture"), mapId: 23, name: "Waypoint", type: .waypoint,
            continentX: center.x, continentY: center.y, source: .arenaNet, chatLink: nil, level: nil, description: nil, state: .unknown)
        for (zoom, opacity) in [(5.2, 0.0), (5.6, 0.5), (6.0, 1.0)] {
            let appearance = MapDetailPolicy.appearance(for: objective, mode: .detailed, cameraZoom: zoom, targetID: nil)
            XCTAssertEqual(appearance.labelOpacity, opacity, accuracy: 0.000001)
            XCTAssertEqual(appearance.size, 26)
        }
        let important = MapDetailPolicy.appearance(for: objective, mode: .detailed, cameraZoom: 4.1, targetID: objective.id)
        XCTAssertTrue(important.showLabel)
        XCTAssertEqual(important.labelOpacity, 1)
    }

    func testWholeLayerRetentionCrossfadeAndStaleCompletion() async throws {
        let image = makeTile()
        let old = MapRasterLayerRequest(continent: 1, floor: 1, tiles: [TileIndex(zoom: 5, x: 43, y: 30)], detailed: false)
        let next = MapRasterLayerRequest(continent: 1, floor: 1, tiles: [TileIndex(zoom: 4, x: 21, y: 15)], detailed: true)
        var handoff = MapRasterLayerHandoff()
        XCTAssertTrue(handoff.accept(MapRasterLayerFrame(request: old, images: [old.tiles[0]: image])))
        XCTAssertFalse(handoff.accept(MapRasterLayerFrame(request: next, images: [:])))
        XCTAssertEqual(handoff.active?.request, old, "Incomplete/cancelled replacements cannot blank the current layer")
        XCTAssertNil(handoff.outgoing)
        let failed = await MapRasterLayerLoader.frame(for: next, derivedLoader: { _ in nil })
        XCTAssertNil(failed)
        XCTAssertTrue(handoff.accept(MapRasterLayerFrame(request: next, images: [next.tiles[0]: image])))
        XCTAssertEqual(handoff.outgoing?.request, old)
        XCTAssertEqual(handoff.active?.request, next)
        XCTAssertEqual(ContinuousMapCamera.crossfadeSeconds, 0.15)
        handoff.finish(old)
        XCTAssertNotNil(handoff.outgoing)
        handoff.finish(next)
        XCTAssertNil(handoff.outgoing)
    }

    func testColdZ4NativeFrameAndCancellation() async {
        let tile = TileIndex(zoom: 4, x: 21, y: 15)
        let native = MapRasterLayerRequest(continent: 1, floor: 1, tiles: [tile], detailed: false)
        let image = makeTile()
        let frame = await MapRasterLayerLoader.frame(for: native, nativeLoader: { _ in image })
        XCTAssertTrue(frame?.isComplete == true)
        let task = Task { await MapRasterLayerLoader.frame(for: native, nativeLoader: { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return image
        }) }
        await Task.yield()
        task.cancel()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
    }

    func testIPadViewportBudgetAndColdWarmPyramidProfile() async throws {
        let tiles = ArenaNetTileProjection.shared.tiles(coveringContinentRect: transform(4).visibleContinentRect(),
                                                       zoom: 4, continentID: 1, mapFloor: 1)
        let request = MapRasterLayerRequest(continent: 1, floor: 1, tiles: tiles, detailed: true)
        XCTAssertTrue(request.permitsDetailed)
        for zoom in [5.0, 6.0] {
            let padded = ArenaNetTileProjection.shared.tiles(coveringContinentRect: transform(zoom).visibleContinentRect(marginPoints: 256),
                zoom: Int(zoom), continentID: 1, mapFloor: 1)
            XCTAssertTrue(MapRasterLayerRequest(continent: 1, floor: 1, tiles: padded, detailed: true).permitsDetailed,
                          "The prefetch ring must not suppress existing moderate-zoom detail on iPad")
        }
        XCTAssertLessThanOrEqual(tiles.count * 64, MapRasterLayerRequest.maximumColdSourceTiles)
        let directory = FileManager.default.temporaryDirectory.appending(path: "continuous-pyramid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = makeTile()
        let probe = TileFetchProbe()
        let provider = DerivedDetailedTileProvider(directory: directory, sourceLoader: { url in
            await probe.begin(url)
            await Task.yield()
            await probe.end()
            return image
        })
        let parent = DerivedDetailedTileRequest(continent: 1, floor: 1, displayTile: tiles[0], sourceZoom: 7)
        let children = try XCTUnwrap(parent.pyramidChildren())
        XCTAssertEqual(children.count, 4)
        XCTAssertTrue(children.allSatisfy { $0.zoom == 5 })
        // Zoom through z5 first, then z4 must consume cached parents with ZERO
        // additional source fetches (also after memory pressure via PNG disk cache).
        let started = ContinuousClock.now
        for child in children {
            let loaded = await provider.image(for: DerivedDetailedTileRequest(continent: 1, floor: 1, displayTile: child, sourceZoom: 7))
            XCTAssertNotNil(loaded)
        }
        let before = await probe.count
        XCTAssertEqual(before, 64)
        await provider.handleMemoryPressure()
        let result = await provider.image(for: parent)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.diagnostics.sourceTileCount, 4)
        let after = await probe.count
        let peak = await probe.peak
        XCTAssertEqual(after, before)
        XCTAssertLessThanOrEqual(peak, DerivedDetailedTileProvider.maximumSimultaneousSourceFetches)
        print("MAP_PYRAMID_PROFILE viewport=1024x1366 z4_parents=\(tiles.count) cold_leaf_budget=\(tiles.count * 64) warm_parent_additional_fetches=\(after - before) sample_elapsed=\(started.duration(to: .now)) peak_fetches=\(peak)")
        let fullStarted = ContinuousClock.now
        let full = await MapRasterLayerLoader.frame(for: request, derivedLoader: { await provider.image(for: $0)?.image })
        XCTAssertTrue(full?.isComplete == true)
        let fullCount = await probe.count
        XCTAssertEqual(fullCount, tiles.count * 64)
        let coldDuration = fullStarted.duration(to: .now)
        await provider.handleMemoryPressure()
        let warmStarted = ContinuousClock.now
        let warm = await MapRasterLayerLoader.frame(for: request, derivedLoader: { await provider.image(for: $0)?.image })
        XCTAssertTrue(warm?.isComplete == true)
        let warmCount = await probe.count
        XCTAssertEqual(warmCount, fullCount)
        print("MAP_PYRAMID_VIEWPORT_PROFILE cold=\(coldDuration) warm=\(warmStarted.duration(to: .now)) source_fetches=\(fullCount) warm_additional_fetches=\(warmCount - fullCount)")
    }

    func testPyramidRapidCancellationAndRetry() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cancel-pyramid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = makeTile()
        let provider = DerivedDetailedTileProvider(directory: directory, sourceLoader: { _ in
            try? await Task.sleep(for: .milliseconds(10))
            return image
        })
        let request = DerivedDetailedTileRequest(continent: 1, floor: 1, displayTile: TileIndex(zoom: 4, x: 21, y: 15), sourceZoom: 7)
        let task = Task { await provider.image(for: request) }
        try? await Task.sleep(for: .milliseconds(5))
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        let retry = await provider.image(for: request)
        XCTAssertNotNil(retry, "Cancelled recursion must release all generation/fetch permits")
    }

    private func makeTile() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.black.setFill(); context.fill(CGRect(x: 8, y: 8, width: 16, height: 32))
        }
    }
}

private actor TileFetchProbe {
    var count = 0
    var active = 0
    var peak = 0
    func begin(_ url: URL) { count += 1; active += 1; peak = max(peak, active) }
    func end() { active -= 1 }
}

final class DeterministicStatRepairTests: XCTestCase {
    private let warrior = GW2Character(name: "Source fixture (not Flashonder equipment)", race: "Human", gender: "Male", profession: "Warrior", level: 80, age: 1)
    private var rune: ItemMetadata {
        ItemMetadata(id: 24771, name: "Localized name is irrelevant", icon: nil, rarity: "Exotic", type: "UpgradeComponent", details: ItemDetails(type: "Rune"))
    }
    private var strength: SpecializationMetadata {
        SpecializationMetadata(id: 4, name: "Strength", profession: "Warrior", elite: false, icon: nil, background: nil,
                               minorTraits: [1446, 1448, 1453], majorTraits: [1449])
    }
    private func build(_ majors: [Int?], strengthActive: Bool = true) -> CharacterBuild {
        CharacterBuild(name: "Source test", profession: "Warrior", specializations: [BuildSpecialization(id: strengthActive ? 4 : 22, traits: majors)], skills: .empty)
    }
    private func trait(_ id: Int, facts: [TraitFact]) -> TraitMetadata {
        TraitMetadata(id: id, name: "Verified API trait \(id)", icon: nil, description: "", tier: nil, slot: nil, facts: facts)
    }
    private var pinnacle: TraitMetadata { trait(1453, facts: [TraitFact(type: "AttributeAdjust", target: "Power", value: 10), TraitFact(type: "Percent", percent: 5)]) }
    private var greatFortitude: TraitMetadata { trait(1449, facts: [TraitFact(type: "BuffConversion", target: "Vitality", source: "Power", percent: 10), TraitFact(type: "BuffConversion", target: "CritDamage", source: "Power", percent: 10)]) }

    func testMelandruCountsOneThroughSixAndNoOutgoingDuration() {
        let toughness = [25, 25, 75, 75, 175, 175]
        for count in 1...6 {
            let values = StaticRuneAttributeCatalog.attributes(for: rune, installedCount: count)
            XCTAssertEqual(values?["Toughness"], toughness[count - 1])
            XCTAssertEqual(values?["Vitality"] ?? 0, count > 1 ? 35 : 0)
            XCTAssertNil(values?["Expertise"])
            XCTAssertNil(values?["ConditionDuration"])
        }
        let impostor = ItemMetadata(id: 123, name: "Superior Rune of Melandru", icon: nil, rarity: "Exotic", type: "UpgradeComponent")
        XCTAssertNil(StaticRuneAttributeCatalog.attributes(for: impostor, installedCount: 6))
    }

    func testSixMelandruTerrestrialOnlyAndDefenseExcludesAquatic() {
        let slots = ["Helm", "Shoulders", "Coat", "Gloves", "Leggings", "Boots", "HelmAquatic"]
        var items = [rune.id: rune]
        let equipment = slots.enumerated().map { i, slot in
            items[i] = ItemMetadata(id: i, name: "Fixture \(slot)", icon: nil, rarity: "Exotic", type: "Armor", details: ItemDetails(defense: 100))
            return CharacterEquipment(itemID: i, slot: slot, upgrades: [rune.id], stats: SelectedItemStats(id: 1, attributes: ["Power": 1]))
        }
        let result = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: items)
        XCTAssertEqual(result.attributes["Toughness"]?.runes, 175)
        XCTAssertEqual(result.attributes["Vitality"]?.runes, 35)
        XCTAssertEqual(result.defense.total, 600)
        items[rune.id] = nil
        let offline = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: items)
        XCTAssertEqual(offline.attributes["Toughness"]?.runes, 175, "An ID-keyed rule must survive missing/localized item metadata")
        XCTAssertEqual(offline.attributes["Vitality"]?.runes, 35)
    }

    func testPinnacleRequiresActiveStrengthAndVerifiedFactNotMightPower() {
        let selected = CharacterEquipment(itemID: 1, slot: "Amulet", stats: SelectedItemStats(id: 1, attributes: ["Precision": 170]))
        let result = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [:], build: build([]), traits: [1453: pinnacle], specializations: [4: strength])
        XCTAssertEqual(result.total(for: "Power"), 1000)
        XCTAssertEqual(result.derived.criticalChanceBuildModifier, 5)
        XCTAssertEqual(result.derived.criticalChancePercent ?? 0, 18.095238, accuracy: 0.000001)
        let inactive = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [:], build: build([], strengthActive: false), traits: [1453: pinnacle], specializations: [4: strength])
        XCTAssertEqual(inactive.derived.criticalChanceBuildModifier, 0)
        let changed = trait(1453, facts: [TraitFact(type: "Percent", percent: 6)])
        XCTAssertEqual(StaticTraitModifierCatalog.criticalChance(in: changed), 0)
    }

    func testGreatFortitudeSelectionFlooringAndFlatTraitOrdering() {
        let selected = CharacterEquipment(itemID: 1, slot: "Amulet", stats: SelectedItemStats(id: 1, attributes: ["Power": 147]))
        let base = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [:], build: build([]), traits: [1449: greatFortitude], specializations: [4: strength])
        XCTAssertEqual(base.total(for: "Ferocity"), 0)
        let active = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [:], build: build([1449]), traits: [1449: greatFortitude], specializations: [4: strength])
        XCTAssertEqual(active.total(for: "Vitality"), 1114)
        XCTAssertEqual(active.total(for: "Ferocity"), 114)
        let wrongSpec = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [:], build: build([1449], strengthActive: false), traits: [1449: greatFortitude])
        XCTAssertEqual(wrongSpec.total(for: "Ferocity"), 0)
        // Existing flat Ferocity +150 must precede any Precision conversion;
        // conversion targets never feed another conversion in the same pass.
        let precisionFlat = trait(803, facts: [TraitFact(type: "AttributeAdjust", target: "Precision", value: 180)])
        let precisionConversion = trait(232, facts: [TraitFact(type: "BuffConversion", target: "CritDamage", source: "Precision", percent: 7)])
        let conditionConversion = trait(810, facts: [TraitFact(type: "BuffConversion", target: "ConditionDamage", source: "Precision", percent: 13)])
        let traits = [803: precisionFlat, 232: precisionConversion, 810: conditionConversion]
        let result = CharacterStatEngine.calculate(character: warrior, equipment: [], items: [:], build: build([810, 232, 803]), traits: traits)
        let reordered = CharacterStatEngine.calculate(character: warrior, equipment: [], items: [:], build: build([803, 810, 232]), traits: traits)
        XCTAssertEqual(result, reordered)
        XCTAssertEqual(result.total(for: "Ferocity"), 82)
        XCTAssertEqual(result.total(for: "ConditionDamage"), 153)
    }

    func testStructuredUpgradeCanonicalAliases() {
        let upgrade = ItemMetadata(id: 2, name: "Structured fixture", icon: nil, rarity: "Exotic", type: "UpgradeComponent",
            details: ItemDetails(infixUpgrade: InfixUpgrade(id: nil, attributes: [
                ItemAttribute(attribute: "CritDamage", modifier: 5), ItemAttribute(attribute: "ConditionDuration", modifier: 6),
                ItemAttribute(attribute: "BoonDuration", modifier: 7), ItemAttribute(attribute: "Healing", modifier: 8)
            ], buff: nil)))
        let equipment = CharacterEquipment(itemID: 1, slot: "Amulet", infusions: [2], upgrades: [2], stats: SelectedItemStats(id: 1, attributes: ["Power": 1]))
        let result = CharacterStatEngine.calculate(character: warrior, equipment: [equipment], items: [2: upgrade])
        for (key, expected) in ["Ferocity": 10, "Expertise": 12, "Concentration": 14, "HealingPower": 16] { XCTAssertEqual(result.total(for: key), expected) }
    }

    func testPublicAPIItemstatCoefficientsMatchActualItemNotObservedTotals() throws {
        // /v2/items/48073 and /v2/itemstats/161 verified 2026-10-01.
        let prefix = ItemStatMetadata(id: 161, name: "Berserker's", attributes: [
            .init(attribute: "Power", multiplier: 0.35, value: 0), .init(attribute: "Precision", multiplier: 0.25, value: 0), .init(attribute: "CritDamage", multiplier: 0.25, value: 0)
        ])
        XCTAssertEqual(prefix.attributes(adjustment: 403.326), ["Power": 141, "Precision": 101, "CritDamage": 101])
        let item = ItemMetadata(id: 48073, name: "Zojja's Breastplate", icon: nil, rarity: "Ascended", type: "Armor",
            details: ItemDetails(type: "Coat", defense: 381, statChoices: [161], attributeAdjustment: 403.326))
        let selected = CharacterEquipment(itemID: item.id, slot: "Coat", stats: SelectedItemStats(id: 161, attributes: nil))
        let result = CharacterStatEngine.calculate(character: warrior, equipment: [selected], items: [item.id: item], itemStats: [161: prefix])
        XCTAssertEqual(result.total(for: "Power"), 1141)
        XCTAssertEqual(result.total(for: "Precision"), 1101)
        XCTAssertEqual(result.total(for: "Ferocity"), 101)
        XCTAssertEqual(result.defense.total, 381)
        XCTAssertEqual(result.derived.health, 19212)
        let wrong = CharacterEquipment(itemID: item.id, slot: "Coat", stats: SelectedItemStats(id: 584, attributes: nil))
        let unsupported = CharacterStatEngine.calculate(character: warrior, equipment: [wrong], items: [item.id: item], itemStats: [161: prefix])
        XCTAssertEqual(unsupported.total(for: "Power"), 1000)
    }

    func testTargetPlanIdentitiesAndCachedCompleteVersusIncomplete() {
        let record = CharacterEquipment(itemID: 48073, slot: "Coat", upgrades: [24771, 999], stats: SelectedItemStats(id: 161, attributes: nil))
        let plan = StatSourceResolutionPlan(equipment: [record], items: [24771: rune], build: build([1449]), traits: [:], specializations: [:], weaponSet: "A")
        XCTAssertEqual(plan.itemIDs, [48073, 999])
        XCTAssertEqual(plan.itemStatIDs, [161])
        XCTAssertTrue(plan.specializationIDs.isEmpty)
        XCTAssertTrue(plan.traitIDs.isEmpty)
        XCTAssertTrue(plan.needsEquipmentAttributes)
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: [record], items: [24771: rune])
        let report = StatCoverageReport(stats: stats, build: nil, traits: [:], specializations: [:])
        XCTAssertTrue(report.missing.contains { $0.contains("Coat") && $0.contains("48073") && $0.contains("stats 161") })
        XCTAssertTrue(report.missing.contains { $0.contains("999") })
        XCTAssertTrue(report.missing.contains { $0.contains("Defense") })
        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.missing.contains { $0.contains("Food") })
    }

    func testOldCharacterSnapshotDecodesWithoutItemStats() throws {
        let detail = try JSONDecoder().decode(CharacterDetailData.self, from: Data(#"{"equipmentTabs":[],"buildTabs":[],"items":{},"skins":{},"specializations":{},"traits":{},"skills":{}}"#.utf8))
        XCTAssertNil(detail.itemStats)
    }

    func testIncompleteCachedStrengthMinorMetadataUsesVerifiedLocalMinorIdentity() {
        let old = SpecializationMetadata(id: 4, name: "Strength", profession: "Warrior", elite: false, icon: nil,
                                        background: nil, minorTraits: [], majorTraits: [1449])
        let plan = StatSourceResolutionPlan(equipment: [], items: [:], build: build([]), traits: [:], specializations: [4: old], weaponSet: "A")
        XCTAssertTrue(plan.specializationIDs.isEmpty)
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: [], items: [:], build: build([]), specializations: [4: old])
        let report = StatCoverageReport(stats: stats, build: build([]), traits: [:], specializations: [4: old])
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.localRules.resolved, 1)
        XCTAssertEqual(stats.derived.criticalChanceBuildModifier, 5)
    }
}
