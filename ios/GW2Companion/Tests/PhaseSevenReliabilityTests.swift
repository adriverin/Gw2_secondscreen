import Foundation
import XCTest
@testable import GW2Companion

final class PhaseSevenDecodeHardeningTests: XCTestCase {
    func testBankNullSlotsAndNullableUpgradesDecode() throws {
        let slots = try SparseNullableArray<InventorySlot>(fromJSONFile: "phase7-bank-nulls").values
        XCTAssertEqual(slots.count, 4)
        XCTAssertEqual(slots.compactMap { $0 }.map(\.id), [19697, 46731])
        XCTAssertEqual(slots[0]?.upgrades, [201])
        XCTAssertEqual(slots[0]?.infusions, [301])
        XCTAssertEqual(slots[0]?.dyes, [2])
        XCTAssertNil(slots[1])
    }

    func testCharacterInventoryNullBagsDecode() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "inventory", withExtension: "json"))
        let response = try JSONDecoder().decode(CharacterInventoryResponse.self, from: Data(contentsOf: url))
        XCTAssertEqual(response.bags.count, 3)
        XCTAssertNil(response.bags[2])
        XCTAssertEqual(response.bags[0]?.inventory?.compactMap { $0 }.map(\.id), [19697, 46731])
    }

    func testUnknownEquipmentSlotsAndBindingsDecode() throws {
        let tabs: [EquipmentTab] = try LossyDecodableArray(fromJSONFile: "phase7-equipment-unknown").values
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs[0].equipment.map(\.slot), ["Relic", "FutureSlot"])
        XCTAssertEqual(tabs[0].equipment[1].location, "FutureLocation")
        XCTAssertEqual(tabs[0].equipment[1].binding, "FutureBinding")
        XCTAssertEqual(tabs[0].equipment[0].upgrades, [201])
        XCTAssertEqual(tabs[0].equipment[0].infusions, [301])
    }

    func testBuildTabsTolerateNullTraitsSkillsAndUnknownProfession() throws {
        let tabs: [BuildTab] = try LossyDecodableArray(fromJSONFile: "phase7-build-unknown").values
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].build.profession, "Virtuoso")
        XCTAssertEqual(tabs[0].build.specializations[0].traits, [31, nil, 33])
        XCTAssertNil(tabs[0].build.skills.terrestrial?.utilities[1])
        XCTAssertFalse(tabs[1].isActive)
        XCTAssertTrue(tabs[1].build.specializations.isEmpty)
    }

    func testUnknownRecipeAndIngredientTypesDoNotDiscardBatch() throws {
        let decoded: LossyDecodableArray<RecipeDefinition> = try LossyDecodableArray(fromJSONFile: "phase7-recipes-forward")
        XCTAssertEqual(decoded.values.map(\.id), [1, 2, 3])
        XCTAssertGreaterThanOrEqual(decoded.failedCount, 1)
        XCTAssertEqual(decoded.values[1].type, "FutureCraftType")
        XCTAssertEqual(decoded.values[1].ingredients.map(\.knownType.rawValue), ["Item", "Currency", "GuildUpgrade", "AstralWidget"])
        XCTAssertEqual(decoded.values[0].ingredients.first?.knownType, .item)
    }

    func testLegacyItemIDIngredientStillDecodes() throws {
        let decoded: LossyDecodableArray<RecipeDefinition> = try LossyDecodableArray(fromJSONFile: "phase7-recipes-forward")
        XCTAssertEqual(decoded.values[0].ingredients.first?.id, 3000)
        XCTAssertEqual(decoded.values[0].ingredients.first?.knownType, .item)
    }

    func testPartialItemMetadataArrayKeepsValidRecords() throws {
        let decoded: LossyDecodableArray<ItemMetadata> = try LossyDecodableArray(fromJSONFile: "phase7-items-partial")
        XCTAssertEqual(decoded.values.map(\.id), [19697])
        XCTAssertEqual(decoded.failedCount, 1)
    }

    func testExistingPublicRecipeFixtureStillDecodesWithUnknownIngredient() throws {
        let recipes: [RecipeDefinition] = try LossyDecodableArray(fromJSONFile: "recipes-phase4").values
        XCTAssertEqual(recipes.count, 11)
        XCTAssertEqual(recipes.first { $0.id == 9 }?.ingredients.last?.type, "FutureType")
    }
}

final class PhaseSevenWalletTests: XCTestCase {
    func testAllTwentyFiveCurrenciesAreReachableWithoutSearch() throws {
        let wallet: [WalletEntry] = try fixture("phase7-wallet-25")
        XCTAssertEqual(wallet.count, 25)
        var currencies: [Int: CurrencyMetadata] = [:]
        for entry in wallet {
            currencies[entry.id] = CurrencyMetadata(
                id: entry.id, name: "Currency \(entry.id)", description: "", icon: nil, order: 100 - entry.id)
        }
        let ordered = WalletPresentation.ordered(wallet: wallet, currencies: currencies, query: "")
        XCTAssertEqual(ordered.count, 25)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(1...25))
        let filtered = WalletPresentation.ordered(wallet: wallet, currencies: currencies, query: "Currency 7")
        XCTAssertEqual(filtered.map(\.id), [7])
    }
}

final class PhaseSevenGatheringCoverageTests: XCTestCase {
    func testUnavailableCoverageDoesNotClaimThereAreNoNodes() {
        XCTAssertEqual(
            GatheringCoverageCopy.banner(availability: .unavailable),
            "Gathering coverage unavailable")
        XCTAssertEqual(
            GatheringCoverageCopy.layerMessage(availability: .unavailable, mapName: "Queensdale"),
            "Queensdale: No Companion gathering dataset yet")
        XCTAssertFalse((GatheringCoverageCopy.banner(availability: .unavailable) ?? "").localizedCaseInsensitiveContains("no gathering nodes"))
        XCTAssertFalse((GatheringCoverageCopy.layerMessage(availability: .available(0), mapName: nil) ?? "")
            .localizedCaseInsensitiveContains("no gathering nodes"))
        XCTAssertEqual(GatheringCoverageCopy.coverageTitle(availability: .unavailable), "No Companion gathering dataset yet")
        XCTAssertEqual(GatheringCoverageCopy.coverageTitle(availability: .available(12)), "Partial coverage")
    }

    @MainActor
    func testStoreMarksUncoveredMapAsUnavailableNotEmpty() async throws {
        let store = GatheringStore(provider: CoverageOnlyProvider(covered: [54]), sampleProvider: CoverageOnlyProvider(covered: [54]))
        let metadata = GW2MapMetadata(
            id: 15, name: "Queensdale", continentId: 1, defaultFloor: 1,
            mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        await store.load(mapId: 15, metadata: metadata, simulation: false)
        XCTAssertEqual(store.availability, .unavailable)
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertEqual(GatheringCoverageCopy.banner(availability: store.availability), "Gathering coverage unavailable")
    }
}

final class PhaseSevenMapDetailTests: XCTestCase {
    func testModerateZoomRequestsOneExtraSourceLevel() {
        let transform = MapViewportTransform(
            center: MapAlignmentLandmarks.kessexHavenWaypoint.continent,
            zoom: 6, magnification: 1, dragOffset: .zero,
            size: CGSize(width: 390, height: 844), tileReferenceZoom: 7)
        let viewport = transform.visibleContinentRect(marginPoints: 256)
        let source = MapRasterDetail.sourceZoom(
            displayZoom: 6, continentID: 1, viewport: viewport, mode: .detailed)
        XCTAssertEqual(source, 7)
        let tiles = ArenaNetTileProjection.shared.tiles(
            coveringContinentRect: viewport, zoom: source, continentID: 1, mapFloor: 1)
        XCTAssertLessThanOrEqual(tiles.count, MapRasterDetail.maxSupersampledTiles)
        XCTAssertEqual(
            MapDetailMode.detailed.sourceZoomBias(displayZoom: 6, referenceZoom: 7, visibleTileCountWithoutBias: 8),
            1)
    }

    func testFarContinentViewDoesNotSupersample() {
        let viewport = CGRect(x: 0, y: 0, width: 49_000, height: 40_000)
        let source = MapRasterDetail.sourceZoom(
            displayZoom: 2, continentID: 1, viewport: viewport, mode: .detailed)
        XCTAssertEqual(source, 2)
        XCTAssertEqual(MapDetailMode.detailed.markerCullZoom, 2)
        XCTAssertEqual(MapDetailMode.balanced.markerCullZoom, 3)
    }

    func testOfficialProviderReportsModernMapsUnavailable() {
        let seitung = MapAlignmentLandmarks.unsupportedNewMapMetadata
        XCTAssertEqual(
            ArenaNetOfficialTileProvider().coverage(for: seitung),
            .unavailable(reason: "Detailed map artwork is not available from ArenaNet for this area."))
        XCTAssertTrue(ArenaNetOfficialTileProvider().coverage(for: MapAlignmentLandmarks.kessexHillsMetadata).isOfficial)
        XCTAssertNil(NeutralFallbackProvider().tileURL(continent: 1, floor: 1, zoom: 7, x: 1, y: 1))
    }

    func testDetailedMarkerCullKeepsObjectivesFartherOut() {
        XCTAssertLessThan(MapDetailMode.detailed.markerCullZoom, MapDetailMode.balanced.markerCullZoom)
    }
}

final class PhaseSevenSchemaTests: XCTestCase {
    func testCharacterEndpointsPinBuildTemplateSchema() {
        XCTAssertEqual(GW2Schema.characterTemplates, "2019-12-19T00:00:00.000Z")
        XCTAssertEqual(GW2Schema.version(for: "characters?page=0&page_size=200"), GW2Schema.characterTemplates)
        XCTAssertEqual(GW2Schema.version(for: "characters/Andrea/inventory"), GW2Schema.characterTemplates)
        XCTAssertEqual(GW2Schema.version(for: "characters/Andrea/buildtabs?tabs=all"), GW2Schema.characterTemplates)
        XCTAssertNil(GW2Schema.version(for: "account/bank"))
        XCTAssertNil(GW2Schema.version(for: "recipes"))
        XCTAssertNil(GW2Schema.account)
        XCTAssertEqual(
            GW2Schema.applyingQuery(to: "characters?page=0&page_size=200"),
            "characters?page=0&page_size=200&v=2019-12-19T00:00:00.000Z")
        XCTAssertEqual(
            GW2Schema.applyingQuery(to: "characters/Andrea/inventory"),
            "characters/Andrea/inventory?v=2019-12-19T00:00:00.000Z")
        XCTAssertEqual(
            GW2Schema.applyingQuery(to: "characters/Andrea/buildtabs?tabs=all"),
            "characters/Andrea/buildtabs?tabs=all&v=2019-12-19T00:00:00.000Z")
        XCTAssertEqual(
            GW2Schema.applyingQuery(to: "characters/Andrea/equipmenttabs?tabs=all"),
            "characters/Andrea/equipmenttabs?tabs=all&v=2019-12-19T00:00:00.000Z")
        XCTAssertEqual(GW2Schema.applyingQuery(to: "account/bank"), "account/bank")
        XCTAssertEqual(GW2Schema.applyingQuery(to: "recipes"), "recipes")
        XCTAssertEqual(
            GW2Schema.applyingQuery(to: "characters/Andrea/inventory?v=2019-12-19T00:00:00.000Z"),
            "characters/Andrea/inventory?v=2019-12-19T00:00:00.000Z")
    }
}

final class PhaseSevenHTTPStatusTests: XCTestCase {
    func testRetryAfterParserUsesHeaderAndBackoff() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.guildwars2.com/v2/items")!,
            statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "2"])!
        XCTAssertEqual(RetryAfterParser.delay(from: response, attempt: 0), 2, accuracy: 0.01)
        let missing = HTTPURLResponse(
            url: URL(string: "https://api.guildwars2.com/v2/items")!,
            statusCode: 429, httpVersion: nil, headerFields: nil)!
        XCTAssertEqual(RetryAfterParser.delay(from: missing, attempt: 3), 8, accuracy: 0.01)
    }

    func testPartialMetadataHTTP206KeepsValidItems() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.routes["items"] = .init(
            status: 206,
            body: Data(#"[{"id":19697,"name":"Mithril Ore","rarity":"Basic","type":"CraftingMaterial"}]"#.utf8))
        let client = phaseSevenClient()
        let items = try await client.items(ids: [19697, 9_999_999], priority: .high)
        XCTAssertEqual(items[19697]?.name, "Mithril Ore")
        XCTAssertNil(items[9_999_999])
        let unresolved = await client.lastUnresolvedMetadataIDs
        XCTAssertEqual(unresolved["items"], [9_999_999])
    }
}

@MainActor
final class PhaseSevenDomainIsolationTests: XCTestCase {
    func testBuildDecodeFailureDoesNotHideBankMaterialsWalletOrCharacters() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.installAccountSuccessRoutes()
        PhaseSevenAPIProtocol.routes["buildtabs"] = .init(status: 200, body: Data(#"{"not":"an array"}"#.utf8))
        let account = phaseSevenAccountStore()
        try await account.connect(apiKey: "phase7-test-key-not-a-secret")
        XCTAssertEqual(account.characters.map(\.name), ["Andrea"])
        XCTAssertFalse(account.bank.isEmpty)
        XCTAssertFalse(account.materials.isEmpty)
        XCTAssertFalse(account.wallet.isEmpty)
        XCTAssertNotEqual(account.errorMessage, "Couldn't refresh account")
        XCTAssertFalse((account.errorMessage ?? "").localizedCaseInsensitiveContains("couldn't refresh. showing saved account data"))

        await account.loadCharacterDetails(account.characters[0], force: true)
        XCTAssertNotNil(account.characterDetails["Andrea"]?.inventory)
        XCTAssertFalse(account.characterDetails["Andrea"]?.inventoryError != nil && account.bank.isEmpty)
        XCTAssertNotNil(account.characterDetails["Andrea"]?.buildError)
        XCTAssertTrue(account.characterDetails["Andrea"]?.buildTabs.isEmpty ?? true)
        XCTAssertEqual(account.domainStates[.bank]?.phase, .live)
        XCTAssertEqual(account.domainStates[.materials]?.phase, .live)
        XCTAssertEqual(account.domainStates[.wallet]?.phase, .live)
        XCTAssertEqual(account.domainStates[.buildTabs]?.phase, .failed)
        XCTAssertEqual(account.domainStates[.buildTabs]?.decodeSucceeded, false)
        XCTAssertNotNil(account.domainStates[.buildTabs]?.decodePath)
        XCTAssertFalse((account.domainStates[.buildTabs]?.diagnosticsBlock ?? "").contains("phase7-test-key"))
        XCTAssertEqual(PhaseSevenAPIProtocol.lastSchema["characters"], GW2Schema.characterTemplates)
        XCTAssertEqual(PhaseSevenAPIProtocol.lastSchema["characters/Andrea/inventory"], GW2Schema.characterTemplates)
        XCTAssertNil(PhaseSevenAPIProtocol.lastSchema["account/bank"])
        XCTAssertNil(PhaseSevenAPIProtocol.lastSchemaHeader["characters"])
        XCTAssertNil(PhaseSevenAPIProtocol.lastSchemaHeader["characters/Andrea/inventory"])
        XCTAssertNil(PhaseSevenAPIProtocol.lastSchemaHeader["account/bank"])
    }

    func testMaterialsRemainWhenBankFails() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.installAccountSuccessRoutes()
        PhaseSevenAPIProtocol.routes["account/bank"] = .init(status: 500, body: Data("{}".utf8))
        let account = phaseSevenAccountStore()
        try await account.connect(apiKey: "phase7-test-key-not-a-secret")
        XCTAssertTrue(account.bank.isEmpty)
        XCTAssertFalse(account.materials.isEmpty)
        XCTAssertEqual(account.domainStates[.bank]?.httpStatus, 500)
        XCTAssertEqual(account.domainStates[.materials]?.phase, .live)
        XCTAssertNil(account.errorMessage)
    }

    func testHTTP403WithInventoriesPermissionIsNotLabeledMissingPermission() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.installAccountSuccessRoutes()
        PhaseSevenAPIProtocol.routes["account/bank"] = .init(status: 403, body: Data("{}".utf8))
        let account = phaseSevenAccountStore()
        try await account.connect(apiKey: "phase7-test-key-not-a-secret")
        XCTAssertEqual(account.domainStates[.bank]?.httpStatus, 403)
        XCTAssertEqual(account.domainStates[.bank]?.phase, .failed)
        XCTAssertFalse((account.domainStates[.bank]?.message ?? "").localizedCaseInsensitiveContains("missing"))
        XCTAssertFalse(account.materials.isEmpty)
    }
}

@MainActor
final class PhaseSevenRecipeIndexTests: XCTestCase {
    func testPublicRecipeIndexPopulatesCraftItemSearchWithoutAPIKey() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.routes["recipes"] = .init(status: 200, body: Data("[1,2]".utf8))
        PhaseSevenAPIProtocol.routes["recipes?ids"] = .init(
            status: 200,
            body: Data(#"[{"id":1,"type":"Refinement","output_item_id":19697,"output_item_count":1,"disciplines":["Weaponsmith"],"min_rating":0,"flags":[],"ingredients":[{"type":"Item","id":19700,"count":2}]},{"id":2,"type":"FutureCraftType","output_item_id":46731,"output_item_count":1,"disciplines":["Tailor"],"min_rating":0,"flags":[],"ingredients":[{"type":"AstralWidget","id":9,"count":1}]}]"#.utf8))
        PhaseSevenAPIProtocol.routes["items"] = .init(
            status: 200,
            body: Data(#"[{"id":19697,"name":"Mithril Ore","rarity":"Basic"},{"id":46731,"name":"Bolt of Damask","rarity":"Ascended"}]"#.utf8))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = GoalStore(
            api: phaseSevenClient(credentials: CredentialStore(secureStore: InMemorySecureStore())),
            cache: MetadataDiskCache(directory: directory),
            defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.prepareRecipes()
        XCTAssertNotEqual(store.recipeState, .unavailable("Couldn't build the crafting catalog."))
        if case .unavailable = store.recipeState { XCTFail("\(store.recipeState)") }
        XCTAssertFalse(store.searchCraftableItems("Mithril").isEmpty)
        XCTAssertEqual(store.searchCraftableItems("Mithril").first?.name, "Mithril Ore")
        XCTAssertFalse(store.searchCraftableItems("Damask").isEmpty)
    }

    func testCraftItemIndexWorksWhenAccountRefreshFails() async throws {
        PhaseSevenAPIProtocol.reset()
        PhaseSevenAPIProtocol.routes["tokeninfo"] = .init(status: 500, body: Data("{}".utf8))
        PhaseSevenAPIProtocol.routes["recipes"] = .init(status: 200, body: Data("[1]".utf8))
        PhaseSevenAPIProtocol.routes["recipes?ids"] = .init(
            status: 200,
            body: Data(#"[{"id":1,"type":"Refinement","output_item_id":19697,"output_item_count":1,"disciplines":["Weaponsmith"],"min_rating":0,"flags":[],"ingredients":[{"type":"Item","id":19700,"count":1}]}]"#.utf8))
        PhaseSevenAPIProtocol.routes["items"] = .init(
            status: 200, body: Data(#"[{"id":19697,"name":"Mithril Ore","rarity":"Basic"}]"#.utf8))
        let credentials = CredentialStore(secureStore: InMemorySecureStore())
        try credentials.saveAPIKey("phase7-test-key-not-a-secret")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let api = phaseSevenClient(credentials: credentials, cache: MetadataDiskCache(directory: directory))
        let account = AccountStore(api: api, cache: MetadataDiskCache(directory: directory.appending(path: "account")))
        await account.refresh()
        XCTAssertNotNil(account.errorMessage)
        let goals = GoalStore(
            api: api, cache: MetadataDiskCache(directory: directory.appending(path: "goals")),
            defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await goals.prepareRecipes()
        XCTAssertFalse(goals.searchCraftableItems("Mithril").isEmpty)
    }
}

final class PhaseSevenTodayProgressiveTests: XCTestCase {
    func testVaultPublishesBeforeSlowRaidsFinish() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = TodayRepository(provider: SlowRaidTodayProvider(), cache: MetadataDiskCache(directory: directory))
        let flags = ProgressiveTodayFlags()
        let finished = try await repository.refresh(
            accountID: "fixture", hasProgressionPermission: true, hasWalletPermission: false,
            force: true, now: Date(),
            onUpdate: { snapshot in
                if snapshot.opportunities.contains(where: { $0.type == .wizardVaultDaily }) {
                    flags.vaultPublished = true
                    XCTAssertFalse(flags.raidsSeen)
                }
                if snapshot.opportunities.contains(where: { $0.type == .raidEncounter }) {
                    flags.raidsSeen = true
                    XCTAssertTrue(flags.vaultPublished)
                }
            })
        XCTAssertTrue(flags.vaultPublished)
        XCTAssertTrue(finished.opportunities.contains { $0.type == .wizardVaultDaily })
    }
}

final class PhaseSevenLivePublicSmokeTests: XCTestCase {
    func testLiveRecipesItemsAndCurrenciesDecode() async throws {
        try await liveDecode("https://api.guildwars2.com/v2/recipes?ids=1,2,3,4,5", as: LossyDecodableArray<RecipeDefinition>.self)
        try await liveDecode("https://api.guildwars2.com/v2/items?ids=19697,46731", as: LossyDecodableArray<ItemMetadata>.self)
        try await liveDecode("https://api.guildwars2.com/v2/currencies?ids=1,2,4,23,63", as: LossyDecodableArray<CurrencyMetadata>.self)
    }

    private func liveDecode<T: Decodable>(_ url: String, as type: T.Type) async throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw XCTSkip("ArenaNet public API unavailable")
        }
        guard let http = response as? HTTPURLResponse, (200...206).contains(http.statusCode) else {
            throw XCTSkip("ArenaNet public API unavailable")
        }
        _ = try JSONDecoder().decode(T.self, from: data)
    }
}

final class PhaseSevenDiagnosticsCopyTests: XCTestCase {
    func testDomainDiagnosticsNeverIncludeSecrets() {
        let status = AccountDomainStatus(
            domain: .bank, phase: .failed, endpoint: "account/bank", httpStatus: 200,
            schemaVersion: nil, source: .live, decodeSucceeded: false,
            decodePath: "infusions", message: "Decode failed at infusions", updatedAt: Date())
        let text = status.diagnosticsBlock
        XCTAssertTrue(text.contains("Domain: Bank"))
        XCTAssertTrue(text.contains("HTTP status: 200"))
        XCTAssertTrue(text.contains("infusions"))
        XCTAssertFalse(text.lowercased().contains("authorization"))
        XCTAssertFalse(text.lowercased().contains("api key"))
        XCTAssertFalse(text.lowercased().contains("bearer"))
    }
}

final class PhaseSevenMapPerformanceTests: XCTestCase {
    func testDetailedModeKeepsBoundedTileAndMarkerCounts() {
        let transform = MapViewportTransform(
            center: MapAlignmentLandmarks.kessexHavenWaypoint.continent,
            zoom: 6, magnification: 1, dragOffset: .zero,
            size: CGSize(width: 390, height: 844), tileReferenceZoom: 7)
        let viewport = transform.visibleContinentRect(marginPoints: 256)
        let source = MapRasterDetail.sourceZoom(
            displayZoom: 6, continentID: 1, viewport: viewport, mode: .detailed)
        let tiles = ArenaNetTileProjection.shared.tiles(
            coveringContinentRect: viewport, zoom: source, continentID: 1, mapFloor: 1)
        XCTAssertEqual(source, 7)
        XCTAssertLessThanOrEqual(tiles.count, MapRasterDetail.maxSupersampledTiles)
        XCTAssertGreaterThan(tiles.count, 0)
        let far = CGRect(x: 0, y: 0, width: 49_000, height: 40_000)
        XCTAssertEqual(
            MapRasterDetail.sourceZoom(displayZoom: 2, continentID: 1, viewport: far, mode: .detailed),
            2)
    }
}

private struct CoverageOnlyProvider: MarkerDataProvider {
    let covered: Set<Int>
    func markers(for mapId: Int, metadata: GW2MapMetadata) async throws -> [GatheringNode] { [] }
    func coveredMapIDs() async throws -> Set<Int> { covered }
}

private struct SlowRaidTodayProvider: TodayDataProvider {
    private let daily = WizardVaultAccountPeriod(
        metaProgressCurrent: 1, metaProgressComplete: 4, metaRewardItemID: 1,
        metaRewardAstral: 10, metaRewardClaimed: false,
        objectives: [WizardVaultAccountObjective(
            id: 11, title: "Daily Goal", track: "PvE", acclaim: 10,
            progressCurrent: 1, progressComplete: 1, claimed: false)])
    private let weekly = WizardVaultAccountPeriod(
        metaProgressCurrent: 0, metaProgressComplete: 8, metaRewardItemID: 2,
        metaRewardAstral: 50, metaRewardClaimed: false, objectives: [])

    func wizardVaultSeason(language: String) async throws -> WizardVaultSeason {
        WizardVaultSeason(title: "Fixture Season", start: "2026-01-01T00:00:00Z", end: "2027-01-01T00:00:00Z", listings: [], objectives: [])
    }
    func wizardVaultObjectives(ids: [Int], language: String) async throws -> [WizardVaultObjectiveMetadata] { [] }
    func wizardVaultListings(ids: [Int], language: String) async throws -> [WizardVaultListingMetadata] { [] }
    func worldBossIDs() async throws -> [String] { [] }
    func mapChestIDs() async throws -> [String] { [] }
    func dailyCraftingIDs() async throws -> [String] { [] }
    func raids(language: String) async throws -> [RaidDefinition] {
        try await Task.sleep(for: .seconds(5))
        return [RaidDefinition(id: "forsaken_thicket", wings: [
            RaidWing(id: "spirit_vale", events: [RaidEvent(id: "vale_guardian", type: .boss)])
        ])]
    }
    func dungeons(language: String) async throws -> [DungeonDefinition] { [] }
    func wizardVaultDaily() async throws -> WizardVaultAccountPeriod {
        try await Task.sleep(for: .milliseconds(100))
        return daily
    }
    func wizardVaultWeekly() async throws -> WizardVaultAccountPeriod {
        try await Task.sleep(for: .milliseconds(120))
        return weekly
    }
    func wizardVaultSpecial() async throws -> WizardVaultAccountSpecial { WizardVaultAccountSpecial(objectives: []) }
    func accountWizardVaultListings() async throws -> [WizardVaultAccountListing] { [] }
    func accountWorldBossIDs() async throws -> [String] { [] }
    func accountMapChestIDs() async throws -> [String] { [] }
    func accountDailyCraftingIDs() async throws -> [String] { [] }
    func accountRaidEventIDs() async throws -> [String] { [] }
    func accountDungeonPathIDs() async throws -> [String] { [] }
    func todayItems(ids: [Int]) async throws -> [Int: ItemMetadata] { [:] }
    func todayCurrencies(ids: [Int]) async throws -> [Int: CurrencyMetadata] { [:] }
    func todayWallet() async throws -> [WalletEntry] { [] }
}

private final class ProgressiveTodayFlags: @unchecked Sendable {
    var vaultPublished = false
    var raidsSeen = false
}

private struct PhaseSevenRoute {
    var status: Int
    var body: Data
}

private final class PhaseSevenAPIProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: PhaseSevenRoute] = [:]
    nonisolated(unsafe) static var lastSchema: [String: String] = [:]
    nonisolated(unsafe) static var lastSchemaHeader: [String: String] = [:]
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); routes = [:]; lastSchema = [:]; lastSchemaHeader = [:]; lock.unlock()
    }

    static func installAccountSuccessRoutes() {
        routes["tokeninfo"] = .init(
            status: 200,
            body: Data(#"{"id":"fixture","name":"Phase 7","permissions":["account","characters","inventories","builds","wallet","progression","unlocks"]}"#.utf8))
        routes["account"] = .init(
            status: 200,
            body: Data(#"{"id":"account-id","name":"Andrea.1234","world":2203,"created":"2018-05-18T17:42:00Z"}"#.utf8))
        routes["characters"] = .init(
            status: 200,
            body: Data(#"[{"name":"Andrea","race":"Human","gender":"Female","profession":"Mesmer","level":80,"age":10,"created":"2018-05-18T17:42:00Z","deaths":1,"crafting":[]}]"#.utf8))
        routes["account/wallet"] = .init(status: 200, body: Data(#"[{"id":1,"value":100},{"id":2,"value":5}]"#.utf8))
        routes["account/bank"] = .init(
            status: 200,
            body: Data(#"[{"id":19697,"count":3,"infusions":[null,301]},null]"#.utf8))
        routes["account/materials"] = .init(status: 200, body: Data(#"[{"id":19697,"category":5,"count":20}]"#.utf8))
        routes["account/inventory"] = .init(status: 200, body: Data(#"[{"id":19697,"count":1},null]"#.utf8))
        routes["inventory"] = .init(
            status: 200,
            body: Data(#"{"bags":[{"id":20,"size":5,"inventory":[{"id":19697,"count":2},null]}]}"#.utf8))
        routes["equipmenttabs"] = .init(status: 200, body: Data(#"[{"tab":1,"name":"Tab","is_active":true,"equipment":[]}]"#.utf8))
        routes["account/achievements"] = .init(status: 200, body: Data("[]".utf8))
        routes["account/recipes"] = .init(status: 200, body: Data("[]".utf8))
        routes["account/skins"] = .init(status: 200, body: Data("[]".utf8))
        routes["account/minis"] = .init(status: 200, body: Data("[]".utf8))
        routes["currencies"] = .init(
            status: 200,
            body: Data(#"[{"id":1,"name":"Coin","description":"","order":1},{"id":2,"name":"Karma","description":"","order":2}]"#.utf8))
        routes["items"] = .init(
            status: 200,
            body: Data(#"[{"id":19697,"name":"Mithril Ore","rarity":"Basic","type":"CraftingMaterial"}]"#.utf8))
        routes["materials"] = .init(
            status: 200,
            body: Data(#"[{"id":5,"name":"Basic Crafting Materials","items":[19697],"order":1}]"#.utf8))
        routes["professions"] = .init(
            status: 200,
            body: Data(#"[{"id":"Mesmer","name":"Mesmer","specializations":[66]}]"#.utf8))
        routes["worlds"] = .init(status: 200, body: Data(#"{"id":2203,"name":"Gandara"}"#.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path.replacingOccurrences(of: "/v2/", with: "")
        let querySchema = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value
        Self.lock.lock()
        if let querySchema { Self.lastSchema[path] = querySchema }
        if let headerSchema = request.value(forHTTPHeaderField: "X-Schema-Version") {
            Self.lastSchemaHeader[path] = headerSchema
        }
        Self.lock.unlock()
        let route = Self.route(for: path, query: url.query)
        let response = HTTPURLResponse(
            url: url, statusCode: route.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func route(for path: String, query: String?) -> PhaseSevenRoute {
        lock.lock(); defer { lock.unlock() }
        if let query, query.contains("ids=") {
            if let route = routes["\(path)?ids"] ?? routes["\(path)?ids="] { return route }
        }
        if let exact = routes[path] { return exact }
        let last = path.split(separator: "/").last.map(String.init) ?? path
        if let route = routes[last] { return route }
        let keys = routes.keys.sorted { $0.count > $1.count }
        if let match = keys.first(where: { path == $0 || path.hasSuffix("/" + $0) }) {
            return routes[match]!
        }
        return PhaseSevenRoute(status: 200, body: Data("[]".utf8))
    }
}

private func phaseSevenClient(
    credentials: CredentialStore = CredentialStore(secureStore: InMemorySecureStore()),
    cache: MetadataDiskCache = MetadataDiskCache(
        directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
) -> GW2APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PhaseSevenAPIProtocol.self]
    return GW2APIClient(session: URLSession(configuration: configuration), credentials: credentials, diskCache: cache)
}

@MainActor
private func phaseSevenAccountStore() -> AccountStore {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    return AccountStore(
        api: phaseSevenClient(cache: MetadataDiskCache(directory: directory.appending(path: "api"))),
        cache: MetadataDiskCache(directory: directory.appending(path: "account")))
}

private func fixture<T: Decodable>(_ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle(for: PhaseSevenDecodeHardeningTests.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private extension LossyDecodableArray {
    init(fromJSONFile name: String) throws {
        let url = try XCTUnwrap(Bundle(for: PhaseSevenDecodeHardeningTests.self).url(forResource: name, withExtension: "json"))
        self = try JSONDecoder().decode(LossyDecodableArray<Element>.self, from: Data(contentsOf: url))
    }
}

private extension SparseNullableArray {
    init(fromJSONFile name: String) throws {
        let url = try XCTUnwrap(Bundle(for: PhaseSevenDecodeHardeningTests.self).url(forResource: name, withExtension: "json"))
        self = try JSONDecoder().decode(SparseNullableArray<Element>.self, from: Data(contentsOf: url))
    }
}
