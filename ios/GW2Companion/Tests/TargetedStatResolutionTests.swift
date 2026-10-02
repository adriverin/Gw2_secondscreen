import XCTest
import os
@testable import GW2Companion

@MainActor
final class TargetedStatResolutionTests: XCTestCase {
    private let character = GW2Character(name: "Repair fixture", race: "Human", gender: "Male", profession: "Warrior", level: 80, age: 1)

    func testTargetedRepairRecomputesDefenseEquipmentRuneAndAutomaticMinorWithoutAccountRefresh() async throws {
        let record = CharacterEquipment(itemID: 48073, slot: "Coat", upgrades: [24771], stats: SelectedItemStats(id: 161, attributes: nil))
        var detail = CharacterDetailData()
        detail.equipmentTabs = [EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [record])]
        detail.buildTabs = [BuildTab(tab: 1, name: "Strength", isActive: true,
            build: CharacterBuild(name: nil, profession: "Warrior", specializations: [BuildSpecialization(id: 4, traits: [])], skills: .empty))]
        detail.source = .cached
        detail.updatedAt = Date(timeIntervalSince1970: 1000)
        detail.errorMessage = "Saved during an outage"
        let (store, directory) = try await makeStore(detail: detail)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = CharacterStatEngine.calculate(character: character, equipment: [record], items: [:])
        XCTAssertEqual(initial.defense.total, 0)
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        let repaired = try XCTUnwrap(store.characterDetails[character.name])
        let stats = CharacterStatEngine.calculate(character: character, equipment: repaired.equipmentTabs[0].equipment,
            items: repaired.items, build: repaired.buildTabs[0].build, traits: repaired.traits,
            specializations: repaired.specializations, itemStats: repaired.itemStats ?? [:])
        XCTAssertEqual(stats.defense.total, 381)
        XCTAssertEqual(stats.total(for: "Power"), 1141)
        XCTAssertEqual(stats.total(for: "Precision"), 1101)
        XCTAssertEqual(stats.total(for: "Ferocity"), 101)
        XCTAssertEqual(stats.attributes["Toughness"]?.runes, 25)
        XCTAssertEqual(stats.derived.criticalChanceBuildModifier, 5)
        XCTAssertEqual(repaired.source, .cached)
        XCTAssertEqual(repaired.updatedAt, detail.updatedAt)
        XCTAssertEqual(repaired.errorMessage, detail.errorMessage)
        XCTAssertTrue(StatCoverageReport(stats: stats, build: repaired.buildTabs[0].build, traits: repaired.traits, specializations: repaired.specializations).isComplete)
        XCTAssertTrue(store.statSourceProgress[character.name]?.allSatisfy { $0.status == "resolved" } == true)
        let paths = TargetedRepairProtocol.paths
        XCTAssertEqual(paths.count, 5)
        XCTAssertTrue(paths.contains { $0.contains("/equipment?") })
        XCTAssertTrue(paths.contains { $0.contains("items?ids=48073") })
        XCTAssertTrue(paths.contains { $0.contains("specializations?ids=4") })
        XCTAssertTrue(paths.contains { $0.contains("traits?ids=1446,1448,1453") })
        XCTAssertTrue(paths.contains { $0.contains("equipmenttabs/1?") })
        XCTAssertFalse(paths.contains { $0.contains("/account") || $0.contains("inventory") || $0.contains("wallet") || $0.contains("equipmenttabs?") })
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        XCTAssertEqual(TargetedRepairProtocol.paths.count, paths.count, "Complete cached sources require no network work")
        // The repaired cached snapshot remains browseable without network access.
        let api = GW2APIClient(credentials: CredentialStore(secureStore: InMemorySecureStore()), diskCache: MetadataDiskCache(directory: directory))
        let restored = AccountStore(api: api, cache: MetadataDiskCache(directory: directory))
        await restored.restoreCachedState()
        XCTAssertEqual(restored.characterDetails[character.name]?.items[48073]?.details?.defense, 381)
        XCTAssertEqual(restored.characterDetails[character.name]?.source, .cached)
    }

    func testMissingSelectableItemstatsOnlyFetchesSelectedPrefixAndCharacterEquipment() async throws {
        let record = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: nil))
        var detail = CharacterDetailData()
        detail.equipmentTabs = [EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [record])]
        detail.items = [30704: ItemMetadata(id: 30704, name: "Twilight", icon: nil, rarity: "Legendary", type: "Weapon",
            details: ItemDetails(type: "Greatsword", defense: 0, statChoices: [161], attributeAdjustment: 717.024))]
        let (store, directory) = try await makeStore(detail: detail)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        let repaired = try XCTUnwrap(store.characterDetails[character.name])
        let stats = CharacterStatEngine.calculate(character: character, equipment: repaired.equipmentTabs[0].equipment,
            items: repaired.items, itemStats: repaired.itemStats ?? [:])
        XCTAssertEqual(stats.total(for: "Power"), 1251)
        XCTAssertEqual(stats.total(for: "Precision"), 1179)
        XCTAssertEqual(stats.total(for: "Ferocity"), 179)
        XCTAssertEqual(TargetedRepairProtocol.paths.count, 3)
        XCTAssertTrue(TargetedRepairProtocol.paths.contains { $0.contains("itemstats?ids=161") })
        XCTAssertFalse(TargetedRepairProtocol.paths.contains { $0.contains("/items?") })
    }

    func testUnavailableTargetedRequestsPreserveCachedInputsAndStayIncomplete() async throws {
        let record = CharacterEquipment(itemID: 48073, slot: "Coat", stats: SelectedItemStats(id: 161, attributes: ["Power": 141]))
        var detail = CharacterDetailData()
        detail.equipmentTabs = [EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [record])]
        detail.source = .cached
        let (store, directory) = try await makeStore(detail: detail, unavailable: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        XCTAssertEqual(store.characterDetails[character.name]?.equipmentTabs, detail.equipmentTabs)
        XCTAssertEqual(store.characterDetails[character.name]?.source, .cached)
        XCTAssertTrue(store.statResolutionMessages[character.name]?.contains("ArenaNet") == true)
        XCTAssertFalse(store.resolvingStatCharacters.contains(character.name))
        XCTAssertTrue(store.statSourceProgress[character.name]?.allSatisfy { $0.status == "still unavailable" } == true)
    }

    func testAuthenticatedSunriseTabSelectionIsRepairedPersistedAndDiagnosedBeforeConversion() async throws {
        var detail = CharacterDetailData()
        detail.equipmentTabs = [EquipmentTab(tab: 1, name: "Active", isActive: true, equipment: [CharacterEquipment(itemID: 30703, slot: "WeaponA1")])]
        detail.items = [30703: ItemMetadata(id: 30703, name: "Sunrise", icon: nil, rarity: "Legendary", type: "Weapon",
            details: ItemDetails(type: "Greatsword", defense: 0, statChoices: [161], attributeAdjustment: 717.024))]
        let selected = EquipmentTab(tab: 1, name: "Active", isActive: true, equipment: [CharacterEquipment(itemID: 30703,
            slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: ["Power":251, "Precision":179, "CritDamage":179]), location: "EquippedFromLegendaryArmory")])
        let (store, directory) = try await makeStore(detail: detail, tabOverride: selected)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        let repaired = try XCTUnwrap(store.characterDetails[character.name])
        XCTAssertEqual(repaired.equipmentTabs[0].equipment[0].stats?.attributes?["Power"], 251)
        let diagnostic = try XCTUnwrap(store.statEquipmentDiagnostics[character.name]?.first)
        XCTAssertEqual(diagnostic.itemID, 30703)
        XCTAssertTrue(diagnostic.statsObjectPresent)
        XCTAssertEqual(diagnostic.selectedStatID, 161)
        XCTAssertFalse(diagnostic.summary.contains("local-test-key"))
        let api = GW2APIClient(credentials: CredentialStore(secureStore: InMemorySecureStore()), diskCache: MetadataDiskCache(directory: directory))
        let restored = AccountStore(api: api, cache: MetadataDiskCache(directory: directory))
        await restored.restoreCachedState()
        XCTAssertEqual(restored.characterDetails[character.name]?.equipmentTabs[0].equipment[0].stats, selected.equipment[0].stats)
    }

    func testFreshTabWithoutLegendarySelectionDoesNotReimportHistoricCachedPrefix() async throws {
        var detail = CharacterDetailData()
        let shoulder = CharacterEquipment(itemID: 4633, slot: "Shoulders")
        let historic = CharacterEquipment(itemID: 30703, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: ["Power":251]))
        detail.equipmentTabs = [EquipmentTab(tab: 1, name: "Active", isActive: true, equipment: [shoulder, historic])]
        detail.items = [30703: ItemMetadata(id: 30703, name: "Sunrise", icon: nil, rarity: "Legendary", type: "Weapon",
            details: ItemDetails(type: "Greatsword", defense: 0, statChoices: [161], attributeAdjustment: 717.024))]
        let fresh = EquipmentTab(tab: 1, name: "Active", isActive: true, equipment: [shoulder, CharacterEquipment(itemID: 30703, slot: "WeaponA1")])
        let (store, directory) = try await makeStore(detail: detail, tabOverride: fresh)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.resolveMissingStatSources(character: character, equipmentTab: 1, weaponSet: "A")
        let repaired = try XCTUnwrap(store.characterDetails[character.name])
        XCTAssertNil(repaired.equipmentTabs[0].equipment[1].stats)
        XCTAssertTrue(store.statEquipmentDiagnostics[character.name]?.contains { $0.itemID == 30703 && !$0.statsObjectPresent } == true)
    }

    private func makeStore(detail: CharacterDetailData, unavailable: Bool = false, tabOverride: EquipmentTab? = nil) async throws -> (AccountStore, URL) {
        let tabBody = (tabOverride ?? detail.equipmentTabs.first).flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        TargetedRepairProtocol.reset(unavailable: unavailable, tabBody: tabBody)
        let directory = FileManager.default.temporaryDirectory.appending(path: "target-stat-repair-\(UUID())")
        let cache = MetadataDiskCache(directory: directory)
        await cache.save(RepairSnapshot(characters: [character], characterDetails: [character.name: detail]), named: "account-snapshot")
        let credentials = CredentialStore(secureStore: InMemorySecureStore())
        try credentials.saveAPIKey("local-test-key-not-an-account-key")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TargetedRepairProtocol.self]
        let api = GW2APIClient(session: URLSession(configuration: configuration), credentials: credentials, diskCache: cache)
        let store = AccountStore(api: api, cache: cache)
        await store.restoreCachedState()
        XCTAssertNotNil(store.characterDetails[character.name])
        return (store, directory)
    }
}

private struct RepairSnapshot: Encodable, Sendable {
    let characters: [GW2Character]
    let characterDetails: [String: CharacterDetailData]
    var professions: [String: ProfessionMetadata] = [:]
    var characterInventories: [String: CharacterInventoryResponse] = [:]
    var bank: [InventorySlot] = []
    var sharedInventory: [InventorySlot] = []
    var materials: [AccountMaterial] = []
    var materialCategories: [Int: MaterialCategoryMetadata] = [:]
    var wallet: [WalletEntry] = []
    var currencies: [Int: CurrencyMetadata] = [:]
    var itemMetadata: [Int: ItemMetadata] = [:]
    var holdings: [AccountHolding] = []
}

private final class TargetedRepairProtocol: URLProtocol, @unchecked Sendable {
    private struct State { var paths: [String] = []; var unavailable = false; var tabBody = "{}" }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    static var paths: [String] { state.withLock { $0.paths } }
    static func reset(unavailable: Bool, tabBody: String) { state.withLock { $0 = State(unavailable: unavailable, tabBody: tabBody) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let unavailable = Self.state.withLock { value in value.paths.append(url.path + "?" + (url.query ?? "")); return value.unavailable }
        let body: String
        switch url.lastPathComponent {
        case "1": body = Self.state.withLock { $0.tabBody }
        case "equipment": body = #"{"equipment":[]}"#
        case "items": body = #"[{"id":48073,"name":"Zojja's Breastplate","rarity":"Ascended","type":"Armor","details":{"type":"Coat","defense":381,"attribute_adjustment":403.326,"infix_upgrade":{"id":161,"attributes":[{"attribute":"Power","modifier":141},{"attribute":"Precision","modifier":101},{"attribute":"CritDamage","modifier":101}]}}},{"id":24771,"name":"Superior Rune of Melandru","rarity":"Exotic","type":"UpgradeComponent","details":{"type":"Rune","infix_upgrade":{"id":112,"attributes":[]}}}]"#
        case "itemstats": body = #"[{"id":161,"name":"Berserker's","attributes":[{"attribute":"Power","multiplier":0.35,"value":0},{"attribute":"Precision","multiplier":0.25,"value":0},{"attribute":"CritDamage","multiplier":0.25,"value":0}]}]"#
        case "specializations": body = #"[{"id":4,"name":"Strength","profession":"Warrior","elite":false,"minor_traits":[1446,1448,1453],"major_traits":[1449]}]"#
        case "traits": body = #"[{"id":1446,"name":"Reckless Dodge","facts":[{"type":"NoData"}]},{"id":1448,"name":"Building Momentum","facts":[{"type":"Number","value":15}]},{"id":1453,"name":"Pinnacle of Strength","facts":[{"type":"AttributeAdjust","target":"Power","value":10},{"type":"Percent","percent":5}]}]"#
        default: body = #"{"text":"unexpected endpoint"}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: unavailable ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
