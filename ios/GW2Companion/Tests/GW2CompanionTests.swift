import Combine
import os
import SwiftUI
import UIKit
import XCTest
@testable import GW2Companion

final class TelemetryDecodingTests: XCTestCase {
    func testDecodesV1AndIgnoresFutureFields() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "telemetry.v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(TelemetryEnvelope.self, from: data)
        XCTAssertEqual(value.character?.name, "Example Character")
        XCTAssertEqual(value.map?.id, 15)
        XCTAssertEqual(value.player?.continentX, 11000.2)
    }

    @MainActor
    func testRemoteComputerClockDoesNotMakeFreshlyReceivedTelemetryStale() {
        let telemetry = TelemetryEnvelope(
            protocolVersion: 1, timestampUnixMs: 1, connected: true, uiTick: 10,
            positionAvailable: true, character: nil, map: nil, player: nil, camera: nil,
            ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
            mount: MountTelemetry(index: 0), statusMessage: nil)

        XCTAssertEqual(TelemetryStore.state(for: telemetry), .connectedLive)
    }
}

final class TokenInfoTests: XCTestCase {
    func testPermissionParsing() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tokeninfo", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let info = try JSONDecoder().decode(TokenInfo.self, from: data)
        XCTAssertTrue(info.permissions.contains("inventories"))
        XCTAssertFalse(info.permissions.contains("tradingpost"))
    }
}

final class CoordinateTransformerTests: XCTestCase {
    func testMapAndContinentRoundTripWithYAxisInversion() throws {
        let metadata = GW2MapMetadata(id: 15, name: "Test", continentId: 1, defaultFloor: 1,
                                      mapRect: [[0, 0], [1_000, 2_000]], continentRect: [[10_000, 12_000], [12_000, 16_000]])
        let transformer = GW2CoordinateTransformer(metadata: metadata)
        let map = try transformer.mapPoint(from: ContinentPoint(x: 10_500, y: 13_000))
        XCTAssertEqual(map.x, 250, accuracy: 0.001)
        XCTAssertEqual(map.y, 1_500, accuracy: 0.001)
        let roundTrip = try transformer.continentPoint(from: map)
        XCTAssertEqual(roundTrip.x, 10_500, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, 13_000, accuracy: 0.001)
    }

    func testTileCoordinateAtReferenceZoom() {
        let metadata = GW2MapMetadata(id: 15, name: "Test", continentId: 1, defaultFloor: 1,
                                      mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        let tile = GW2CoordinateTransformer(metadata: metadata).tilePoint(from: ContinentPoint(x: 513, y: 770), zoom: 7)
        XCTAssertEqual(tile.tileX, 2)
        XCTAssertEqual(tile.tileY, 3)
        XCTAssertEqual(tile.pixelX, 1)
        XCTAssertEqual(tile.pixelY, 2)
    }
}

final class GatheringTests: XCTestCase {
    private let nodes = [
        GatheringNode(id: "near", mapId: 15, continentX: 12, continentY: 10, category: .ore, name: "Near", reliability: .fixed, source: nil, notes: nil),
        GatheringNode(id: "far", mapId: 15, continentX: 50, continentY: 50, category: .wood, name: "Far", reliability: .possible, source: nil, notes: nil),
        GatheringNode(id: "other", mapId: 50, continentX: 10, continentY: 10, category: .plant, name: "Other", reliability: .fixed, source: nil, notes: nil)
    ]

    func testNearestNode() {
        XCTAssertEqual(GatheringGeometry.nearest(to: ContinentPoint(x: 10, y: 10), among: Array(nodes.prefix(2)))?.id, "near")
    }

    func testVisitedDetectionUsesRadius() {
        let visited = GatheringGeometry.nodesWithin(radius: 3, of: ContinentPoint(x: 10, y: 10), among: nodes)
        XCTAssertEqual(visited, ["near", "other"])
    }

    func testFilteringByMapAndCategory() {
        let filtered = nodes.filter { $0.mapId == 15 && $0.category == .ore }
        XCTAssertEqual(filtered.map(\.id), ["near"])
    }
}

final class MapMarkerSceneTests: XCTestCase {
    private let transform = MapViewportTransform(
        center: ContinentPoint(x: 1_000, y: 1_000), zoom: 7, magnification: 1.6,
        dragOffset: CGSize(width: 31, height: -18), size: CGSize(width: 390, height: 844))

    func testViewportTransformRoundTripsWithPanAndMagnification() {
        let point = ContinentPoint(x: 1_127.5, y: 812.25)
        let roundTrip = transform.continentPoint(for: transform.screenPosition(for: point))
        XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.0001)
    }

    func testViewportQueryIncludesOnlyVisibleMarkers() {
        let visible = gathering(id: "visible", x: 1_000, y: 1_000)
        let offscreen = gathering(id: "offscreen", x: 10_000, y: 10_000)
        let scene = MapMarkerScene(gathering: [visible, offscreen])

        XCTAssertEqual(scene.visibleMarkers(in: transform, marginPoints: 0).map(\.id), ["gathering:visible"])
    }

    func testHitTestingUsesGestureTransformAndFortyFourPointTarget() {
        let node = gathering(id: "node", x: 1_100, y: 900)
        let scene = MapMarkerScene(gathering: [node])
        let position = transform.screenPosition(for: ContinentPoint(x: 1_100, y: 900))

        XCTAssertEqual(scene.marker(at: CGPoint(x: position.x + 21, y: position.y), in: transform)?.id, "gathering:node")
        XCTAssertNil(scene.marker(at: CGPoint(x: position.x + 23, y: position.y), in: transform))
    }

    func testClosestMarkerWinsAndGatheringBreaksOverlapTie() {
        let landmark = MapLandmark(
            id: "waypoint", kind: .waypoint, name: "Waypoint",
            coordinate: ContinentPoint(x: 1_000, y: 1_000), chatLink: nil)
        let gathering = gathering(id: "ore", x: 1_000, y: 1_000)
        let nearby = self.gathering(id: "nearby", x: 1_006, y: 1_000)
        let scene = MapMarkerScene(landmarks: [landmark], gathering: [gathering, nearby])
        let position = transform.screenPosition(for: landmark.coordinate)

        XCTAssertEqual(scene.marker(at: position, in: transform)?.id, "gathering:ore")
    }

    private func gathering(id: String, x: Double, y: Double, category: GatheringCategory = .ore) -> GatheringNode {
        GatheringNode(
            id: id, mapId: 73, continentX: x, continentY: y, category: category,
            name: id, reliability: .possible, source: nil, notes: nil)
    }
}

final class MapIconDataCacheTests: XCTestCase {
    func testConcurrentRequestsAreDeduplicatedAndPersistedToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GW2CompanionIconTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = AsyncCounter()
        let expected = Data([1, 2, 3, 4])
        let url = try XCTUnwrap(URL(string: "https://example.invalid/icon.png"))
        let cache = MapIconDataCache(directory: directory) { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(30))
            return expected
        }

        async let first = cache.data(for: url)
        async let second = cache.data(for: url)
        let values = try await (first, second)
        XCTAssertEqual(values.0, expected)
        XCTAssertEqual(values.1, expected)
        let fetchCount = await counter.value
        XCTAssertEqual(fetchCount, 1)

        let diskOnly = MapIconDataCache(directory: directory) { _ in throw URLError(.notConnectedToInternet) }
        let persisted = try await diskOnly.data(for: url)
        XCTAssertEqual(persisted, expected)
    }
}

private actor AsyncCounter {
    private var count = 0
    func increment() { count += 1 }
    var value: Int { count }
}

final class TelemetryBufferTests: XCTestCase {
    func testLatestValueBufferDropsObsoleteTelemetry() async throws {
        let stream = TelemetryStreamBuffer.latest { continuation in
            continuation.yield(Self.envelope(tick: 1))
            continuation.yield(Self.envelope(tick: 2))
            continuation.yield(Self.envelope(tick: 3))
            continuation.finish()
        }
        var ticks: [UInt32] = []
        for try await value in stream { ticks.append(value.uiTick) }
        XCTAssertEqual(ticks, [3])
    }

    private static func envelope(tick: UInt32) -> TelemetryEnvelope {
        TelemetryEnvelope(
            protocolVersion: 1, timestampUnixMs: 0, connected: true, uiTick: tick,
            positionAvailable: true, character: nil, map: nil, player: nil, camera: nil,
            ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
            mount: MountTelemetry(index: 0), statusMessage: nil)
    }
}

final class APIBatchingTests: XCTestCase {
    func testCharacterInventoryEnvelopeDecoding() throws {
        let data = Data(#"{"bags":[{"id":20,"size":20,"inventory":[{"id":19697,"count":12},null]},null]}"#.utf8)
        let response = try JSONDecoder().decode(CharacterInventoryResponse.self, from: data)
        XCTAssertEqual(response.bags.compactMap { $0 }.first?.inventory?.compactMap { $0 }.first?.count, 12)
    }

    func testIDsAreDeduplicatedAndSorted() {
        XCTAssertEqual(GW2APIClient.batchedIDs([9, 2, 9, 3, 2]), ["2", "3", "9"])
    }

    func testChunksRespectTwoHundredItemLimit() {
        let chunks = GW2APIClient.chunks(of: Array(0..<401), size: 200)
        XCTAssertEqual(chunks.map(\.count), [200, 200, 1])
    }
}

final class CoinAmountTests: XCTestCase {
    func testCopperBoundaries() {
        let cases: [(Int, CoinAmount)] = [
            (0, CoinAmount(gold: 0, silver: 0, copper: 0)),
            (99, CoinAmount(gold: 0, silver: 0, copper: 99)),
            (100, CoinAmount(gold: 0, silver: 1, copper: 0)),
            (9_999, CoinAmount(gold: 0, silver: 99, copper: 99)),
            (10_000, CoinAmount(gold: 1, silver: 0, copper: 0)),
            (526_532, CoinAmount(gold: 52, silver: 65, copper: 32))
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(CoinAmount(copperValue: raw), expected)
        }
    }
}

final class PhaseTwoAccountDomainTests: XCTestCase {
    func testCurrentCharacterMatcherPrefersExactAndAllowsUniqueCaseInsensitiveMatch() throws {
        let characters = try fixture([GW2Character].self, name: "characters")
        XCTAssertEqual(CurrentCharacterMatcher.match(liveName: "Andrea", characters: characters)?.name, "Andrea")
        XCTAssertEqual(CurrentCharacterMatcher.match(liveName: "  andrea  ", characters: characters)?.name, "Andrea")
        XCTAssertNil(CurrentCharacterMatcher.match(liveName: "Unknown", characters: characters))
    }

    func testAccountSummaryAggregatesCharacters() throws {
        let characters = try fixture([GW2Character].self, name: "characters")
        let summary = AccountSummary(characters: characters, holdings: [])
        XCTAssertEqual(summary.characterCount, 2)
        XCTAssertEqual(summary.maxLevelCharacterCount, 1)
        XCTAssertEqual(summary.totalPlaytime, 6_004_800)
        XCTAssertEqual(summary.totalDeaths, 95)
    }

    func testGlobalHoldingsAggregateEveryAccountLocation() throws {
        let character = try slots(#"[{"id":19697,"count":173},{"id":99,"count":1}]"#)
        let bank = try slots(#"[{"id":19697,"count":211}]"#)
        let shared = try slots(#"[{"id":19697,"count":100}]"#)
        let materials = try slots(#"[{"id":19697,"count":250}]"#)
        let holdings = AccountHoldingAggregator.aggregate([
            (.character("Andrea"), character), (.bank, bank),
            (.sharedInventory, shared), (.materialStorage, materials)
        ])
        let mithril = try XCTUnwrap(holdings.first { $0.itemID == 19697 })
        XCTAssertEqual(mithril.totalQuantity, 734)
        XCTAssertEqual(mithril.locations.count, 4)
        XCTAssertEqual(mithril.locations.first { $0.location == .materialStorage }?.quantity, 250)
    }

    func testHoldingSearchIsCaseInsensitiveAndSortsLocally() throws {
        let holdings = AccountHoldingAggregator.aggregate([
            (.bank, try slots(#"[{"id":1,"count":4},{"id":2,"count":25}]"#))
        ])
        let items = try JSONDecoder().decode([ItemMetadata].self, from: Data(#"[{"id":1,"name":"Mithril Ore","icon":null,"rarity":"Basic"},{"id":2,"name":"Elder Wood Log","icon":null,"rarity":"Basic"}]"#.utf8))
        let metadata = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertEqual(HoldingSearch.results(holdings: holdings, metadata: metadata, query: "mItHrIl", sort: .name).map(\.item.name), ["Mithril Ore"])
        XCTAssertEqual(HoldingSearch.results(holdings: holdings, metadata: metadata, query: "", sort: .quantity).first?.item.name, "Elder Wood Log")
    }

    func testCharacterStatEngineAddsEquipmentUpgradeAndInfusionAttributes() throws {
        let equipment = try JSONDecoder().decode([CharacterEquipment].self, from: Data(#"[{"id":101,"slot":"WeaponA1","stats":{"id":1,"attributes":{"Power":125}},"upgrades":[201],"infusions":[301]}]"#.utf8))
        let items = try JSONDecoder().decode([ItemMetadata].self, from: Data(#"""
        [
          {"id":101,"name":"Sword","icon":null,"rarity":"Ascended","details":{"infix_upgrade":{"id":1,"attributes":[{"attribute":"Power","modifier":125}],"buff":null}}},
          {"id":201,"name":"Rune","icon":null,"rarity":"Exotic","details":{"infix_upgrade":{"id":2,"attributes":[{"attribute":"Precision","modifier":20}],"buff":null}}},
          {"id":301,"name":"Infusion","icon":null,"rarity":"Fine","details":{"infix_upgrade":{"id":3,"attributes":[{"attribute":"Power","modifier":5}],"buff":null}}}
        ]
        """#.utf8))
        let metadata = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let result = CharacterStatEngine.equipmentAttributes(equipment: equipment, items: metadata, upgrades: metadata)
        XCTAssertEqual(result.attributes["Power"], 130)
        XCTAssertEqual(result.attributes["Precision"], 20)
    }

    func testLevel80DerivedStatsUseVerifiedFormulasAndDiscloseLowerLevels() {
        let level80 = GW2Character(
            name: "Andrea", race: "Human", gender: "Female", profession: "Warrior", level: 80, age: 1)
        let equipment = [
            CharacterEquipment(
                itemID: 101, slot: "Helm",
                stats: SelectedItemStats(id: 1, attributes: ["Precision": 147, "Toughness": 200, "Vitality": 50]))
        ]
        let stats = CharacterStatEngine.calculate(character: level80, equipment: equipment, items: [:])
        XCTAssertEqual(stats.total(for: "Power"), 1_000)
        XCTAssertEqual(stats.total(for: "Precision"), 1_147)
        XCTAssertEqual(stats.derived.availableForLevel, true)
        XCTAssertEqual(stats.derived.criticalChancePercent ?? 0, 5 + 147.0 / 21.0, accuracy: 0.01)
        XCTAssertEqual(stats.derived.armor, 1_200)
        XCTAssertEqual(stats.derived.health, 9_212 + 1_050 * 10)

        let low = GW2Character(
            name: "Sylvari Ranger", race: "Sylvari", gender: "Male", profession: "Ranger", level: 35, age: 1)
        let lowStats = CharacterStatEngine.calculate(character: low, equipment: [], items: [:])
        XCTAssertEqual(lowStats.attributes["Power"]?.base ?? 0, 0)
        XCTAssertFalse(lowStats.derived.availableForLevel)
        XCTAssertNil(lowStats.derived.criticalChancePercent)
        XCTAssertNil(lowStats.derived.health)
    }

    func testHighPriorityAPIRequestsAreDequeuedBeforeNormalBulk() async throws {
        let scheduler = APIRequestScheduler(maxConcurrent: 1)
        let order = OSAllocatedUnfairLock(initialState: [String]())
        async let runningNormal: Void = scheduler.perform(priority: .normal) {
            try await Task.sleep(for: .milliseconds(40))
            order.withLock { $0.append("running-normal") }
        }
        try await Task.sleep(for: .milliseconds(8))
        async let queuedHigh: Void = scheduler.perform(priority: .high) {
            order.withLock { $0.append("high") }
        }
        async let queuedNormal: Void = scheduler.perform(priority: .normal) {
            order.withLock { $0.append("queued-normal") }
        }
        _ = try await (runningNormal, queuedHigh, queuedNormal)
        XCTAssertEqual(order.withLock { $0 }, ["running-normal", "high", "queued-normal"])
    }

    func testCachedCharacterDetailsStayLabeledSavedNotCurrent() throws {
        var detail = CharacterDetailData()
        detail.equipmentTabs = [
            EquipmentTab(tab: 1, name: "Raid DPS", isActive: true, equipment: [])
        ]
        detail.source = .live
        detail.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let encoded = try JSONEncoder().encode(detail)
        var decoded = try JSONDecoder().decode(CharacterDetailData.self, from: encoded)
        decoded.source = .cached
        XCTAssertEqual(decoded.source, .cached)
        XCTAssertEqual(decoded.updatedAt, detail.updatedAt)
        XCTAssertFalse(decoded.equipmentTabs.isEmpty)
    }

    func testLimitedPermissionsRemainIndependent() throws {
        let info = try fixture(TokenInfo.self, name: "tokeninfo-limited")
        let permissions = PermissionSet(info.permissions)
        XCTAssertTrue(permissions.contains(.account))
        XCTAssertTrue(permissions.contains(.characters))
        XCTAssertFalse(permissions.contains(.inventories))
        XCTAssertFalse(permissions.contains(.wallet))
    }

    func testRealisticCharacterEquipmentBuildInventoryAndWalletFixturesDecode() throws {
        XCTAssertEqual(try fixture([GW2Character].self, name: "characters").first?.crafting?.first?.rating, 500)
        XCTAssertEqual(try fixture([EquipmentTab].self, name: "equipment-tabs").first?.equipment.first?.stats?.attributes?["Power"], 125)
        XCTAssertEqual(try fixture([BuildTab].self, name: "build-tabs").first?.build.skills.pve?.utilities.count, 3)
        XCTAssertEqual(try fixture(CharacterInventoryResponse.self, name: "inventory").bags.first??.size, 5)
        XCTAssertEqual(try fixture([WalletEntry].self, name: "wallet").first?.value, 3_824_100)
        XCTAssertEqual(try fixture(GW2Account.self, name: "account").world, 2203)
        let itemRarities = Set(try fixture([ItemMetadata].self, name: "items").map(\.rarity))
        XCTAssertEqual(itemRarities, ["Ascended", "Exotic", "Legendary", "Fine"])
    }

    private func fixture<Value: Decodable>(_ type: Value.Type, name: String) throws -> Value {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func slots(_ json: String) throws -> [InventorySlot] {
        try JSONDecoder().decode([InventorySlot].self, from: Data(json.utf8))
    }
}

final class MetadataDiskCacheTests: XCTestCase {
    func testCachedMetadataRemainsAvailableWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GW2MetadataTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = MetadataDiskCache(directory: directory)
        let value = [42: "cached item"]
        await first.save(value, named: "items")

        let relaunched = MetadataDiskCache(directory: directory)
        let restored = await relaunched.load([Int: String].self, named: "items")
        XCTAssertEqual(restored, value)
    }
}

final class MapLandmarkTests: XCTestCase {
    func testDecodesOfficialFloorMarkerTypes() throws {
        let data = Data(#"""
        {
          "id":15,
          "points_of_interest":{
            "1":{"name":"Village Waypoint","type":"waypoint","floor":1,"coord":[10,20],"id":1,"chat_link":"[&A=]"},
            "2":{"name":"Old Mill","type":"landmark","floor":1,"coord":[30,40],"id":2,"chat_link":"[&B=]"},
            "3":{"name":"","type":"vista","floor":1,"coord":[50,60],"id":3,"chat_link":"[&C=]"}
          },
          "tasks":{"4":{"objective":"Help the villagers","level":5,"coord":[70,80],"bounds":[],"id":4,"chat_link":"[&D=]"}},
          "skill_challenges":[{"coord":[90,100],"id":"0-5"},{"coord":[110,120]}]
        }
        """#.utf8)
        let map = try JSONDecoder().decode(GW2FloorMap.self, from: data)
        let landmarks = map.landmarks()

        XCTAssertEqual(Set(landmarks.map(\.kind)), Set(MapLandmarkKind.allCases))
        XCTAssertEqual(landmarks.filter { $0.kind == .heroChallenge }.count, 2)
        XCTAssertEqual(landmarks.first(where: { $0.kind == .vista })?.name, "Vista")
        XCTAssertEqual(landmarks.first(where: { $0.kind == .waypoint })?.chatLink, "[&A=]")
    }

    func testConvertsTacOWorldMetersToContinentCoordinates() throws {
        let metadata = GW2MapMetadata(
            id: 15, name: "Queensdale", continentId: 1, defaultFloor: 1,
            mapRect: [[-43_008, -27_648], [43_008, 30_720]],
            continentRect: [[9_856, 11_648], [13_440, 14_080]])
        let point = try GW2CoordinateTransformer(metadata: metadata).continentPoint(worldX: -193.448, worldZ: 324.628)

        XCTAssertEqual(point.x, 11_330.664, accuracy: 0.01)
        XCTAssertEqual(point.y, 13_460.526, accuracy: 0.01)
    }
}

@MainActor
final class MapStoreTests: XCTestCase {
    func testEmptyLayerSelectionsArePreserved() {
        let suite = "GW2CompanionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([], forKey: "visibleGatheringCategories")
        defaults.set([], forKey: "visibleGatheringReliabilities")
        defaults.set([], forKey: "visibleMapLandmarkKinds")

        XCTAssertTrue(GatheringStore(defaults: defaults).categories.isEmpty)
        XCTAssertTrue(GatheringStore(defaults: defaults).reliabilities.isEmpty)
        XCTAssertTrue(MapOverlayStore(defaults: defaults).visibleKinds.isEmpty)
    }

    func testOlderMapLoadCannotReplaceNewerMap() async {
        let store = MapOverlayStore(defaults: UserDefaults(suiteName: "GW2CompanionTests-\(UUID().uuidString)")!)
        let provider = DelayedLandmarkProvider()
        let old = GW2MapMetadata(id: 1, name: "Old", continentId: 1, defaultFloor: 1,
                                mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        let new = GW2MapMetadata(id: 2, name: "New", continentId: 1, defaultFloor: 1,
                                mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])

        let olderTask = Task { await store.load(provider: provider, metadata: old) }
        try? await Task.sleep(for: .milliseconds(10))
        await store.load(provider: provider, metadata: new)
        await olderTask.value

        XCTAssertEqual(store.landmarks.map(\.name), ["Map 2"])
    }

    func testGatheringFiltersAreCachedAndMovementDoesNotRebuildScene() async {
        let suite = "GW2CompanionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let nodes = [
            GatheringNode(id: "ore", mapId: 73, continentX: 10, continentY: 10, category: .ore, name: "Ore", reliability: .fixed, source: nil, notes: nil),
            GatheringNode(id: "wood", mapId: 73, continentX: 100, continentY: 100, category: .wood, name: "Wood", reliability: .fixed, source: nil, notes: nil)
        ]
        let provider = FixedGatheringProvider(nodes: nodes)
        let store = GatheringStore(provider: provider, sampleProvider: provider, defaults: defaults)
        let metadata = GW2MapMetadata(
            id: 73, name: "Dense", continentId: 1, defaultFloor: 1,
            mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        await store.load(mapId: 73, metadata: metadata, simulation: false)
        XCTAssertEqual(store.visibleNodes.count, 2)

        store.categories = []
        XCTAssertTrue(store.visibleNodes.isEmpty)
        let emptyRevision = store.sceneRevision
        var visitedUpdates = 0
        let observation = store.$visited.dropFirst().sink { _ in visitedUpdates += 1 }
        store.updatePlayer(ContinentPoint(x: 10, y: 10))
        store.updatePlayer(ContinentPoint(x: 10, y: 10))
        XCTAssertEqual(store.sceneRevision, emptyRevision)
        XCTAssertEqual(visitedUpdates, 1)
        withExtendedLifetime(observation) {}
    }
}

private struct FixedGatheringProvider: MarkerDataProvider {
    let nodes: [GatheringNode]
    func markers(for mapId: Int, metadata: GW2MapMetadata) async throws -> [GatheringNode] {
        nodes.filter { $0.mapId == mapId }
    }
    func coveredMapIDs() async throws -> Set<Int> { Set(nodes.map(\.mapId)) }
}

final class MapScenePerformanceTests: XCTestCase {
    private static let landmarks = (0..<80).map { index in
        MapLandmark(
            id: "landmark-\(index)", kind: MapLandmarkKind.allCases[index % MapLandmarkKind.allCases.count],
            name: "Landmark \(index)",
            coordinate: ContinentPoint(x: 10_000 + Double(index % 16) * 80, y: 10_000 + Double(index / 16) * 80),
            chatLink: nil)
    }
    private static let gathering = (0..<321).map { index in
        GatheringNode(
            id: "gathering-\(index)", mapId: 73,
            continentX: 9_500 + Double(index % 21) * 95,
            continentY: 9_500 + Double(index / 21) * 95,
            category: GatheringCategory.allCases[index % GatheringCategory.allCases.count],
            name: "Node \(index)", reliability: .possible, source: nil, notes: nil)
    }

    func testBenchmarkGatheringDisabled() { benchmark(gathering: []) }
    func testBenchmarkMiningOnly() { benchmark(gathering: Self.gathering.filter { $0.category == .ore }) }
    func testBenchmarkAllGathering() { benchmark(gathering: Self.gathering) }

    private func benchmark(gathering: [GatheringNode]) {
        let scene = MapMarkerScene(landmarks: Self.landmarks, gathering: gathering)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var visibleCount = 0
            for frame in 0..<1_000 {
                let transform = MapViewportTransform(
                    center: ContinentPoint(x: 10_350 + Double(frame % 40), y: 10_250),
                    zoom: 7, magnification: 1, dragOffset: .zero,
                    size: CGSize(width: 390, height: 844))
                visibleCount += scene.visibleMarkers(in: transform).count
            }
            XCTAssertGreaterThan(visibleCount, 0)
        }
    }
}

@MainActor
final class MapCanvasPerformanceTests: XCTestCase {
    private static let landmarks = (0..<80).map { index in
        MapLandmark(
            id: "canvas-landmark-\(index)", kind: MapLandmarkKind.allCases[index % MapLandmarkKind.allCases.count],
            name: "Landmark \(index)",
            coordinate: ContinentPoint(x: 10_000 + Double(index % 16) * 80, y: 10_000 + Double(index / 16) * 80),
            chatLink: nil)
    }
    private static let gathering = (0..<321).map { index in
        GatheringNode(
            id: "canvas-gathering-\(index)", mapId: 73,
            continentX: 9_500 + Double(index % 21) * 95,
            continentY: 9_500 + Double(index / 21) * 95,
            category: GatheringCategory.allCases[index % GatheringCategory.allCases.count],
            name: "Node \(index)", reliability: .possible, source: nil, notes: nil)
    }

    func testCanvasBenchmarkGatheringDisabled() { benchmark(gathering: []) }
    func testCanvasBenchmarkMiningOnly() { benchmark(gathering: Self.gathering.filter { $0.category == .ore }) }
    func testCanvasBenchmarkAllGathering() { benchmark(gathering: Self.gathering) }

    private func benchmark(gathering: [GatheringNode]) {
        let scene = MapMarkerScene(landmarks: Self.landmarks, gathering: gathering)
        let icon = Image(uiImage: UIGraphicsImageRenderer(size: CGSize(width: 31, height: 31)).image { context in
            UIColor.orange.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 31, height: 31))
        })
        let images = Dictionary(uniqueKeysWithValues: scene.iconURLs.map { ($0, icon) })

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var renderedWidth = 0.0
            for frame in 0..<8 {
                let transform = MapViewportTransform(
                    center: ContinentPoint(x: 10_350 + Double(frame) * 10, y: 10_250),
                    zoom: 3, magnification: 1, dragOffset: .zero,
                    size: CGSize(width: 390, height: 844))
                let visible = scene.visibleMarkers(in: transform)
                let renderer = ImageRenderer(content: MapMarkerCanvas(
                    markers: visible, transform: transform, visited: [], harvested: [],
                    images: images, onActivate: { _ in }).frame(width: 390, height: 844))
                renderer.scale = 1
                renderedWidth += Double(renderer.uiImage?.size.width ?? 0)
            }
            XCTAssertEqual(renderedWidth, 3_120)
        }
    }
}

private actor DelayedLandmarkProvider: MapLandmarkDataProvider {
    func landmarks(continentId: Int, floor: Int, mapId: Int) async throws -> [MapLandmark] {
        try await Task.sleep(for: .milliseconds(mapId == 1 ? 100 : 5))
        return [MapLandmark(
            id: "map-\(mapId)", kind: .waypoint, name: "Map \(mapId)",
            coordinate: ContinentPoint(x: Double(mapId), y: 0), chatLink: nil)]
    }
}

final class BridgeConnectionTests: XCTestCase {
    func testUnauthorizedPairingIsReportedDistinctly() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnauthorizedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let connection = BridgeConnection(
            pairing: BridgePairing(host: "192.0.2.1", port: 38291, token: String(repeating: "a", count: 32)),
            session: session)

        do {
            for try await _ in connection.telemetryStream() {}
            XCTFail("Expected an invalid pairing error")
        } catch {
            XCTAssertEqual(error as? BridgeConnectionError, .pairAgain)
        }
    }

    func testCancellingStreamClosesSocket() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = expectation(description: "socket started")
        let closed = expectation(description: "socket closed")
        let socket = BlockingBridgeSocket(started: started, closed: closed)
        let connection = BridgeConnection(
            pairing: BridgePairing(host: "192.0.2.1", port: 38291, token: String(repeating: "a", count: 32)),
            session: session,
            socketFactory: { _ in socket })

        let consumer = Task {
            do {
                for try await _ in connection.telemetryStream() {}
            } catch is CancellationError {
                // Expected when the consumer is cancelled.
            } catch {
                XCTFail("Unexpected connection error: \(error)")
            }
        }
        await fulfillment(of: [started], timeout: 1)
        consumer.cancel()
        await fulfillment(of: [closed], timeout: 1)
        _ = await consumer.result
    }
}

private final class UnauthorizedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class AcceptedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BlockingBridgeSocket: BridgeWebSocket, @unchecked Sendable {
    private let started: XCTestExpectation
    private let closed: XCTestExpectation

    init(started: XCTestExpectation, closed: XCTestExpectation) {
        self.started = started
        self.closed = closed
    }

    func resume() { started.fulfill() }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await Task.sleep(for: .seconds(60))
        throw BridgeConnectionError.closed
    }

    func close() { closed.fulfill() }
}
