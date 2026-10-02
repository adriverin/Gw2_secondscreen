import XCTest
import UIKit
@testable import GW2Companion

@MainActor
final class AtomicMapHandoffTests: XCTestCase {
    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image {
            UIColor.white.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
    }
    private func frame(_ request: MapRasterLayerRequest) -> MapRasterLayerFrame {
        let tile = image()
        return MapRasterLayerFrame(request: request, images: Dictionary(uniqueKeysWithValues: request.tiles.map { ($0, tile) }))
    }
    private func request(_ zoom: Double, pan: Double = 0, detailed: Bool = true) -> MapRasterLayerRequest {
        let source = ContinuousMapCamera.sourceZoom(cameraZoom: zoom, current: 6, maximum: 7)
        let transform = MapViewportTransform(center: ContinentPoint(x: 44615.5 + pan, y: 29863.7), zoom: source,
            magnification: 1, dragOffset: .zero, size: CGSize(width: 1024, height: 1366), cameraZoom: zoom)
        return MapRasterLayerRequest(continent: 1, floor: 1, tiles: ArenaNetTileProjection.shared.tiles(
            coveringContinentRect: transform.visibleContinentRect(), zoom: source, continentID: 1, mapFloor: 1), detailed: detailed)
    }

    func testOneMissingVisibleTileKeepsEntireOldFrameOpaque() async {
        let old = request(6)
        let target = request(5)
        var handoff = MapRasterLayerHandoff()
        handoff.begin(old); XCTAssertTrue(handoff.accept(frame(old))); handoff.finish(old)
        handoff.begin(target)
        let tile = image(), missing = target.tiles[0]
        let failed = await MapRasterLayerLoader.frame(for: target, derivedLoader: {
            $0.displayTile == missing ? nil : tile
        })
        XCTAssertNil(failed)
        XCTAssertEqual(handoff.active?.request, old)
        XCTAssertEqual(handoff.activeOpacity(progress: 0), 1)
        XCTAssertNil(handoff.outgoing)
        var incomplete = frame(target).images; incomplete[missing] = nil
        XCTAssertFalse(handoff.accept(MapRasterLayerFrame(request: target, images: incomplete)))
        XCTAssertEqual(handoff.active?.images.count, old.tiles.count)
    }

    func testVisibleFramePromotesWithoutAnyPrefetchTiles() async throws {
        let visible = request(5)
        let tile = image()
        let loaded = await MapRasterLayerLoader.frame(for: visible, derivedLoader: { _ in tile })
        let ready = try XCTUnwrap(loaded)
        XCTAssertTrue(ready.isComplete)
        var handoff = MapRasterLayerHandoff(); handoff.begin(visible)
        XCTAssertTrue(handoff.accept(ready))
        XCTAssertEqual(handoff.active?.images.count, visible.tiles.count)
        XCTAssertEqual(handoff.activeOpacity(progress: 0), 1, "An initial frame has no outgoing layer to fade through")
    }

    func testRapidKessexZoomPanRejectsStaleCompletionAndRetainsBackingCoverage() {
        let projection = ArenaNetTileProjection.shared
        let backing = MapRasterLayerRequest.backing(continent: 1, floor: 1)
        XCTAssertEqual(backing.tiles.count, 6)
        let backingRect = backing.tiles.compactMap { projection.tileWorldRect(for: $0, continentID: 1) }.reduce(CGRect.null) { $0.union($1) }
        var handoff = MapRasterLayerHandoff()
        let initial = request(6); handoff.begin(initial); XCTAssertTrue(handoff.accept(frame(initial))); handoff.finish(initial)
        var previous = initial
        for (zoom, pan) in [(5.31, 100.0), (4.91, 800), (4.25, -500), (4.70, 900), (5.75, 1000), (6.3, 0)] {
            let newest = request(zoom, pan: pan)
            handoff.begin(newest)
            XCTAssertFalse(handoff.accept(frame(previous), for: previous), "Late complete frames must not win a viewport race")
            XCTAssertEqual(handoff.activeOpacity(progress: 0.25), 1, "Pending request leaves the retained layer fully opaque")
            let transform = MapViewportTransform(center: ContinentPoint(x: 44615.5 + pan, y: 29863.7), zoom: 6,
                magnification: 1, dragOffset: .zero, size: CGSize(width: 1024, height: 1366), cameraZoom: zoom)
            XCTAssertTrue(backingRect.contains(transform.visibleContinentRect()), "Newly exposed geography must have retained artwork, not placeholders")
            XCTAssertTrue(handoff.accept(frame(newest)))
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                XCTAssertEqual(handoff.activeOpacity(progress: progress), progress)
                XCTAssertEqual(handoff.outgoingOpacity(progress: progress), 1 - progress)
                // Both layers use this same current continuous transform,
                // independent of their own integer source zoom.
                let point = ContinentPoint(x: 44700, y: 29900)
                let screen = transform.screenPosition(for: point)
                XCTAssertEqual(transform.continentPoint(for: screen).x, point.x, accuracy: 0.000001)
            }
            handoff.finish(previous); XCTAssertNotNil(handoff.outgoing)
            handoff.finish(newest); XCTAssertNil(handoff.outgoing)
            previous = newest
        }
    }

    func testCompleteNativeFallbackAndInterruptedFade() async throws {
        let old = request(6), detail = request(5)
        var handoff = MapRasterLayerHandoff(); handoff.begin(old); XCTAssertTrue(handoff.accept(frame(old))); handoff.finish(old)
        handoff.begin(detail)
        let failed = await MapRasterLayerLoader.frame(for: detail, derivedLoader: { _ in nil }); XCTAssertNil(failed)
        let native = MapRasterLayerRequest(continent: detail.continent, floor: detail.floor, tiles: detail.tiles, detailed: false)
        let tile = image()
        let loaded = await MapRasterLayerLoader.frame(for: native, nativeLoader: { _ in tile })
        let ready = try XCTUnwrap(loaded)
        XCTAssertTrue(handoff.accept(ready, for: detail))
        XCTAssertEqual(handoff.outgoing?.request, old)
        let newer = request(4.3); handoff.begin(newer)
        XCTAssertEqual(handoff.active?.request, native)
        XCTAssertEqual(handoff.activeOpacity(progress: 0.3), 1)
        XCTAssertFalse(handoff.accept(frame(detail), for: detail))
        handoff.finish(native)
        XCTAssertEqual(handoff.pending, newer)
    }
}

final class PhysicalStatSourceTests: XCTestCase {
    private let warrior = GW2Character(name: "Generic source regression, not Flashonder", race: "Human", gender: "Male", profession: "Warrior", level: 80, age: 1)
    private let liveFacts = #"{"id":1449,"name":"Great Fortitude","specialization":4,"slot":"Major","facts":[{"type":"BuffConversion","source":"Power","target":"Vitality","percent":10},{"type":"BuffConversion","source":"Power","target":"CritDamage","percent":10}]}"#

    func testLiveGreatFortitudeAndIrrelevantPayloadEvolution() throws {
        let live = try JSONDecoder().decode(TraitMetadata.self, from: Data(liveFacts.utf8))
        XCTAssertEqual(StaticTraitModifierCatalog.conversions(in: live).count, 2)
        let evolved = #"{"id":1449,"name":"Localised","description":"Not used","facts":[{"type":"BuffConversion","source":"Power","target":"Ferocity","percent":10.0,"value":0.5,"text":{"future":"shape"},"irrelevant":true},{"type":"BuffConversion","source":"Power","target":"Vitality","percent":10.0},{"type":"BuffConversion","source":"Power","target":"Vitality","percent":10},{"type":"NoData"}]}"#
        let trait = try JSONDecoder().decode(TraitMetadata.self, from: Data(evolved.utf8))
        XCTAssertEqual(trait.facts.count, 4, "An unrelated non-integer value must not discard a conversion fact")
        XCTAssertEqual(StaticTraitModifierCatalog.conversions(in: trait).count, 2, "Ordering/duplicates/localisation do not change the two curated effects")
    }

    func testFinalPowerConversionAndUnchangedDerivedFormulaeFromSelectedSources() throws {
        let trait = try JSONDecoder().decode(TraitMetadata.self, from: Data(liveFacts.utf8))
        let pinnacle = TraitMetadata(id: 1453, name: "Pinnacle of Strength", icon: nil, description: "", tier: nil, slot: "Minor", facts: [TraitFact(type: "Percent", percent: 5)])
        // Deliberately synthetic aggregate equipment to exercise the rule's
        // arithmetic; NOT a reconstructed Flashonder equipment fixture.
        let equipment = [CharacterEquipment(itemID: 1, slot: "Amulet", stats: SelectedItemStats(id: 1,
            attributes: ["Power":873, "Precision":170, "Vitality":864, "Ferocity":73]))]
        let build = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 4, traits: [1449, 1453])], skills: .empty)
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: build, traits: [1449:trait, 1453:pinnacle])
        XCTAssertEqual(stats.total(for: "Power"), 1873)
        XCTAssertEqual(stats.attributes["Vitality"]?.traits, 187)
        XCTAssertEqual(stats.total(for: "Vitality"), 2051)
        XCTAssertEqual(stats.total(for: "Ferocity"), 260)
        XCTAssertEqual(try XCTUnwrap(stats.derived.criticalDamagePercent), 167.333333, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(stats.derived.criticalChancePercent), 18.095238, accuracy: 0.00001)
        XCTAssertEqual(stats.derived.health, 29722)
        let unselected = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 4, traits: [])], skills: .empty)
        XCTAssertEqual(CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: unselected, traits: [1449:trait]).total(for: "Ferocity"), 73)
        let wrongSpecialization = CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 36, traits: [1449])], skills: .empty)
        XCTAssertEqual(CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:], build: wrongSpecialization, traits: [1449:trait]).total(for: "Ferocity"), 73)
    }

    func testSunriseRawArmoryStatsHydrationPersistenceAndNoGuess() throws {
        let raw = #"{"equipment":[{"id":30703,"slot":"WeaponA1","location":"EquippedFromLegendaryArmory","tabs":[1],"stats":{"id":161,"attributes":{"Power":251,"Precision":179,"CritDamage":179}}}]}"#
        let data = Data(raw.utf8)
        let diagnostics = EquipmentPayloadDiagnostic.capture(data, endpoint: "equipment")
        XCTAssertTrue(diagnostics[0].statsObjectPresent)
        XCTAssertEqual(diagnostics[0].selectedStatID, 161)
        XCTAssertEqual(diagnostics[0].attributeKeys, ["CritDamage", "Power", "Precision"])
        let response = try JSONDecoder().decode(CharacterEquipmentResponse.self, from: data)
        let tabs = [EquipmentTab(tab: 1, name: "Active", isActive: true, equipment: [CharacterEquipment(itemID: 30703, slot: "WeaponA1")])]
        let hydrated = EquipmentStatInputResolver.hydratedTabs(tabs, from: response)
        let restored = try JSONDecoder().decode([EquipmentTab].self, from: JSONEncoder().encode(hydrated))
        XCTAssertEqual(restored, hydrated)
        XCTAssertEqual(restored[0].equipment[0].stats?.attributes?["Power"], 251)
        let sunrise = ItemMetadata(id: 30703, name: "Sunrise", icon: nil, rarity: "Legendary", type: "Weapon",
            details: ItemDetails(type: "Greatsword", defense: 0, statChoices: [161], attributeAdjustment: 717.024))
        XCTAssertTrue(EquipmentStatInputResolver.audit(equipment: tabs[0].equipment, items: [30703:sunrise])[0].baseAttributes.isEmpty)
        let idOnly = CharacterEquipmentResponse(equipment: [CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: nil))])
        XCTAssertEqual(EquipmentStatInputResolver.hydratedTabs(tabs, from: idOnly)[0].equipment[0].stats?.id, 161, "An authenticated selected ID alone must survive hydration for subsequent itemstats repair")
    }

    func testUnavailable4633NeverInventsDefenseOrAttributes() {
        let equipment = [CharacterEquipment(itemID: 4633, slot: "Shoulders")]
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [:])
        XCTAssertEqual(stats.defense.total, 0)
        XCTAssertEqual(stats.total(for: "Power"), 1000)
        XCTAssertTrue(stats.equipmentSources[0].sources.contains { $0.label == "Defense" && $0.state == .unresolved })
    }

    func testEvolvingAttributeObjectDoesNotLoseLegendarySelectionOrSlot() throws {
        let raw = #"{"equipment":[{"id":30703,"slot":"WeaponA1","stats":{"id":161,"attributes":{"Power":251,"future_field":"not a stat"}}}]}"#
        let decoded = try JSONDecoder().decode(CharacterEquipmentResponse.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.equipment[0].stats?.id, 161)
        XCTAssertNil(decoded.equipment[0].stats?.attributes, "Do not partially invent or silently truncate a malformed selected attribute object")
        XCTAssertEqual(decoded.equipment[0].slot, "WeaponA1")
    }

    func testVerifiedPublicShoulderFixtureAddsItsActualDefenseNotDiagnostic121() throws {
        // ArenaNet /v2/items/48197 fetched 2026-10-02. Not Flashonder's item
        // 4633 (404); a real fixture exercises the repaired metadata path.
        let raw = #"{"id":48197,"name":"Zintl Shoulderguard","type":"Armor","rarity":"Ascended","details":{"type":"Shoulders","weight_class":"Medium","defense":102,"attribute_adjustment":134.442,"infix_upgrade":{"id":153,"attributes":[{"attribute":"Vitality","modifier":47},{"attribute":"Healing","modifier":34},{"attribute":"ConditionDamage","modifier":34}]},"secondary_suffix_item_id":""}}"#
        let item = try JSONDecoder().decode(ItemMetadata.self, from: Data(raw.utf8))
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: [CharacterEquipment(itemID: 48197, slot: "Shoulders")], items: [48197:item])
        XCTAssertEqual(stats.defense.total, 102)
        XCTAssertEqual(stats.total(for: "Vitality"), 1047)
        XCTAssertEqual(stats.derived.armor, 1102)
    }
}

final class TradingPostAsyncStateTests: XCTestCase {
    private func price(_ age: TimeInterval = 0, quantity: Int = 2) -> TimedCommercePrice {
        TimedCommercePrice(price: CommercePrice(id: 30703, whitelisted: true,
            buys: CommerceListingSummary(quantity: 1, unitPrice: 100),
            sells: CommerceListingSummary(quantity: quantity, unitPrice: quantity == 0 ? 0 : 200)), fetchedAt: Date().addingTimeInterval(-age))
    }
    func testLoadingIsNotUnavailableOrPriorRequestFailure() {
        XCTAssertEqual(TradingPostPriceResolver.state(price: nil, loading: true), .loading)
        XCTAssertEqual(TradingPostPriceResolver.state(price: nil, failed: "old failure", loading: true), .loading)
        XCTAssertEqual(TradingPostPriceResolver.state(price: nil), .unavailable)
        XCTAssertEqual(TradingPostPriceResolver.state(price: nil, failed: "network failure"), .failed("network failure"))
    }
    func testCachedPriceSurvivesRefreshAndFailure() {
        let cached = price(600)
        XCTAssertEqual(TradingPostPriceResolver.state(price: cached, loading: true), .stale(cached))
        XCTAssertEqual(TradingPostPriceResolver.state(price: cached, failed: "offline"), .stale(cached))
        let presentation = TradingPostPriceResolver.presentation(itemID: 30703, itemName: "Sunrise", missingQuantity: 2, state: .stale(cached))
        XCTAssertEqual(presentation.unitCopper, 200)
        XCTAssertEqual(presentation.buyNowCopper, 400)
    }
    func testCompletedAvailableNoListingsAndNotTradable() {
        let available = price(), empty = price(quantity: 0)
        XCTAssertEqual(TradingPostPriceResolver.state(price: available), .available(available))
        XCTAssertEqual(TradingPostPriceResolver.state(price: empty), .noSellListings(empty))
        let bound = ItemMetadata(id: 1, name: "Bound", icon: nil, rarity: "Exotic", type: "Armor", flags: ["AccountBound"])
        XCTAssertEqual(TradingPostPriceResolver.state(price: nil, item: bound, loading: true), .notTradable)
    }
}

@MainActor
final class TradingPostRequestPhaseTests: XCTestCase {
    func testActual404CompletesAsNoListingsBut500NeverOverwritesCachedPrice() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tp-cache-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MetadataDiskCache(directory: directory)
        let saved = TimedCommercePrice(price: CommercePrice(id: 30703, whitelisted: true,
            buys: CommerceListingSummary(quantity: 1, unitPrice: 100),
            sells: CommerceListingSummary(quantity: 2, unitPrice: 200)), fetchedAt: Date().addingTimeInterval(-600))
        await cache.save([30703:saved], named: "commerce-prices-v1")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailedPriceProtocol.self]
        let api = GW2APIClient(session: URLSession(configuration: configuration), credentials: CredentialStore(secureStore: InMemorySecureStore()), diskCache: cache)
        let fallback = try await api.commercePrices(ids: [30703], force: true)
        XCTAssertEqual(fallback[30703], saved)
        do {
            _ = try await api.commercePrices(ids: [30703], force: true, reportFailure: true)
            XCTFail("HTTP 500 must remain a failed lookup even with a cached listing")
        } catch { XCTAssertEqual(error as? GW2APIError, .server(500)) }
        let stillSaved = try await api.commercePrices(ids: [30703], force: true)
        XCTAssertEqual(stillSaved[30703], saved)
        let missing = try await api.commercePrices(ids: [30704], force: true, reportFailure: true)
        let price = try XCTUnwrap(missing[30704])
        XCTAssertEqual(TradingPostPriceResolver.state(price: price), .noSellListings(price))
    }

    func testCompletedRequestFailureIsItemScopedAndNeverUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tp-request-phase-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MetadataDiskCache(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailedPriceProtocol.self]
        let api = GW2APIClient(session: URLSession(configuration: configuration), credentials: CredentialStore(secureStore: InMemorySecureStore()), diskCache: cache)
        let defaults = UserDefaults(suiteName: "tp-request-phase-\(UUID())")!
        let store = GoalStore(api: api, cache: cache, defaults: defaults)
        let pending = expectation(description: "Item becomes loading before request finishes")
        let subscription = store.$priceLookups.sink { phases in
            if phases[30703] == .loading { pending.fulfill() }
        }
        await store.refreshPrice(itemID: 30703)
        await fulfillment(of: [pending], timeout: 1)
        withExtendedLifetime(subscription) {}
        let phase = try XCTUnwrap(store.priceLookups[30703])
        XCTAssertNotNil(phase.error)
        XCTAssertFalse(phase.isLoading)
        XCTAssertNil(store.priceLookups[4633], "Unrelated item errors cannot leak into this detail")
        let state = TradingPostPriceResolver.state(price: store.marketPrices[30703], failed: phase.error, loading: phase.isLoading)
        guard case .failed = state else { return XCTFail("A failed request is not an unavailable listing") }
    }
}

private final class FailedPriceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url?.query?.contains("30704") == true ? 404 : 500
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"fixture outage"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
