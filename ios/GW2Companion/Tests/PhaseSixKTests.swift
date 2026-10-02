import XCTest
import UIKit
@testable import GW2Companion

final class OfflineStatClosureTests: XCTestCase {
    private let warrior = GW2Character(name: "Offline fixture", race: "Human", gender: "Male", profession: "Warrior", level: 80, age: 1)
    private let build = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 4, traits: [1444, 1449, 1437])], skills: .empty)
    private var equipment: [CharacterEquipment] {
        [CharacterEquipment(itemID: 1, slot: "Amulet", stats: SelectedItemStats(id: 1, attributes: ["Power": 873, "Vitality": 864, "Ferocity": 73]))]
    }
    private func metadata(_ facts: [TraitFact]) -> TraitMetadata {
        TraitMetadata(id: 1449, name: "Localised/cosmetic", icon: nil, description: "Not mechanical", tier: nil, slot: "Major", facts: facts)
    }

    func testGreatFortitudeExecutesOfflineWithMissingIncompleteAndIrrelevantFacts() throws {
        let variants: [TraitMetadata?] = [nil, metadata([]), metadata([TraitFact(type: "NoData")]),
            metadata([TraitFact(type: "BuffConversion", target: "Vitality", source: "Power", percent: 10)]),
            metadata([TraitFact(type: "AttributeAdjust", target: "HealingPower", value: 999)])]
        for trait in variants {
            let traits = trait.map { [1449: $0] } ?? [:]
            let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: build, traits: traits)
            XCTAssertEqual(stats.total(for: "Power"), 1873)
            XCTAssertEqual(stats.attributes["Vitality"]?.traits, 187)
            XCTAssertEqual(stats.attributes["Ferocity"]?.traits, 187)
            XCTAssertEqual(stats.total(for: "Ferocity"), 260)
            XCTAssertEqual(try XCTUnwrap(stats.derived.criticalDamagePercent), 167.333333, accuracy: 0.00001)
            XCTAssertEqual(stats.derived.criticalChanceBuildModifier, 5)
            let report = StatCoverageReport(stats: stats, build: build, traits: traits, specializations: [:])
            XCTAssertEqual(report.localRules.resolved, 2)
            XCTAssertEqual(report.localRules.total, 2)
            XCTAssertFalse(report.missing.contains { $0.contains("Trait 1449") || $0.contains("Trait 1453") })
            XCTAssertTrue(report.diagnostics.contains { $0.contains("API metadata differs from verified catalog") })
            let plan = StatSourceResolutionPlan(equipment: equipment, items: [:], build: build, traits: traits, specializations: [:], weaponSet: "A")
            XCTAssertFalse(plan.traitIDs.contains(1449))
            XCTAssertFalse(plan.specializationIDs.contains(4))
        }
    }

    func testRelevantMechanicalContradictionsSuppressWholeRuleAndRequestValidation() {
        for fact in [TraitFact(type: "BuffConversion", target: "Vitality", source: "Power", percent: 12),
                     TraitFact(type: "BuffConversion", target: "Ferocity", source: "Toughness", percent: 10),
                     TraitFact(type: "AttributeAdjust", target: "Vitality", value: 180)] {
            let trait = metadata([fact])
            XCTAssertEqual(StaticTraitModifierCatalog.validation(id: 1449, metadata: trait), .mechanicalMismatch)
            let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: build, traits: [1449: trait])
            XCTAssertEqual(stats.total(for: "Ferocity"), 73)
            XCTAssertEqual(stats.attributes["Vitality"]?.traits, 0)
            let report = StatCoverageReport(stats: stats, build: build, traits: [1449: trait], specializations: [:])
            XCTAssertTrue(report.missing.contains { $0.contains("mechanical fields") && $0.contains("rule suppressed") })
            XCTAssertTrue(StatSourceResolutionPlan(equipment: [], items: [:], build: build, traits: [1449: trait], specializations: [:], weaponSet: "A").traitIDs.contains(1449))
        }
    }

    func testOtherVersionedRulesExecuteWithoutAPIFactsAndSelectionIsRequired() {
        let other = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 1, traits: [325])], skills: .empty)
        XCTAssertEqual(CharacterStatEngine.calculate(character: warrior, equipment: [], items: [:], build: other).total(for: "ConditionDamage"), 180)
        XCTAssertEqual(CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:]).total(for: "Ferocity"), 73)
        let wrong = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 36, traits: [1449])], skills: .empty)
        XCTAssertEqual(CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: wrong).total(for: "Ferocity"), 73)
    }

    func testMechanicalTargetReplacementVersusExtraFactsAndOfflineMinorRepairPlan() {
        let vital = TraitFact(type: "BuffConversion", target: "Vitality", source: "Power", percent: 10)
        let fero = TraitFact(type: "BuffConversion", target: "CritDamage", source: "Power", percent: 10)
        let extra = TraitFact(type: "BuffConversion", target: "Toughness", source: "Power", percent: 10)
        XCTAssertEqual(StaticTraitModifierCatalog.validation(id: 1449, metadata: metadata([vital, extra])), .mechanicalMismatch)
        XCTAssertEqual(StaticTraitModifierCatalog.validation(id: 1449, metadata: metadata([extra, fero, vital])), .verified)
        XCTAssertEqual(StaticTraitModifierCatalog.validation(id: 1449, metadata: metadata([extra])), .metadataDiffers)
        XCTAssertEqual(StaticTraitModifierCatalog.validation(id: 1449, metadata: metadata([extra, extra])), .metadataDiffers, "Duplicate irrelevant facts are not a mechanical replacement pair")
        let pinnacle = TraitMetadata(id: 1453, name: "Changed", icon: nil, description: "", tier: nil, slot: "Minor", facts: [TraitFact(type: "Percent", percent: 7)])
        let plan = StatSourceResolutionPlan(equipment: [], items: [:], build: build, traits: [1453: pinnacle], specializations: [:], weaponSet: "A")
        XCTAssertTrue(plan.traitIDs.contains(1453))
    }

    func testMissingPublicMetadataIsNetworkRequiredAndCountsPartitionAllSources() {
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: [CharacterEquipment(itemID: 4633, slot: "Shoulders")], items: [:], build: build)
        let report = StatCoverageReport(stats: stats, build: build, traits: [:], specializations: [:])
        XCTAssertTrue(report.missing.contains { $0.contains("Defense") && $0.contains("Requires ArenaNet metadata refresh") })
        XCTAssertEqual(report.networkRequired, report.total - report.resolved)
        XCTAssertEqual(report.total, report.localRules.total + report.accountData.total + report.publicMetadata.total)
        XCTAssertEqual(report.resolved, report.localRules.resolved + report.accountData.resolved + report.publicMetadata.resolved)
        XCTAssertEqual(EquipmentStatSourceState.unresolved.rawValue, "Requires ArenaNet metadata refresh")
    }

    func testSelectedStatsMergeRetainsOnlySameTemplateSlotItemAndPersistsProvenance() throws {
        let known = CharacterEquipment(itemID: 30703, slot: "WeaponA1", upgrades: [1], stats: SelectedItemStats(id: 161, attributes: ["Power": 251]))
        func tab(_ record: CharacterEquipment, number: Int = 1) -> EquipmentTab {
            EquipmentTab(tab: number, name: "Fixture", isActive: number == 1, equipment: [record])
        }
        let old = [tab(known)]
        let retained = EquipmentStatInputResolver.mergingTabs([tab(CharacterEquipment(itemID: 30703, slot: "WeaponA1"))], cached: old)
        XCTAssertEqual(retained[0].equipment[0].stats, known.stats)
        XCTAssertTrue(retained[0].equipment[0].statsAreCached)
        XCTAssertEqual(retained[0].equipment[0].upgrades, [1])
        var detail = CharacterDetailData(); detail.equipmentTabs = retained
        let restored = try JSONDecoder().decode(CharacterDetailData.self, from: JSONEncoder().encode(detail))
        XCTAssertEqual(restored.equipmentTabs, retained)
        for fresh in [tab(CharacterEquipment(itemID: 30704, slot: "WeaponA1")),
                      tab(CharacterEquipment(itemID: 30703, slot: "WeaponA2")),
                      tab(CharacterEquipment(itemID: 30703, slot: "WeaponA1"), number: 2)] {
            let merged = EquipmentStatInputResolver.mergingTabs([fresh], cached: old)[0].equipment[0]
            XCTAssertNil(merged.stats)
            XCTAssertFalse(merged.statsAreCached)
        }
        let newPrefix = CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: 584, attributes: nil))
        XCTAssertNil(EquipmentStatInputResolver.mergingTabs([tab(newPrefix)], cached: old)[0].equipment[0].stats?.attributes)
        let authoritative = CharacterEquipment(itemID: 30703, slot: "WeaponA1", upgrades: [], stats: SelectedItemStats(id: 161, attributes: ["Power": 300]))
        let updated = EquipmentStatInputResolver.mergingTabs([tab(authoritative)], cached: retained)[0].equipment[0]
        XCTAssertEqual(updated.stats?.attributes?["Power"], 300)
        XCTAssertFalse(updated.statsAreCached)
        XCTAssertEqual(updated.upgrades, [])
        let partialFields = CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: nil, attributes: ["Power": 300]))
        let nested = EquipmentStatInputResolver.mergingTabs([tab(partialFields)], cached: old)[0].equipment[0]
        XCTAssertEqual(nested.stats?.id, 161)
        XCTAssertEqual(nested.stats?.attributes?["Power"], 300)
        XCTAssertTrue(nested.statsAreCached, "Only the omitted ID is retained; new attributes remain authoritative")
    }

    func testFreshAuthenticatedFullEquipmentCanReplaceCachedPrefixWithoutCrossTabLeak() {
        var cached = CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: ["Power": 251]))
        cached.statsAreCached = true
        let tabs = [EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [cached]), EquipmentTab(tab: 2, name: "Two", isActive: false, equipment: [cached])]
        var fresh = CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: 584, attributes: ["Vitality": 200]))
        fresh.tabs = [1]
        let hydrated = EquipmentStatInputResolver.hydratedTabs(tabs, from: CharacterEquipmentResponse(equipment: [fresh]))
        XCTAssertEqual(hydrated[0].equipment[0].stats?.id, 584)
        XCTAssertNil(hydrated[0].equipment[0].stats?.attributes?["Power"])
        XCTAssertFalse(hydrated[0].equipment[0].statsAreCached)
        XCTAssertEqual(hydrated[1].equipment[0].stats?.id, 161)
    }
}

@MainActor
final class EarlyMapPrefetchTests: XCTestCase {
    private func request(_ zoom: Int, count: Int = 1) -> MapRasterLayerRequest {
        MapRasterLayerRequest(continent: 1, floor: 1, tiles: (0..<count).map { TileIndex(zoom: zoom, x: $0, y: 0) }, detailed: true)
    }
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
    }
    func testEarlyDirectionAwareIntentNeverChangesCurrentFrameOrPromotionThreshold() {
        var policy = MapSourcePrefetchPolicy()
        policy.update(from: 5, to: 4.9, currentSource: 5)
        XCTAssertEqual(policy.nextSource, 4)
        XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: 4.9, current: 5, maximum: 7), 5)
        let old = request(5)
        var handoff = MapRasterLayerHandoff(); handoff.begin(old)
        XCTAssertTrue(handoff.accept(MapRasterLayerFrame(request: old, images: [old.tiles[0]: image()])))
        handoff.finish(old)
        let transform = MapViewportTransform(center: ContinentPoint(x: 44615.5, y: 29863.7), zoom: 5, magnification: 1, dragOffset: .zero, size: CGSize(width: 390, height: 844), cameraZoom: 4.9)
        let prepared = policy.request(transform: transform, currentSource: 5, continent: 1, floor: 1)
        XCTAssertNotNil(prepared)
        XCTAssertEqual(handoff.active?.request, old)
        XCTAssertEqual(handoff.pending, old)
        XCTAssertEqual(handoff.activeOpacity(progress: 0), 1)
        for camera in [4.895, 4.905, 4.89, 4.91, 4.6, 4.5] {
            policy.update(from: 4.9, to: camera, currentSource: 5)
            XCTAssertEqual(policy.nextSource, 4)
            XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: camera, current: 5, maximum: 7), 5)
        }
        XCTAssertEqual(ContinuousMapCamera.sourceZoom(cameraZoom: 4.349, current: 5, maximum: 7), 4)
        policy.update(from: 4.5, to: 4.65, currentSource: 5)
        XCTAssertNil(policy.nextSource, "Reversal cancels outward intent before any inward threshold")
        policy.update(from: 4.65, to: 5.1, currentSource: 5)
        XCTAssertEqual(policy.nextSource, 6)
    }

    func testCancelledPrefetchStopsBeforeNextParentAndBudgetRejectsColdOversize() async throws {
        let cache = PrefetchTestCache(image: image(), delay: .milliseconds(450))
        let task = Task { await MapRasterLayerLoader.prefetch(request(4, count: 3), derivedLoader: { await cache.load($0) }) }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel(); await task.value
        let starts = await cache.starts
        XCTAssertEqual(starts, 1)
        let before = await cache.starts
        await MapRasterLayerLoader.prefetch(request(4, count: 49), derivedLoader: { await cache.load($0) })
        let after = await cache.starts
        XCTAssertEqual(after, before)
        XCTAssertFalse(request(4, count: 49).permitsDetailed)
        XCTAssertLessThanOrEqual(MapRasterLayerLoader.maximumConcurrentParents, 2)
    }

    func testWarmCacheShortensSimulatedPostThresholdSoftInterval() async throws {
        let target = request(4)
        let cache = PrefetchTestCache(image: image(), delay: .milliseconds(450))
        let clock = ContinuousClock()
        let coldStart = clock.now
        let cold = await MapRasterLayerLoader.frame(for: target, derivedLoader: { await cache.load($0) })
        let coldDuration = coldStart.duration(to: clock.now)
        XCTAssertNotNil(cold)
        await cache.clear()
        let warming = Task { await MapRasterLayerLoader.prefetch(target, derivedLoader: { await cache.load($0) }) }
        // 4.90 → 4.35 at one camera-level/second gives 550 ms lead time.
        try await Task.sleep(for: .milliseconds(550)); await warming.value
        let warmStart = clock.now
        let warm = await MapRasterLayerLoader.frame(for: target, derivedLoader: { await cache.load($0) })
        let warmDuration = warmStart.duration(to: clock.now)
        XCTAssertNotNil(warm)
        XCTAssertGreaterThan(coldDuration, .milliseconds(400))
        XCTAssertLessThan(warmDuration, .milliseconds(100))
        print("Phase 6K simulated post-threshold softness: cold \(coldDuration), early-prefetched \(warmDuration); one parent, 450 ms cold latency, 550 ms lead")
    }

    func testSpeculationSharesTwoParentBudgetAndDoesNotQueueAheadOfVisibleWork() async throws {
        let cache = PrefetchTestCache(image: image(), delay: .milliseconds(150))
        let warm = Task { await MapRasterLayerLoader.prefetch(request(4, count: 4), derivedLoader: { await cache.load($0) }) }
        try await Task.sleep(for: .milliseconds(30))
        let visible = await MapRasterLayerLoader.frame(for: request(5, count: 3), derivedLoader: { await cache.load($0) })
        XCTAssertNotNil(visible)
        warm.cancel(); await warm.value
        let maximum = await cache.maximumConcurrent
        XCTAssertLessThanOrEqual(maximum, 2)
        XCTAssertEqual(maximum, 2)
    }
}

private actor PrefetchTestCache {
    let image: UIImage
    let delay: Duration
    private var ready = Set<DerivedDetailedTileRequest>()
    private(set) var starts = 0
    private var concurrent = 0
    private(set) var maximumConcurrent = 0
    init(image: UIImage, delay: Duration) { self.image = image; self.delay = delay }
    func clear() { ready.removeAll() }
    func load(_ request: DerivedDetailedTileRequest) async -> UIImage? {
        if ready.contains(request) { return image }
        starts += 1; concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        do { try await Task.sleep(for: delay) } catch { return nil }
        guard !Task.isCancelled else { return nil }
        ready.insert(request)
        return image
    }
}
